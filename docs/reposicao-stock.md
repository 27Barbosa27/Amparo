# Reposição de stock ("Comprei mais")

Estado: por implementar. Depende de [[plano]] (secção das receitas) e da alteração de 25/11/2026 que tornou obrigatório o campo "Quantos tem agora?" ao criar uma receita.

## Problema

O stock de uma receita é `unidadesIniciais − tomas tomadas × unidades por toma` (`backend/src/medicacao/stock.ts`). `unidadesIniciais` só se define ao criar a receita. Quando a pessoa compra outra caixa, não há forma de o dizer: o stock continua a descer, a app avisa "só chega para N dias" quando já não é verdade, e o alerta de "receita a acabar" dispara por engano.

A única saída hoje seria editar `unidadesIniciais` à mão. Isso falsifica a barra de progresso (`restantes / iniciais`) e perde-se o histórico do que foi comprado.

## O que se quer

1. **Comprei mais:** somar N unidades ao stock de uma receita, em dois toques.
2. **Acertar o stock:** dizer "tenho exatamente N", para corrigir diferenças (um comprimido caiu, a contagem estava errada).
3. Todo o cálculo existente (dias restantes, "só chega para…", alerta push) passa a usar o stock real, sem mais alterações.

Fora de âmbito: preço, farmácia, lembrete de compra, código de barras.

## Decisões

| Decisão | Escolha | Porquê |
|---|---|---|
| Onde guardar as compras | Tabela nova `reposicoes`, uma linha por compra | Mantém `unidades_iniciais` intacto (a barra continua certa) e dá histórico e auditoria |
| Como se acerta o stock | Calcula-se um `unidades_iniciais` novo no servidor, para que `restantes = N` | Não é preciso um segundo mecanismo |
| Unidade | Comprimidos/unidades, como o formulário | Caixas ficam para depois (ver "Mais tarde") |
| Quem pode | Quem tem acesso de escrita ao perfil (o mesmo de `PATCH /receitas/:id`) | Reutiliza as regras que já existem |
| Receitas sem stock (`unidades_iniciais` nulo) | Primeiro "Acertar", que define o stock; "Comprei mais" fica desativado até lá | Sem base não há a que somar |

## Backend

### 1. Migração `1763800000010_reposicoes.sql`

Seguir o estilo das migrações existentes (ver `1763800000009_verificacao-email.sql`).

```sql
create table reposicoes (
  id uuid primary key default gen_random_uuid(),
  receita_id uuid not null references receitas(id) on delete cascade,
  profile_id uuid not null references profiles(id) on delete cascade,
  unidades int not null check (unidades > 0 and unidades <= 100000),
  user_id uuid references users(id) on delete set null,
  criado_em timestamptz not null default now()
);
create index reposicoes_receita_idx on reposicoes (receita_id);
```

Confirmar o nome real da tabela de perfis e se as outras tabelas têm políticas de acesso por perfil; copiar o padrão.

### 2. `stock.ts`

`calcularStock` ganha um parâmetro `repostas` (soma das reposições), com valor por omissão 0 para não partir os testes existentes:

```ts
const unidadesRestantes = Math.max(0, unidadesIniciais + repostas - tomadas * porToma);
```

O `Stock` devolvido passa a incluir `unidadesTotais: unidadesIniciais + repostas`, para a app calcular a barra como `restantes / totais`.

### 3. `servico.ts`

- `COLUNAS_RECEITA`: acrescentar a soma `(select coalesce(sum(unidades), 0)::int from reposicoes r where r.receita_id = receitas.id) as repostas`, ao lado de `tomadas`.
- `LinhaReceita` e `paraReceita`: passar `l.repostas` a `calcularStock`.
- Funções novas:
  - `registarReposicao(db, userId, profileId, receitaId, unidades, ip)`: insere a linha e audita `receita.reposicao`. Se `unidades_iniciais` for nulo, falha com `ErroAuth('sem_stock', 409)`.
  - `acertarStock(db, mestra, userId, profileId, receitaId, unidadesAgora, ip)`: lê a receita, calcula `iniciais = unidadesAgora + tomadas × porToma − repostas` (mínimo 0), grava em `unidades_iniciais` e audita `receita.acerto_stock`. Aceita receitas sem stock (é a forma de o definir).
  - `desfazerReposicao(db, userId, profileId, receitaId, reposicaoId)`: só se tiver menos de 5 minutos, para corrigir um erro de escrita. Audita.

### 4. `rotas.ts`

| Pedido | Corpo | Resposta |
|---|---|---|
| `POST /receitas/:id/reposicoes` | `{ unidades: int 1..100000, idempotencyKey? }` | `201` com a receita atualizada |
| `DELETE /receitas/:id/reposicoes/:reposicaoId` | | `204` |
| `PUT /receitas/:id/stock` | `{ unidadesAgora: int 0..100000 }` | `200` com a receita atualizada |

Validar com `zod` como as outras rotas. A idempotência segue a de `tomas/registo.ts`: guardar a chave na linha e devolver o resultado sem repetir. O `POST` é o único que um reenvio pode duplicar.

### 5. Alertas

`alertarReceitasAAcabar` (`jobs/trabalhos.ts`) já usa `r.stock.diasRestantes`, por isso passa a ver o stock reposto sem alterações. Como o aviso é "no máximo um por receita e por dia", não é preciso limpar nada depois de repor.

### 6. Testes (`backend/tests/stock.test.ts` e `tomas.test.ts`)

- Unitário: `calcularStock` com `repostas`; 24 iniciais + 24 repostas, 2 por dia, dá 24 dias.
- Integração: criar receita com 24 → `POST reposicoes` 24 → `stock.unidadesRestantes` 48; marcar uma toma → 47.
- `PUT stock` com 10 dá `unidadesRestantes: 10`, mesmo depois de tomas e reposições.
- `sem_stock` 409 numa receita sem unidades; um utilizador sem acesso ao perfil recebe 404; `unidades: 0` e `-1` dão 400.
- Reenvio com a mesma `idempotencyKey` não duplica.

## App

### 1. Modelo e repositório

- `Receita` (`modelos.dart`): ler `unidadesTotais` do stock; `fracaoRestante` passa a `restantes / totais`.
- `Repositorio` (`repositorio.dart`): `Future<void> reporStock(String perfilId, String receitaId, int unidades)` e `Future<void> acertarStock(String perfilId, String receitaId, int unidadesAgora)`.
- `RepositorioApi`: os pedidos acima (a chave de idempotência gera-se como em `marcarTomada`).
- `test/apoio/repositorio_memoria.dart`: a versão falsa implementa os dois.

### 2. Controlador

`ReceitasControlador` (`estado/receitas_controlador.dart`): métodos `reporStock` e `acertarStock` que chamam o repositório e recarregam as receitas; erro guardado em `erro`, como os outros.

### 3. Ecrãs (`outros.dart`)

- **Folha "Comprei mais":** campo numérico, botão "Adicionar". Sugerir o valor da última compra (guardar o último valor por receita em memória; não precisa de persistência).
- **Onde se abre:**
  - botão "Comprei mais" no cartão `_AvisoAAcabar`, ao lado de "Pedir renovação ao médico";
  - entrada no menu de opções de cada receita, junto com "Acertar stock".
- **"Só chega para N dias":** passa a ter o botão "Comprei mais" à frente, porque é aí que a pessoa percebe o problema.
- **Acertar stock:** a mesma folha, com o texto "Quantos tem agora?" e o valor atual escrito.
- Depois de repor, a mensagem "Stock atualizado: restam X unidades, chega para Y dias" (reaproveitar o estilo das mensagens de sucesso já existentes).

### 4. Testes

- `pessoas_receitas_test.dart`: repor 24 numa receita a acabar tira o aviso "Acaba em N dias" e atualiza os dias; o acerto mostra o valor escrito; valor vazio ou `0` na reposição dá erro por baixo do campo.

## Ordem de trabalho

1. Migração, `calcularStock` e testes unitários.
2. `servico.ts` e rotas, com os testes de integração.
3. `Repositorio`, `RepositorioApi`, memória e controlador.
4. Folha e botões, com os testes de widget.
5. Passar tudo: `npm test` e `flutter analyze && flutter test`.

## Pontos de atenção

- **Receitas já criadas sem stock:** não há a que repor. "Acertar" resolve (define o stock agora).
- **Alterar a dose a meio:** `calcularStock` usa a dose atual para todas as tomas passadas, por isso mudar de 1 para 2 comprimidos falseia o stock já gasto. Já acontece hoje; se incomodar, guardar a dose por toma. Não faz parte deste trabalho.
- **Tomas por registar offline:** o stock só desce quando a toma chega ao servidor (ver [[fila-offline]]). Aceitável: o erro é de poucas unidades e corrige-se ao sincronizar.
- **Auditoria:** as reposições e os acertos entram em `audit_logs`; não guardam nomes de medicamentos.

## Mais tarde

- Unidade "caixas": guardar `unidades_por_caixa` na receita e aceitar "2 caixas".
- Lembrete de compra a X dias do fim (já há `dias_antes` nas preferências de alerta).

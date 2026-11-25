# Vários cuidadores por pessoa

Estado: por implementar. Complementa [[plano]] (acesso a perfis, alertas) e [[dpia-rascunho]] (dados de saúde de terceiros).

## Problema

Quem cuida de uma pessoa raramente é uma só pessoa: os filhos de uma senhora idosa, o casal que cuida do pai, uma cuidadora em horário e a família à distância. Hoje:

- o perfil de uma pessoa pertence a **uma conta** (papel `owner`);
- para outro familiar ver ou marcar tomas, só há a opção de partilhar a palavra-passe, o que é inseguro e esconde quem fez o quê;
- não há forma de convidar, listar, limitar ou tirar acesso a ninguém.

O resultado são chamadas do tipo "já deste o comprimido ao pai?" e tomas dadas duas vezes, que é precisamente o que a app devia evitar.

## O que já existe (e não se refaz)

| Peça | Onde | O que dá |
|---|---|---|
| Acesso por perfil | `profile_access (user_id, profile_id, papel, autorizacao_declarada_em, revogado_em)` | A base: já é muitos-para-muitos; o `primary key (user_id, profile_id)` permite vários cuidadores |
| Papéis | `papel_acesso = 'owner' \| 'caregiver'` e `exigirPapel('owner')` em `perfis/rotas.ts` | Exportar, editar e apagar o perfil só pelo dono |
| Verificação única | `resolverAcesso` (`perfis/acesso.ts`) | Corre em todos os pedidos e já ignora acessos revogados: revogar tem efeito imediato |
| Alertas por cuidador | `alert_prefs (user_id, profile_id, …)` | Cada pessoa escolhe os seus avisos, e o push só vai a quem tem acesso ativo |
| Quem registou | `tomas.registada_por_user_id`, "Marcada pela Ana" | Já se vê quem deu o medicamento |
| Chaves de cifra | A chave de cada perfil está no servidor, protegida pela `PROFILE_MASTER_KEY` | Partilhar um perfil **não exige trocar chaves**: dar acesso é só inserir uma linha |
| Código de uso único | `pairing_codes` + `resgatarCodigo` (`dispositivos/servico.ts`) | Padrão a copiar para os convites: hash com pepper, expira, uso único, limite de tentativas |

Falta o **convite**, a **lista de cuidadores**, o **papel só de leitura**, a **saída/remoção** e os **ecrãs**.

## Decisões

| Decisão | Escolha | Porquê |
|---|---|---|
| Como se convida | O dono gera um **código de 8 caracteres**, válido 48 horas, uso único, e partilha-o como quiser (mensagem, chamada) | Não depende de email nem de domínio configurado; é o mesmo modelo da ligação do telemóvel. Ligações diretas ficam para depois |
| Quem aceita | Alguém com **conta própria**, que introduz o código e declara que a pessoa autorizou | Cada cuidador tem credenciais e histórico próprios; a declaração fica em `autorizacao_declarada_em` como no perfil original |
| Papéis | `owner`, `caregiver` (já existem) e **`viewer`** (novo, só ver) | Um familiar à distância quer ver, não mexer nas receitas |
| Quem convida | Só o `owner` | Dar acesso a dados de saúde é a decisão mais sensível |
| Limite | 5 cuidadores ativos por perfil | Evita abuso e é suficiente para o caso real |
| Mensagem de erro | Um só código `convite_invalido` para inexistente, expirado ou usado | Não revela que códigos existem (igual a `codigo_invalido`) |
| Várias contas "dono" | Não: um só `owner`; passar a titularidade é uma ação explícita (fase 3) | Mantém claro quem responde pelos dados |

### Quem pode fazer o quê

| Ação | Dono | Cuidador | Leitor |
|---|:-:|:-:|:-:|
| Ver tomas, receitas, histórico, adesão | sim | sim | sim |
| Marcar, saltar, desfazer tomas | sim | sim | não |
| Criar, editar receitas; repor stock | sim | sim | não |
| Ligar o telemóvel da pessoa | sim | sim | não |
| Convidar, mudar papéis, remover cuidadores | sim | não | não |
| Editar ou apagar o perfil, exportar dados | sim | não | não |
| Sair do perfil | não (primeiro passa a titularidade ou apaga) | sim | sim |

Hoje as rotas de escrita só exigem acesso ativo, por isso um `viewer` conseguiria escrever. Há de acrescentar-se `exigirEscrita` (nega a `viewer`) a todas as rotas que alteram dados: tomas (`registo`, `saltar`, `desfazer`), medicamentos e receitas, códigos de ligação.

## Backend

### 1. Migrações

**`…10_papel-leitor.sql`** (separada, porque `alter type … add value` não se mistura com outros comandos na mesma transação):

```sql
alter type papel_acesso add value if not exists 'viewer';
```

**`…11_convites.sql`**:

```sql
create table convites (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles (id) on delete cascade,
  criado_por_user_id uuid not null references users (id) on delete cascade,
  papel papel_acesso not null check (papel in ('caregiver', 'viewer')),
  codigo_hash bytea not null,
  expira_em timestamptz not null,
  usado_em timestamptz,
  usado_por_user_id uuid references users (id) on delete set null,
  criado_em timestamptz not null default now()
);
create index convites_ativos_idx on convites (codigo_hash) where usado_em is null;
create index convites_perfil_idx on convites (profile_id);
```

Confirmar com as migrações existentes o nome real da tabela de perfis e seguir o padrão de índices.

### 2. Serviço (`perfis/convites.ts`, novo)

- `criarConvite(db, pepper, userId, profileId, papel, ip)`: confirma que há menos de 5 cuidadores ativos (`convites_cheio` 409); invalida convites pendentes do mesmo perfil e papel; gera 8 caracteres de um alfabeto sem ambiguidades (sem `0 O 1 I L`); guarda só o hash (HMAC com o pepper, como `hashCodigo`); audita `convite.criar`. Devolve o código **uma só vez**.
- `aceitarConvite(db, pepper, userId, codigo, declaraAutorizacao, ip)`: dentro de uma transação, `select … for update` ao convite pelo hash. Se for inválido, expirado ou usado: `convite_invalido` (404). Exige `declaraAutorizacao === true`. Se o utilizador já tem acesso ativo: `ja_tem_acesso` (409). Se tem uma linha revogada: reativa-a (`revogado_em = null`, novo papel, nova declaração). Senão, insere. Cria o `alert_prefs` com os valores por omissão (como o perfil original). Marca o convite usado. Audita `convite.aceitar`. Avisa os restantes membros (ver Alertas).
- `listarConvites`, `cancelarConvite`: só do dono; devolvem papel e hora de expiração, nunca o código.
- `listarMembros(db, profileId)`: `user_id` (opaco), nome de exibição, papel, desde quando, e quem convidou. **Nunca** o email.
- `alterarPapel(db, donoId, profileId, userId, papel)`: dono muda entre `caregiver` e `viewer`; não mexe em si próprio. Audita `membro.papel`.
- `removerMembro(db, quemPede, profileId, userId, ip)`: o dono remove qualquer um que não seja ele; qualquer um se remove a si (`sair`), exceto o dono. Faz `revogado_em = now()`; não apaga a linha (guarda-se o historial e a auditoria). Os registos de tomas feitos por essa pessoa mantêm-se e continuam a mostrar o nome. Audita `membro.remover`.

### 3. Rotas

| Pedido | Quem | Corpo | Resposta |
|---|---|---|---|
| `POST /profiles/:id/convites` | dono | `{ papel: 'caregiver' \| 'viewer' }` | `201 { id, codigo, expiraEm }` |
| `GET /profiles/:id/convites` | dono | | pendentes (sem código) |
| `DELETE /profiles/:id/convites/:cid` | dono | | `204` |
| `POST /convites/aceitar` | qualquer conta autenticada | `{ codigo, declaraAutorizacao: true }` | `201` com o perfil (papel incluído) |
| `GET /profiles/:id/membros` | qualquer membro | | lista |
| `PATCH /profiles/:id/membros/:userId` | dono | `{ papel }` | `200` |
| `DELETE /profiles/:id/membros/:userId` | dono, ou o próprio | | `204` |

`POST /convites/aceitar` tem limite de pedidos por conta e por IP (reutilizar o que `pairing/redeem` usa), e responde `demasiadas_tentativas` como os outros.

### 4. Alertas (`push/servico.ts`, `jobs/trabalhos.ts`)

O essencial já funciona: `alert_prefs` é por cuidador e as consultas juntam `profile_access` com `revogado_em is null`. Faltam três coisas:

1. **Novo cuidador:** ao aceitar, push ao dono e aos cuidadores: "O Rui passou a acompanhar a Maria." (visibilidade: ninguém entra sem que os outros saibam).
2. **Toma não confirmada:** hoje avisa quem tem `toma_nao_confirmada`. Com vários, quem recebe vê o aviso mesmo que outro já tenha tratado. Acrescentar `tomaTratada` ao fluxo: quando a toma é registada, enviar um push silencioso de "limpeza" ou, mais simples, garantir que o aviso se atualiza ao abrir a app (a lista de tomas já vem do servidor). Fase 2.
3. **Leitores:** só recebem alertas se escolherem; por omissão desligados, para não gerarem ruído a quem apenas acompanha.

### 5. Segurança

- O código vale 48 h e uma vez. Guarda-se só o hash.
- Todas as respostas de erro de convite são iguais; limite de tentativas por IP e por conta.
- Revogar é imediato (`resolverAcesso`). Confirmar com um teste: depois de removido, o mesmo token de sessão recebe 404 em tudo.
- A remoção **não** apaga dados pessoais da pessoa acompanhada, só o acesso.
- `autorizacao_declarada_em` e `autorizacao_versao` registam o que o novo cuidador declarou; usar o texto da versão em vigor.
- Auditoria: `convite.criar`, `convite.aceitar`, `convite.cancelar`, `membro.papel`, `membro.remover`. Atualizar o texto da [[dpia-rascunho]] e da [[politica-privacidade-rascunho]]: passa a haver partilha de dados de saúde entre contas, por decisão do dono e com a autorização da pessoa.
- Quando o dono apaga a conta, `auth/conta.ts` já passa a titularidade a outro cuidador; confirmar que escolhe um `caregiver` e nunca um `viewer`.

### 6. Testes (`backend/tests/`)

- Convidar, aceitar e ver o perfil; o novo cuidador marca uma toma e o nome aparece.
- Código usado, expirado ou inexistente: todos `convite_invalido`; reaproveitar um código usado falha.
- Limite de 5; cuidador a convidar dá 404/403; `viewer` a escrever dá 403 em cada rota de escrita (uma verificação por rota).
- Remover: o acesso acaba logo; as tomas marcadas continuam com o nome; um alerta já não lhe chega.
- Reativar uma linha revogada.
- Sair: o dono não pode; um cuidador pode.
- IDOR: o cuidador de A não lista membros nem convites do perfil de B.

## App

Estas funcionalidades não pertencem às Definições: devem estar onde a pessoa já está.

### Onde aparece

- **No cartão da pessoa**, em "Hoje": uma linha "Quem cuida da Maria" com as iniciais dos cuidadores e o botão "Convidar". Toca para abrir a lista.
- **Quando a conta não tem ninguém** (primeira vez, ao lado de "Adicionar pessoa"): "Tenho um convite", para quem recebeu um código.

### Ecrãs

1. **Convidar:** escolher o papel com duas explicações curtas ("Cuidador: pode marcar tomas e editar receitas" e "Leitor: só vê"); botão "Gerar convite". Mostra o código grande, a validade ("Vale 48 horas") e "Partilhar" (folha do sistema). O código desaparece quando se sai do ecrã: não se pode voltar a ver, só gerar outro.
2. **Quem cuida de [nome]:** lista com nome, papel e "desde"; o dono vê "⋯" para mudar o papel ou remover; qualquer um vê "Sair". Convites pendentes (sem código) com "Cancelar".
3. **Tenho um convite:** campo do código e a declaração "Confirmo que a pessoa acompanhada autorizou que eu veja a sua informação". O botão só fica ativo com a declaração, como em "Adicionar pessoa". Depois mostra o resultado no ecrã de sucesso unificado.
4. **Leitor:** os botões de marcar, saltar, editar e repor ficam escondidos (não só desativados), e uma nota "Só pode ver" no topo.

### Código

- `Perfil` (`modelos.dart`) ganha `papel` (`dono`, `cuidador`, `leitor`); a UI decide o que mostra a partir daí. O servidor continua a ser quem decide: a app nunca é a única proteção.
- `Repositorio`: `criarConvite`, `convites`, `cancelarConvite`, `aceitarConvite`, `membros`, `alterarPapel`, `removerMembro`. Implementação em `RepositorioApi` e versão falsa em `test/apoio/repositorio_memoria.dart`.
- Controlador novo `MembrosControlador` (carregar, convidar, remover), no estilo dos que já existem em `estado/`.
- Textos em pt-PT e sem jargão ("convite", "cuidador", "leitor"; sem "papel" nem "acesso").

### Testes

- Convidar mostra o código e "Partilhar"; sair do ecrã não o volta a mostrar.
- Aceitar com declaração; botão desativado sem ela; `convite_invalido` mostra a mensagem certa.
- Um leitor não vê os botões de escrita; o dono vê "Convidar".
- Remover pede confirmação e atualiza a lista.

## Ordem de trabalho

**Fase 1 (o essencial, usável):**
1. Migrações e `exigirEscrita` em todas as rotas de escrita (isto fecha a falha dos leitores antes de existirem).
2. Convites: criar, aceitar, cancelar; membros: listar, remover, sair. Testes de backend.
3. App: papel no modelo, "Tenho um convite", "Convidar", lista de cuidadores.
4. Aviso aos restantes quando alguém entra.

**Fase 2:**
5. Alterar papel; papel de leitor completo na app.
6. Deixar de mostrar o aviso de toma não confirmada a quem já não precisa (toma tratada por outro).
7. Ecrã de atividade ("Quem fez o quê") com os últimos registos.

**Fase 3:**
8. Passar a titularidade a outro cuidador.
9. Ligações diretas em vez de código (precisa do domínio e de links de aplicação).
10. "Estou a tratar disto": um cuidador reclama uma toma e os outros veem-no.

## Riscos e pontos de atenção

- **Convite partilhado por engano:** um código a chegar à pessoa errada dá acesso a dados de saúde. Mitigações: 48 h, uso único, aviso a todos quando alguém entra, o dono pode remover logo. Considerar mostrar ao dono o nome de quem entrou antes de ficar ativo (aprovação em dois passos) se a DPIA o pedir.
- **Dois cuidadores a dar o mesmo comprimido:** o primeiro registo ganha; o segundo recebe `toma_ja_registada` e a app mostra "A Ana já registou esta toma às 08:02" (a mensagem, e não o erro técnico). Ver também [[fila-offline]], onde a mesma regra decide conflitos.
- **A pessoa acompanhada:** o telemóvel dela (ligado por código, sem conta) é outro tipo de acesso e não muda. O cuidador que a convida vê-a ligada; não se esquece de a mostrar na lista de quem tem acesso (tem de aparecer como "Telemóvel da Maria", não como cuidador).
- **RGPD:** o dono declara a autorização da pessoa ao criar o perfil, e cada cuidador declara-a de novo ao entrar. Se a pessoa pedir para retirar o consentimento, o dono tem de poder remover todos e apagar o perfil. Já existe `DELETE /profiles/:id`; confirmar que revoga também os convites pendentes.

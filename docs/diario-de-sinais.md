# Diário de sinais (peso, tensão, glicemia, temperatura, dor)

Estado: **proposta para decidir**. Relacionado com [[plano]], [[design]], [[sintomas-e-efeitos]], [[varios-cuidadores]], [[plano-pago]] e [[consultas-e-analises]].

> **Para quem vai implementar: desenhar primeiro.** Antes de escrever código na app, desenhar os ecrãs no artefacto do Claude Design (https://claude.ai/artifact/M1NgwcwbWDTxp2fK6r7s9R, ver [[design]]) e só depois implementar. A lista do que desenhar está em "Desenho (fazer primeiro)". O servidor pode avançar em paralelo. No fim, atualizar a contagem de ecrãs em [[design]].

## Antes de tudo: a linha que não se cruza

Esta é a funcionalidade **mais próxima** da linha "a app não substitui o médico". Por isso fica registada à cabeça, e a implementação só avança se as regras abaixo forem cumpridas **todas**.

**A app é um caderno com gráfico.** Guarda o que a pessoa mediu e mostra-o por ordem do tempo. Não diz se o valor é bom ou mau.

| A app **faz** | A app **nunca faz** |
|---|---|
| Guardar o valor, a unidade, a hora e uma nota | Dizer "normal", "alto", "baixo", "elevado", "preocupante" |
| Desenhar o valor num gráfico simples e numa lista | Colorir valores (verde, amarelo, vermelho) segundo um critério |
| Mostrar a escala e as unidades que a pessoa escolheu | Mostrar **intervalos de referência** ou "valores normais" |
| Avisar se um valor parece um **erro de escrita** (1300 kg) e pedir que o confirme | Bloquear ou comentar um valor plausível, por extremo que seja |
| Incluir o período no resumo para o médico, tal como foi registado | Descrever tendências em texto ("a sua tensão subiu") |
| Lembrar de medir, **se a pessoa o configurou** | Sugerir quando ou com que frequência medir |

**Critério de avançar (go / no-go):** só se implementa se, na revisão do desenho, **nenhum ecrã** usar cor, ícone ou texto que classifique um valor. Se uma versão do desenho o fizer, volta atrás.

## Para que serve

Quem tem hipertensão, diabetes ou um problema cardíaco mede valores em casa, e leva um papel (ou nada) à consulta. Os valores dispersos não ajudam; **uma lista e um gráfico simples, por ordem do tempo, ajudam o médico a decidir**, e a decisão continua a ser dele.

## O que se quer

1. **Registar uma medição** em poucos toques: tipo, valor, hora.
2. **Ver a evolução** num gráfico simples e numa lista, por períodos (7 dias, 30 dias, 6 meses).
3. **Levar à consulta** (o período escolhido entra no resumo para o médico).
4. **Lembrar de medir**, só se a pessoa ou o cuidador o definirem (fase 2).

## Decisões

| Decisão | Escolha | Porquê |
|---|---|---|
| Que sinais | Peso, tensão arterial (sistólica e diastólica, com pulso opcional), glicemia, temperatura, dor (0 a 10, a escolha da pessoa), saturação de oxigénio, frequência cardíaca | Os mais usados em casa. "Outro" com nome e unidade livres |
| Unidades | A pessoa escolhe a unidade (glicemia em mg/dL ou mmol/L, peso em kg ou lb, temperatura em °C ou °F); por omissão as de Portugal | A app não converte para decidir nada; só para desenhar o gráfico |
| Contexto | Etiquetas opcionais e neutras ("em jejum", "depois de comer", "antes de dormir", "depois de exercício") e uma nota livre | Quem lê a lista precisa de saber como foi medido; **as etiquetas são o que a pessoa escolhe, a app não as sugere** |
| Quem escreve | Dono, cuidador, e a própria pessoa no seu telemóvel (fase 2) | Quem mede é, muitas vezes, a própria pessoa |
| Quem lê | Dono, cuidadores e leitor | Como as receitas |
| Plano | Plano pago ([[plano-pago]]) | Ocupa mais dados e é de uso avançado; **nunca** impede alarmes nem alertas |
| Dispositivos | Fora de âmbito na primeira versão (ver "Mais tarde") | Complexo e com permissões sensíveis |

## Modelo de dados

```sql
create table sinais (
  id uuid primary key,                    -- gerado na app: reenvio idempotente
  profile_id uuid not null references profiles (id) on delete cascade,
  dados_cifrados bytea not null,          -- JSON cifrado: { tipo, valor, valor2?, unidade, etiquetas, nota }
  medido_em timestamptz not null,
  autor_user_id uuid references users (id) on delete set null,
  autor_dispositivo_id uuid references profile_devices (id) on delete set null,
  criado_em timestamptz not null default now(),
  editado_em timestamptz,
  check (num_nonnulls(autor_user_id, autor_dispositivo_id) <= 1)
);
create index sinais_perfil_tempo_idx on sinais (profile_id, medido_em desc);
```

- **Tudo o que descreve a medição vai cifrado**, incluindo o tipo: saber que alguém regista glicemia já revela uma doença. A hora fica à vista para se poder pedir um intervalo.
- O servidor decifra (a chave do perfil está nele) e **filtra por tipo depois** de ler o intervalo pedido. O volume é pequeno (uma pessoa raramente passa das poucas centenas de medições por mês).
- Sem tabela de intervalos de referência, sem limites, sem alertas: **não existem no modelo de propósito**.

## Backend

### Rotas (`backend/src/sinais/`, novo módulo)

| Pedido | Quem | Corpo / filtros | Resposta |
|---|---|---|---|
| `GET /profiles/:id/sinais` | membros e a pessoa | `?de=&ate=&tipo=` | lista por data |
| `POST /profiles/:id/sinais` | dono, cuidador (e a pessoa, fase 2) | `id`, `tipo`, `valor`, `valor2?`, `unidade`, `etiquetas?`, `nota?`, `medidoEm` | `201` |
| `PATCH /profiles/:id/sinais/:sid` | autor, ou dono | qualquer campo | `200` |
| `DELETE /profiles/:id/sinais/:sid` | autor, ou dono | | `204` |

- Validação com `zod`: `medidoEm` não pode estar mais de 5 minutos no futuro; intervalos pedidos até 92 dias por vez (como o histórico das tomas).
- **Validação de plausibilidade só para apanhar gralhas**, nunca para classificar. Quando o valor cai fora de um intervalo muito largo, o servidor responde `valor_a_confirmar` e a app pede "Escreveu 1300. Confirma?". Se a pessoa confirmar, **o valor grava-se sem comentários**. Intervalos largos propostos:

  | Sinal | Aceita sem perguntar | Pede confirmação fora de |
  |---|---|---|
  | Peso (kg) | 2 a 400 | 2 a 400 |
  | Tensão sistólica / diastólica | 40 a 300 / 20 a 200 | idem |
  | Glicemia (mg/dL) | 10 a 1000 | idem |
  | Temperatura (°C) | 30 a 45 | idem |
  | Dor | 0 a 10 | recusa fora (é uma escala) |
  | Saturação (%) | 50 a 100 | idem |
  | Frequência cardíaca (bpm) | 20 a 300 | idem |

  Estes limites existem para **erros de digitação**, não para dizer o que é saudável. Documentá-lo no código e nos testes.
- Auditoria sem conteúdo: `sinal.criar`, `sinal.editar`, `sinal.apagar`.
- A exportação do perfil inclui os sinais.

### Testes

- Criar cada tipo; unidade e valor guardados cifrados (ler a coluna).
- Um valor fora do intervalo largo pede confirmação, e depois de confirmado grava-se tal como veio.
- Leitor lê mas não escreve; sem acesso ao perfil dá 404.
- Idempotência pelo `id`.
- **Teste de contrato:** nenhuma resposta da API contém campos como `normal`, `alto`, `baixo`, `estado`, `gravidade`.

## App

### Modelo e estado

- `Sinal`, `TipoSinal`, e a lógica de gráficos em `dominio/`, sem dependências de UI.
- `Repositorio`: `sinais(perfilId, de, ate, {tipo})`, `criarSinal`, `alterarSinal`, `apagarSinal`; versão real e falsa.
- `SinaisControlador` em `estado/`.
- Sem rede, o registo entra na fila ([[fila-offline]]).

### Onde aparece (fora das Definições)

- No cartão da pessoa: uma linha "Medições" com a última (por exemplo, "Tensão 128/82, hoje às 08:10"), sem cor nem classificação.
- Abre a **lista e o gráfico**, com o seletor de período (como o histórico de tomas: 7 dias, 30 dias, 6 meses).

### Registar

- Escolher o sinal (os mais recentes à frente), teclado numérico grande, hora ("agora" por omissão), etiquetas opcionais, nota.
- Tensão: dois campos (sistólica e diastólica) e um terceiro, opcional, para o pulso.
- Confirmar fora do intervalo largo (ver acima).
- Ecrã de sucesso unificado.

### Gráfico

- Linha fina com pontos, num só tom do tema (a cor principal), um gráfico por sinal. A tensão desenha **duas** linhas (sistólica e diastólica) distinguidas por forma e rótulo, não só por cor.
- Toque num ponto: valor, hora, etiquetas e nota.
- **Alternativa em tabela** (a lista) para leitores de ecrã e para quem prefere números: o gráfico não pode ser a única forma de ver.
- Eixo ajustado ao intervalo dos dados. Sem linhas de referência, sem zonas coloridas.
- **Linha de objetivo opcional, fora da primeira versão:** o médico pode ter dito "135/85". Mostrar uma linha com essa meta, escrita pela pessoa, parece inofensivo, mas leva rapidamente a colorir valores fora dela, que é classificar. **Recomendação: deixar de fora.** Se se avançar, a linha só pode ser neutra, rotulada "Objetivo indicado pelo médico (nota sua)", e nunca pode haver cor nos pontos que a ultrapassam.

### Lembretes de medição (fase 2)

Uma "medição" configurada como uma toma sem medicamento: o cuidador ou a pessoa escolhe o sinal e as horas, e a app lembra. A app **não sugere** quando ou com que frequência medir; o texto do alarme é "Hora de registar a tensão." Reutiliza o mecanismo de lembretes já previsto em [[plano]].

### Testes

- O gráfico mostra um ponto por medição e a tabela mostra a mesma informação.
- A tensão tem duas séries distinguíveis sem cor.
- Nenhum widget desta funcionalidade usa cores de semáforo; teste que procura cores de estado (`aviso`, `erro`, `ok`) no código dos ecrãs de sinais.
- Nenhum texto contém "normal", "alto", "baixo", "elevado", "preocupante", "recomendamos".

## Desenho (fazer primeiro)

No artefacto do Claude Design, nos temas claro e escuro. **Rever cada ecrã contra a tabela "faz / nunca faz" no início.**

1. **Linha "Medições"** no cartão da pessoa, com e sem registos.
2. **Registar:** escolha do sinal, teclado numérico grande, tensão com dois campos, etiquetas, nota, "Confirma o valor?".
3. **Gráfico** por sinal (e tensão com duas séries), seletor de período, toque num ponto.
4. **Lista** (alternativa em tabela) e **detalhe** de uma medição.
5. **Estados:** vazio, erro ao guardar, sem ligação.
6. **Telemóvel da pessoa** (fase 2): registar em ecrã simples e grande.

Decisões a resolver no desenho:
- Como distinguir as duas linhas da tensão sem depender da cor.
- Se a linha de objetivo entra, ou não (recomenda-se que não).

## Ordem de trabalho

1. **Decidir** (go / no-go) com base nas regras do início e nos desenhos.
2. **Desenho** e aprovação.
3. Migração, módulo `sinais`, validação de plausibilidade e testes (em paralelo ao desenho, depois da decisão).
4. App: registo, lista e gráfico, com os testes de "sem classificação".
5. Entrada na exportação e no resumo para o médico.
6. Fase 2: lembretes de medição e registo pela própria pessoa.
7. Atualizar [[dpia-rascunho]] (dados de saúde de categoria especial, em volume) e [[design]].

## Mais tarde (fora desta primeira versão)

- **Dispositivos:** ler peso e tensão do Health Connect (Android) ou do HealthKit (iPhone). Evita digitar, mas exige permissões sensíveis e testes por marca. Só depois de a versão manual estar validada.
- **Exportar** para folha de cálculo.
- **Mais sinais** definidos pela pessoa.

## Riscos

- **Parecer um dispositivo médico.** Se a app classificar, alertar ou comentar valores, pode ser tratada como dispositivo médico, com requisitos legais bem mais pesados. A regra "só regista e mostra" não é só uma preferência: é o que mantém a app fora desse âmbito. Confirmar com apoio jurídico antes de lançar.
- **Falsa segurança:** a pessoa pode achar que, se a app "não avisou", está tudo bem. O texto de ajuda tem de dizer claramente que **a app não avalia valores**.
- **Dados muito sensíveis:** cifrados, sem aparecer em logs, notificações nem no ecrã bloqueado.

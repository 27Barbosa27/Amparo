# Consultas e análises

Estado: por implementar. Relacionado com [[plano]], [[design]], [[varios-cuidadores]] (quem pode ver e editar) e [[fotos-de-receitas]] (anexos).

> **Para quem vai implementar: desenhar primeiro.** Antes de escrever uma linha de Flutter, desenhar os ecrãs desta funcionalidade no artefacto do Claude Design (https://claude.ai/artifact/M1NgwcwbWDTxp2fK6r7s9R, ver [[design]]). Só depois de o desenho estar aprovado se passa ao código. A lista do que desenhar está em "Desenho (fazer primeiro)" mais abaixo. No fim, atualizar a contagem de ecrãs em [[design]].

## Regra de produto

A app **regista e lembra** o que a pessoa ou o médico marcaram. Nunca sugere uma consulta, nunca diz que uma análise "está atrasada", nunca interpreta um resultado. Isto é a regra "a app não substitui o médico" e vale para todos os textos desta funcionalidade ("Marcada para quinta às 10:30", e não "Deve fazer análises").

## Problema

Quem cuida de alguém gere duas agendas: a das tomas (que a app já trata) e a das consultas, análises e exames. Hoje a segunda vive em papéis, no calendário de cada familiar e na memória. O resultado são marcações esquecidas, jejum esquecido e a pergunta de véspera "a que horas era a consulta do pai?".

Para a app, o ganho está em juntar as duas agendas num só sítio, partilhado pelos cuidadores, com lembrete e com o material (o pedido, os resultados) à mão.

## O que se quer

1. Registar uma **consulta, análise, exame ou outro compromisso**, com data, hora, local e notas.
2. Receber **lembretes** (por omissão, na véspera e umas horas antes).
3. Escrever e ver a **preparação** em texto livre ("jejum de 8 horas", "levar a lista de medicamentos"), tal como a clínica a disse.
4. **Anexar** a foto do pedido e, depois, a do resultado (ver [[fotos-de-receitas]]), sem leitura nem interpretação.
5. Ver tudo num ecrã de **próximas e passadas**, e a próxima marcação em "Hoje".
6. Depois da consulta, um atalho **neutro** para rever as receitas.

Fora de âmbito (por agora): marcações repetidas por regra, ligação a calendários externos, marcar consultas dentro da app, ler resultados.

## Decisões

| Decisão | Escolha | Porquê |
|---|---|---|
| Onde vive | Cartão "Próxima consulta" em **Hoje** e um ecrã "Consultas e análises" aberto a partir dele. **Sem quarto separador** nem nas Configurações | A barra tem hoje Hoje, Receitas e Configurações; uma agenda de uso ocasional não justifica um separador. Confirmar no desenho |
| Quem escreve | Dono e cuidadores; o leitor só vê | Igual às receitas ([[varios-cuidadores]]) |
| O que se cifra | Título, local e notas (a especialidade já revela a doença) | Mesmo critério da dose da receita |
| O que fica à vista na base | Data e hora, tipo e estado | O servidor precisa delas para enviar lembretes |
| Repetição | Não há regras. Depois de "feita", a app oferece "Marcar a próxima" com a data em branco | Quem decide quando é a próxima é o médico, e uma regra de repetição seria a app a decidir |
| Passado | "Marcado" cuja hora já passou aparece como "Já passou. Foi feita?" com Sim, Não e Reagendar | Neutro, sem juízo |
| Lembretes | Por omissão 24 h e 2 h antes; o dono escolhe entre 1 semana, 1 dia, 2 horas, 1 hora | Mesmos mecanismos dos alertas que já existem |

## Modelo de dados

Migração nova (a seguinte à última existente; confirmar o número):

```sql
create type tipo_compromisso as enum ('consulta', 'analise', 'exame', 'outro');
create type estado_compromisso as enum ('marcado', 'feito', 'cancelado');

create table compromissos (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles (id) on delete cascade,
  tipo tipo_compromisso not null,
  titulo_cifrado bytea not null,
  local_cifrado bytea,
  notas_cifradas bytea,
  inicio_utc timestamptz not null,
  timezone text not null,
  estado estado_compromisso not null default 'marcado',
  lembretes_min int[] not null default '{1440,120}'
    check (cardinality(lembretes_min) <= 4),
  criado_por_user_id uuid references users (id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index compromissos_perfil_inicio_idx on compromissos (profile_id, inicio_utc);
create index compromissos_proximos_idx on compromissos (inicio_utc) where estado = 'marcado';

alter table alert_prefs add column compromissos boolean not null default true;
```

Notas:

- Seguir o padrão das tabelas existentes (nome real da tabela de perfis, índices, `updated_at`).
- A data e a hora guardam-se em UTC com o fuso do perfil, como as tomas. A hora de 10:30 mantém-se 10:30 no relógio local, também depois de uma mudança de hora.
- Os anexos usam a tabela `imagens` de [[fotos-de-receitas]], que ganha uma coluna `compromisso_id` (exatamente um de `receita_id` ou `compromisso_id` preenchido).

## Backend

### Rotas (`backend/src/compromissos/`, novo módulo, no estilo de `medicacao/`)

| Pedido | Quem | Corpo / filtros | Resposta |
|---|---|---|---|
| `GET /profiles/:id/compromissos` | qualquer membro | `?de=&ate=&estado=` | lista por data |
| `POST /profiles/:id/compromissos` | dono, cuidador | tipo, título, local?, notas?, `inicioUtc`, `lembretesMin?` | `201` com o compromisso |
| `PATCH /profiles/:id/compromissos/:cid` | dono, cuidador | qualquer campo, e `estado` | `200` |
| `DELETE /profiles/:id/compromissos/:cid` | dono, cuidador | | `204` |

- Validar com `zod`: título 1 a 120 caracteres, local até 200, notas até 2000, `inicioUtc` válido (aceitar o passado, para registar o que já aconteceu), `lembretesMin` valores permitidos.
- Cifrar com a chave do perfil, tal como a dose (`servico.ts` da medicação).
- Auditoria: `compromisso.criar`, `compromisso.alterar`, `compromisso.apagar`. O texto nunca vai para o log.
- Incluir os compromissos na exportação dos dados (`perfis/exportacao.ts`) e confirmar que o `on delete cascade` os apaga com o perfil.

### Lembretes (`jobs/trabalhos.ts`)

O trabalho `minuto` já corre `alertarReceitasAAcabar` por dia; acrescentar `alertarCompromissos`:

1. Consultar os compromissos `marcado` cujo `inicio_utc − lembrete` cai na janela do último minuto.
2. Para cada membro com `alert_prefs.compromissos` ativo, enviar o push com `alertarUtilizadores` (novo `subtipo: 'compromisso'`).
3. Deduplicar com `marcarAlertaEnviado(db, userId, 'compromisso', `${id}:${minutos}`)`, como os outros alertas, para um reinício do servidor nunca repetir.
4. Não enviar lembretes de compromissos `feito` ou `cancelado`, nem de leitores que não escolheram receber.

O texto do push **não leva o título** (o ecrã bloqueado é público): "Tem uma marcação amanhã às 10:30. Abra a Amparo para ver." O título só se vê dentro da app.

### Testes

- Criar, listar por intervalo, alterar, cancelar e apagar; um leitor a escrever dá 403; um utilizador sem acesso ao perfil dá 404.
- O título, o local e as notas estão cifrados na base (ler a coluna e confirmar que não é texto).
- Lembrete: enviado uma só vez por compromisso e por antecedência, mesmo se o job correr duas vezes na mesma janela; não enviado se `cancelado`; respeita `alert_prefs`.
- Mudança de hora (março e outubro): um compromisso às 10:30 locais continua às 10:30.
- A exportação inclui os compromissos.

## App

### Modelo e estado

- `Compromisso`, `TipoCompromisso`, `EstadoCompromisso` em `dominio/modelos.dart`.
- `Repositorio`: `compromissos(perfilId, de, ate)`, `criarCompromisso`, `alterarCompromisso`, `apagarCompromisso`. Implementar em `RepositorioApi` e na versão falsa de `test/apoio/repositorio_memoria.dart`.
- `AgendaControlador` em `estado/`, no estilo de `ReceitasControlador` (carregar, erro, listas "próximas" e "passadas").

### Ecrãs

Ver "Desenho". A implementação reutiliza `CabecalhoFormulario`, `CampoTexto`, `GrelhaOpcoes`, `EcraResultado` (sucesso unificado) e os componentes de `ui/componentes/`.

- **Cartão em Hoje:** "Próxima consulta: amanhã, 10:30 · Cardiologia". Toca para abrir a lista. Quando não há nada marcado, **não aparece** (sem convites vazios).
- **Lista "Consultas e análises":** duas secções, "Próximas" e "Passadas"; botão "Adicionar".
- **Formulário:** tipo (grelha de 4), título, data, hora, local, preparação, lembretes. A mesma estrutura do formulário de receita.
- **Detalhe:** título, quando, local, preparação, anexos, ações (feita, reagendar, cancelar, apagar).
- **Depois de "feita":** cartão neutro "Houve alterações aos medicamentos?" com "Ver receitas" e "Não". A app não sugere o que alterar.
- **Telemóvel da pessoa (modo simples):** uma linha discreta em Hoje, "Amanhã tem uma marcação às 10:30", sem botões de edição.

### Testes

- Formulário: erros por baixo dos campos, igual aos outros; criar mostra o sucesso unificado.
- A lista separa próximas e passadas e mostra "Já passou. Foi feita?" nas marcadas que passaram.
- O cartão de Hoje aparece só quando há uma marcação nos próximos 7 dias.
- Um leitor não vê os botões de escrita.

## Desenho (fazer primeiro)

No artefacto do Claude Design, desenhar, por esta ordem, nos temas **claro e escuro**, com as convenções de [[design]] (tokens, alvos de toque de 44 a 56 px, texto base de 15 px, cantos e sombras iguais aos dos ecrãs atuais):

1. Cartão "Próxima consulta" em **Hoje** (com e sem marcação).
2. **Lista** "Consultas e análises": próximas, passadas, vazio.
3. **Formulário** de nova marcação, com erro por baixo de um campo.
4. **Detalhe**, com e sem anexos, e o estado "Já passou. Foi feita?".
5. **Sucesso** ("Marcação criada") com o ecrã de resultado unificado.
6. **Depois de feita**: "Houve alterações aos medicamentos?".
7. **Linha em Hoje no modo simples** da pessoa, com texto grande.
8. **Estados**: sem ligação, erro ao guardar, a carregar (reutilizar os existentes).

Decisões que o desenho tem de resolver:

- O cartão em Hoje e o ecrã a partir dele chegam, ou faz falta mesmo um quarto separador? (Proposta: não.)
- Como se mostra o aviso de preparação ("jejum") no cartão sem o tornar um conselho da app: sempre atribuído ao texto da pessoa, por exemplo "Preparação (nota sua): jejum de 8 horas".

Só depois de o desenho estar aprovado começar a implementação.

## Ordem de trabalho

1. **Desenho** no artefacto e aprovação.
2. Migração, rotas e testes do backend (sem lembretes).
3. Lembretes (`alertarCompromissos`) e testes.
4. Repositório, controlador e ecrãs da app, com testes.
5. Anexos, quando [[fotos-de-receitas]] estiver feito.
6. Atualizar [[dpia-rascunho]] (a especialidade da consulta revela dados de saúde) e a lista de funcionalidades em [[design]].

## Riscos

- **Lembretes com título no ecrã bloqueado:** por isso o push não leva o título.
- **Fuso horário:** testar a mudança de hora; um compromisso criado noutro fuso (viagem) usa o do perfil, e isso tem de ser claro no formulário ("hora de Lisboa").
- **A tentação de "ajudar":** sugerir consultas de rotina, avisar de "análises em atraso" ou ler resultados faz a app parecer um substituto do médico. Fica fora do âmbito de propósito.

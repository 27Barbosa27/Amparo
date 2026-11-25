# Sintomas e efeitos que reparei

Estado: por implementar. Relacionado com [[plano]], [[design]], [[varios-cuidadores]], [[diario-do-cuidador]] (usa a mesma tabela de notas), [[diario-de-sinais]] e [[fotos-de-receitas]].

> **Para quem vai implementar: desenhar primeiro.** Antes de escrever código na app, desenhar os ecrãs no artefacto do Claude Design (https://claude.ai/artifact/M1NgwcwbWDTxp2fK6r7s9R, ver [[design]]) e só depois implementar. A lista do que desenhar está em "Desenho (fazer primeiro)". O servidor pode avançar em paralelo. No fim, atualizar a contagem de ecrãs em [[design]].

## Para que serve

Em cima da hora da consulta, quase ninguém se lembra do que sentiu nas últimas semanas. "Tinha tonturas depois do comprimido da manhã, mas não sei quando começou." Esta funcionalidade deixa **anotar em dois toques o que se repara**, ligado ao medicamento e à hora, e reencontrar tudo quando faz falta.

**A app só guarda o que a pessoa escreve.** Nunca interpreta, nunca diz se é grave, nunca relaciona um sintoma com um medicamento ("isto pode ser efeito de…"), nunca sugere ligar ao médico por causa do conteúdo. Isto é a regra "a app não substitui o médico".

## O que se quer

1. **Anotar depressa** um sintoma ou efeito, ligado (se a pessoa quiser) a uma receita e a uma hora.
2. **Ver a lista** por ordem do tempo e filtrar por medicamento.
3. **Levar à consulta** (a lista aparece no resumo para o médico, tal como foi escrita).
4. **Avisar o cuidador**, sem texto, de que há uma nota nova.

Fora de âmbito: categorias automáticas, gravidade calculada, alertas por palavras-chave, sugestões. "Como me sinto hoje" **diário e recorrente** ficou de fora de propósito: pedir isto todos os dias cansa. O humor, se a pessoa quiser registá-lo, é só uma etiqueta opcional de uma nota (ver mais abaixo).

## Decisões

| Decisão | Escolha | Porquê |
|---|---|---|
| Como se começa | Nunca por lembrete diário. Só quando a pessoa **toca em "Notei algo"** | Evita o cansaço de um pedido repetido |
| Texto | Livre, até 500 caracteres, cifrado | A pessoa diz o que quer, com as palavras dela |
| Intensidade | Opcional: **Leve / Média / Forte**, escolhida pela pessoa | É a perceção dela; a app **não** a usa para alertas, cores de perigo nem ordenação |
| Hora | Por omissão "agora"; editável ("há 1 hora", "esta manhã", hora exata) | Muitas vezes só se anota mais tarde |
| Ligação | Opcional a uma **receita** (e portanto a um medicamento) | Para filtrar "o que notei com o Ramipril" |
| Quem escreve | A **pessoa** no seu telemóvel, o **cuidador** em nome dela, o dono | Não depende de a pessoa saber usar tudo |
| Quem lê | Dono e cuidadores, e o leitor ([[varios-cuidadores]]); o telemóvel da pessoa só vê as dela | As do diário do cuidador são outro tipo, ver [[diario-do-cuidador]] |
| Texto de segurança | Uma linha fixa no ecrã: "Se for urgente, ligue 112." | Não é conselho clínico, é sinalização de emergência; **validar a redação no desenho** |

## Modelo de dados

A tabela `notas` serve esta funcionalidade e o [[diario-do-cuidador]]. Migração nova (confirmar o número seguinte):

```sql
create type tipo_nota as enum ('sintoma', 'cuidador');

create table notas (
  id uuid primary key,                    -- gerado na app: torna o reenvio idempotente
  profile_id uuid not null references profiles (id) on delete cascade,
  tipo tipo_nota not null,
  texto_cifrado bytea not null,
  intensidade smallint check (intensidade between 1 and 3),   -- só sintomas
  etiquetas text[] not null default '{}',                      -- ver diário do cuidador
  receita_id uuid references receitas (id) on delete set null,
  ocorreu_em timestamptz not null,
  autor_user_id uuid references users (id) on delete set null,
  autor_dispositivo_id uuid references profile_devices (id) on delete set null,
  fixada boolean not null default false,
  criado_em timestamptz not null default now(),
  editado_em timestamptz,
  check (num_nonnulls(autor_user_id, autor_dispositivo_id) <= 1)
);
create index notas_perfil_tempo_idx on notas (profile_id, ocorreu_em desc);
create index notas_receita_idx on notas (receita_id) where receita_id is not null;

alter table alert_prefs add column notas_sintoma boolean not null default true;
```

Notas:

- **Sem ligação a uma toma concreta**: o servidor só guarda 90 dias de tomas, por isso uma chave para a toma deixaria de funcionar. A ligação é à receita, mais a hora (`ocorreu_em`).
- O `id` é gerado na app (UUID). Quando se escrever uma nota sem rede ([[fila-offline]]), o reenvio nunca cria duas.
- `etiquetas` é só para o [[diario-do-cuidador]]; nos sintomas fica vazia.
- `on delete set null` no autor: se uma conta for apagada, as notas ficam, sem nome.

## Backend

### Rotas (`backend/src/notas/`, novo módulo)

| Pedido | Quem | Corpo / filtros | Resposta |
|---|---|---|---|
| `GET /profiles/:id/notas` | membros e a própria pessoa | `?tipo=sintoma&receitaId=&de=&ate=` | lista por data, a mais recente primeiro |
| `POST /profiles/:id/notas` | dono, cuidador, a pessoa | `id`, `tipo`, `texto`, `intensidade?`, `receitaId?`, `ocorreuEm` | `201` |
| `PATCH /profiles/:id/notas/:nid` | autor, ou dono | `texto?`, `intensidade?`, `receitaId?`, `ocorreuEm?` | `200` |
| `DELETE /profiles/:id/notas/:nid` | autor, ou dono | | `204` |

**Visibilidade por quem pede** (aplicar na consulta, não só na app):

| Quem pede | Vê | Escreve |
|---|---|---|
| Dono, cuidador | `sintoma` e `cuidador` | ambos |
| Leitor | só `sintoma` | nada |
| Telemóvel da pessoa | só os `sintoma` (todos) | só `sintoma` |

- Validar com `zod`: `texto` 1 a 500 caracteres; `intensidade` 1 a 3; `ocorreuEm` não pode estar mais de 5 minutos no futuro; `receitaId` tem de ser do mesmo perfil.
- O `POST` com o mesmo `id` devolve a nota existente (idempotente).
- Cifrar o texto com a chave do perfil, como a dose.
- Auditoria sem conteúdo: `nota.criar`, `nota.editar`, `nota.apagar`.
- Exportação do perfil (`perfis/exportacao.ts`) inclui as notas; o cascade apaga-as com o perfil.

### Aviso ao cuidador

Quando a **pessoa** (ou um cuidador) cria uma nota de sintoma, os cuidadores com `notas_sintoma` ativo recebem um push **sem conteúdo**: "A Maria acrescentou uma nota." Quem a escreveu não é avisado. O texto da nota nunca vai para o push nem para o log.

### Testes

- Criar com os três perfis de acesso e ver quem pode ler e escrever (a tabela de visibilidade, uma verificação por linha).
- O texto está cifrado na base.
- Idempotência: o mesmo `id` duas vezes dá uma só nota.
- `receitaId` de outro perfil dá 400; um utilizador sem acesso ao perfil dá 404.
- O push não leva texto e não chega ao autor.

## App

### Modelo e estado

- `Nota`, `TipoNota`, `Intensidade` em `dominio/modelos.dart`.
- `Repositorio`: `notas(perfilId, {tipo, receitaId, de, ate})`, `criarNota`, `alterarNota`, `apagarNota`; versão real e falsa.
- `NotasControlador` em `estado/`, no estilo dos outros.
- Quando existir a [[fila-offline]], escrever uma nota sem rede entra na fila (com o `id` gerado na app).

### Onde aparece (fora das Definições)

- **"Notei algo"** no cartão de cada toma e no ecrã de sucesso ("Toma marcada"): leva ao formulário já com o medicamento escolhido e a hora de agora.
- **Linha em Hoje**: um atalho discreto "Notei algo" **sempre disponível, nunca a pedir**.
- **Lista "O que notei"**: na receita (as notas desse medicamento) e no histórico de tomas (a linha do tempo, junto às tomas).
- **Telemóvel da pessoa:** botão grande "Notei algo", que abre o ditado por voz, se existir ([[widget-e-modo-simples]]), ou um campo de texto.

### O formulário

Três passos, todos opcionais menos o texto:

1. **O que reparou?** Campo de texto grande (e o microfone para ditar, se existir).
2. **Quão forte?** Leve, Média, Forte (opcional, sem cores de alerta: usar a cor neutra do tema).
3. **Quando e com que medicamento?** "Agora" por omissão; escolher outro momento ou uma receita.

O botão "Guardar" fica ativo logo que haja texto. No fim, o ecrã de sucesso unificado (`EcraResultado`).

**Humor (opcional):** em vez de uma pergunta diária, uma linha de carinhas pequena **dentro do formulário**, que só se usa se a pessoa quiser. Guarda-se como etiqueta da nota (`humor:bem` etc.), nunca como pedido recorrente.

### Texto de segurança

"Se for urgente, ligue 112." fixo no rodapé do formulário e da lista. A redação final fecha-se no desenho e é a **única frase que se aproxima de aconselhar**; mantém-se sem ligação ao conteúdo da nota.

### Testes

- Criar com e sem intensidade; guardar fica desativado sem texto.
- Aparece na lista do medicamento certo e na linha do tempo.
- Na versão do leitor não há "Notei algo".
- Nenhum texto desta funcionalidade contém "grave", "perigoso", "deve", "recomendamos" (teste que procura as palavras).

## Desenho (fazer primeiro)

No artefacto do Claude Design, nos temas **claro e escuro**:

1. **"Notei algo"** no cartão da toma e no ecrã de sucesso.
2. **Formulário** (texto, intensidade, quando e medicamento, humor opcional, rodapé do 112), e o estado de erro.
3. **Lista** por medicamento e **linha do tempo** com as tomas.
4. **Detalhe** de uma nota (editar, apagar).
5. **Telemóvel da pessoa:** botão grande e ditado por voz.
6. **Sucesso** ("Nota guardada").
7. **Vazio:** primeira vez, sem notas, sem texto a pedir que escreva.

Decisões a resolver no desenho:
- Como representar a intensidade **sem** cores de perigo (vermelho, laranja): só o tom do tema e o texto.
- Onde está o atalho "Notei algo" em Hoje sem competir com as tomas.
- A redação exata da linha do 112.

## Ordem de trabalho

1. **Desenho** e aprovação.
2. Migração, módulo `notas`, visibilidade e testes (em paralelo ao desenho).
3. Push sem conteúdo.
4. App: modelo, formulário, lista e ligação ao cartão da toma, com testes.
5. Ditado por voz, quando existir ([[widget-e-modo-simples]]).
6. Incluir as notas no resumo para o médico, quando existir.
7. Atualizar [[dpia-rascunho]] (texto livre de saúde) e [[design]].

## Riscos

- **Texto livre com dados de saúde:** por isso cifrado, fora do log e fora do push.
- **A tentação de ajudar:** palavras-chave, "isto é um efeito conhecido", gravidade. Tudo isso seria a app a interpretar. Fica fora, de propósito.
- **Uma nota "grave" que ninguém lê:** a app não pode garantir que alguém atua. O aviso ao cuidador existe, mas o texto de 112 e a responsabilidade clínica continuam fora da app.

# Motivação sem culpa

Estado: por implementar. Relacionado com [[plano]], [[design]], [[varios-cuidadores]], [[plano-pago]] e [[widget-e-modo-simples]].

> **Para quem vai implementar: desenhar primeiro.** Antes de escrever código na app, desenhar os ecrãs no artefacto do Claude Design (https://claude.ai/artifact/M1NgwcwbWDTxp2fK6r7s9R, ver [[design]]) e só depois implementar. A lista do que desenhar está em "Desenho (fazer primeiro)". O servidor pode avançar em paralelo, porque não depende do desenho. No fim, atualizar a contagem de ecrãs em [[design]].

## Para que serve

Ajudar a pessoa e quem cuida dela a **manter o hábito** de tomar e registar, e dar à família uma forma de se fazer presente sem ligar todos os dias. Quatro peças:

1. **Resumo semanal em positivo.**
2. **Sequência sem castigo.**
3. **Mensagens da família.**
4. **Marcos discretos.**

## Princípios (valem para tudo neste documento)

1. **Nunca criar culpa.** Uma pessoa idosa que vê "perdeu a sua sequência" pode desistir da app, ou do medicamento. Nenhum texto diz "falhou", "perdeu", "devia" ou "atrasado" a quem toma.
2. **Só factos, nunca juízos.** "Esta semana: 19 de 21 tomas." Não "Muito bem!" nem "Podia ser melhor". O incentivo vem de mensagens humanas (as da família), não da app a avaliar.
3. **Tudo é opcional e desligável**, por pessoa, e a pessoa acompanhada não vê nada que o cuidador não tenha ligado para ela.
4. **Sem comparações** com outras pessoas, sem rankings, sem "o seu vizinho tomou mais".
5. **Não interpreta.** A adesão é uma contagem do que aconteceu. A app não diz se é "boa" ou "má" nem o que fazer. Isto é a regra "a app não substitui o médico".
6. **Respeita "reduzir movimento"** do sistema (as animações já o fazem em `AnimacaoLottie`).
7. **Gratuito.** Ajuda a manter a rotina, que é segurança: ver [[plano-pago]].

## O que já existe e se reutiliza

| Peça | Onde | Para quê |
|---|---|---|
| Adesão diária | `DiaAdesao` / `ResultadoDia` (`tudoTomado`, `esquecida`, `emCurso`, `semDados`) e `percentagemAdesao` em `modelos.dart` | Define o que conta como "dia completo". Não se reinventa |
| Trabalho diário | `trabalhosDiarios` em `jobs/trabalhos.ts` | Onde se atualiza a sequência e se envia o resumo |
| Alertas sem repetição | `marcarAlertaEnviado(db, userId, tipo, chave)` | Garante um só resumo por semana mesmo que o job corra duas vezes |
| Preferências | `alert_prefs` (por cuidador e perfil) | Onde se ligam e desligam |
| Ecrã de sucesso | `SucessoMarcadaEcra` (`sucesso_marcada.dart`) com animação Lottie | Onde aparece a mensagem da família |
| Papéis | [[varios-cuidadores]] | Quem pode escrever mensagens |

**Limite técnico a ter em conta:** o servidor só guarda **90 dias de tomas** (`manterJanela`). Uma sequência de 200 dias não se pode calcular a partir das tomas; por isso guarda-se o contador à parte (ver 2).

---

## 1. Resumo semanal em positivo

### O que é

Ao domingo à noite, um cartão e (opcionalmente) um push: "Esta semana a Maria tomou 19 das 21 tomas." Só números e, quando for verdade e favorável, uma comparação suave: "Mais 2 do que na semana passada."

### Regras do texto

| Situação | Texto |
|---|---|
| Melhorou | "Esta semana: 19 de 21 tomas. Mais 2 do que na semana passada." |
| Igual | "Esta semana: 19 de 21 tomas. O mesmo que na semana passada." |
| Piorou | "Esta semana: 17 de 21 tomas." (**sem** comparação) |
| Tudo tomado | "Esta semana: 21 de 21 tomas." |
| Semana com pausa ([[plano]]) | Só conta os dias sem pausa; se não houver dias, não há resumo |
| Menos de 7 dias de uso | Não há resumo |
| Sem tomas | Não há resumo |

Nunca "falhou", nunca "esqueceu". A palavra do resumo é **"tomou"**. As tomas **saltadas** de propósito contam como registadas e não como esquecidas (quem as salta decidiu algo; penalizá-lo ensina a mentir à app).

### Quem recebe

- Os **cuidadores** que ativarem "Resumo da semana" (por omissão, ligado só para o dono).
- A **própria pessoa** só se o cuidador ligar "Mostrar à pessoa". Para algumas pessoas ver números é motivador, para outras é ansiedade, e quem decide é quem as conhece.
- Os **leitores** recebem se escolherem, e por omissão não.

### Como se calcula

- Semana de **segunda a domingo**, no fuso do perfil. O trabalho diário verifica se hoje é domingo às 19:00 locais (ou o primeiro ciclo depois), e depois processa cada perfil.
- A contagem usa a mesma regra de `percentagemAdesao`: dias terminados, com tomas, "tudo tomado" ou "esquecida". Para o resumo, em vez de percentagem, mostra-se `tomadas / total de tomas` da semana; extrair uma função partilhada no servidor com a mesma lógica da app, para os números nunca discordarem.
- Chave de repetição: `resumo_semana:2026-W48` em `alertas_enviados`, por utilizador.

### Dados

Sem tabela nova: a semana calcula-se das tomas (dentro da janela de 90 dias). Acrescenta-se a `alert_prefs`:

```sql
alter table alert_prefs
  add column resumo_semanal boolean not null default false,
  add column resumo_semanal_pessoa boolean not null default false;
```

(`resumo_semanal_pessoa` só vale na linha do dono e controla o que a pessoa vê.)

### Rotas e app

- `GET /profiles/:id/resumo-semanal?semana=2026-W48` devolve os números e o texto-base (a app compõe a frase, para ficar em pt-PT e traduzível).
- Cartão "Semana de 17 a 23 de novembro" em Hoje, ao domingo e na segunda-feira, que se fecha com um toque.
- Push (se ligado), sem números no texto bloqueado: "O resumo da semana da Maria está pronto."

---

## 2. Sequência sem castigo

### O que é

"7 dias seguidos a tomar". Não é um jogo com vidas. **Nunca zera visivelmente**: quando um dia falha, a app mostra "Recomeçou hoje" e guarda a melhor sequência ("A sua melhor: 23 dias").

### O que conta

Por dia (no fuso do perfil), com as regras do resultado diário já existentes:

| Resultado do dia | Efeito na sequência |
|---|---|
| `tudoTomado` | Soma 1 |
| `esquecida` (alguma toma falhada) | Quebra: a atual passa a 0 e o texto mostra "Recomeçou hoje" |
| Dia só de tomas saltadas de propósito | Neutro: não soma nem quebra |
| Dia em pausa ([[plano]]) | Neutro |
| `semDados` / `emCurso` | Ignorar (só se conta um dia terminado) |

### Dados

Como só há 90 dias de tomas, a sequência guarda-se:

```sql
create table sequencias (
  profile_id uuid primary key references profiles (id) on delete cascade,
  atual int not null default 0,
  melhor int not null default 0,
  ultimo_dia date,                 -- o último dia já contado
  atualizada_em timestamptz not null default now()
);
alter table alert_prefs add column mostrar_sequencia boolean not null default false;
```

- O trabalho diário (`trabalhosDiarios`) avalia o dia que terminou, atualiza `atual` e `melhor` e grava `ultimo_dia`. É **idempotente**: se correr duas vezes para o mesmo dia, não soma duas vezes (comparar com `ultimo_dia`).
- **Dias em falta** (servidor desligado): ao correr, processar todos os dias desde `ultimo_dia + 1` até ontem, por ordem.
- Correções: se uma toma for corrigida (marcada depois, desfeita), reavaliar **só os últimos 3 dias** e recalcular a partir daí; se for mais antigo, não se mexe.

### Onde e quando se mostra

- **Desligada por omissão** (`mostrar_sequencia`). O cuidador liga-a por pessoa.
- Num cartão pequeno em Hoje e no ecrã de sucesso de uma toma: "Dia 12".
- Quando quebra: "Recomeçou hoje. A sua melhor: 23 dias." Nunca "0 dias" nem um ícone de chama apagada.
- A pessoa idosa só a vê se o cuidador a ligou para ela.

### Testes

- Dias consecutivos somam; um dia `esquecida` quebra e mantém `melhor`; dia de pausa e dia de saltadas não alteram.
- Correr o trabalho duas vezes não soma duas vezes; um intervalo de 3 dias sem job recupera-os por ordem.
- Mudança de hora e fuso horário diferente do servidor.

---

## 3. Mensagens da família

### O que é

Um cuidador escreve uma mensagem curta ("Bom trabalho, avó!") que a pessoa vê **quando marca uma toma**, no ecrã de sucesso. É uma forma de presença sem chamada, e a única peça de motivação que vem de uma pessoa e não da app.

### Regras

- Texto até **140 caracteres**, sem imagens.
- Só **dono e cuidadores** escrevem; os leitores não.
- **Uma por dia** é mostrada, a mais antiga por ver; se houver várias, esperam pelo dia seguinte. Evita que um ecrã de sucesso vire uma conversa.
- **Sem resposta** em texto; a pessoa pode tocar num coração para dizer que viu ("A Ana vê que gostou"). Fase 2.
- O cuidador escolhe entre **frases prontas** ("Bom trabalho!", "Estou orgulhoso de si.", "Um beijinho.") ou escreve a sua. Reduz o esforço.
- Limite de **5 por dia** por cuidador.
- A pessoa pode **fechar** a mensagem; não há obrigação de ler.
- Uma mensagem **expira** 14 dias depois de criada, se nunca chegou a ser mostrada.

### Dados

```sql
create table mensagens (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles (id) on delete cascade,
  de_user_id uuid references users (id) on delete set null,
  texto_cifrado bytea not null,
  criada_em timestamptz not null default now(),
  mostrada_em timestamptz,
  coracao_em timestamptz
);
create index mensagens_pendentes_idx on mensagens (profile_id, criada_em) where mostrada_em is null;
```

### Rotas

| Pedido | Quem | Resposta |
|---|---|---|
| `POST /profiles/:id/mensagens` | dono, cuidador | `201` |
| `GET /profiles/:id/mensagens/proxima` | pessoa (dispositivo) ou cuidador a ver como a pessoa | a próxima por mostrar, ou `204` |
| `POST /profiles/:id/mensagens/:mid/vista` | pessoa | `204`; marca `mostrada_em` |

- Cifrar o texto com a chave do perfil, como a dose.
- Auditoria sem conteúdo: `mensagem.criar`.
- O push só se usa para avisar o cuidador de que a pessoa viu, e **não** leva o texto.

### App

- No ecrã de sucesso de uma toma marcada, por baixo da animação: o texto da mensagem num cartão suave, com "Fechar".
- Para o cuidador: "Escrever uma mensagem para a Maria" no cartão da pessoa, com as frases prontas.
- Respeitar o tamanho de letra do perfil.

---

## 4. Marcos discretos

### O que é

Poucos, espaçados, sem comparação: ao fim de **7, 30, 100 e 365** dias com as tomas registadas, aparece uma animação (a mesma família dos Lottie de sucesso) e uma frase: "30 dias a manter a rotina."

### Regras

- Cada marco acontece **uma só vez** por pessoa.
- Baseado nos **dias com tomas registadas** (a mesma contagem da sequência, mas **não se perde** quando a sequência quebra: é um total acumulado). Assim, nunca se "perde" um marco já ganho.
- Mostra-se à pessoa só se o cuidador ligou "Mostrar à pessoa", e aos cuidadores como uma linha em Hoje ("A Maria chegou aos 30 dias.").
- Sem partilha em redes, sem "medalhas", sem ranking.
- Uma animação nova: **fica para o desenho** decidir se se reutiliza a de sucesso ou se se cria uma, e confirmar a licença dela (o README já avisa que os Lottie atuais precisam de confirmação).

### Dados

```sql
create table marcos (
  profile_id uuid not null references profiles (id) on delete cascade,
  dias int not null check (dias in (7, 30, 100, 365)),
  alcancado_em timestamptz not null default now(),
  mostrado_em timestamptz,
  primary key (profile_id, dias)
);
alter table sequencias add column dias_registados int not null default 0;
```

O trabalho diário soma 1 a `dias_registados` por cada dia contado, e quando atinge 7, 30, 100 ou 365 insere o marco.

---

## Desenho (fazer primeiro)

No artefacto do Claude Design, nos temas **claro e escuro**, com as convenções de [[design]]:

1. **Cartão do resumo semanal** em Hoje (melhorou, igual, piorou, tudo tomado, sem resumo).
2. **Cartão da sequência** ("Dia 12") e o estado "Recomeçou hoje, a sua melhor: 23 dias".
3. **Ecrã de sucesso de uma toma** com a **mensagem da família** por baixo.
4. **Escrever uma mensagem**: frases prontas, campo livre, contador de caracteres.
5. **Marco** (7, 30, 100, 365) com a animação e a frase.
6. **Ligar e desligar** (por pessoa, no ecrã do cuidador): resumo semanal, sequência, marcos, "Mostrar à pessoa". Não nas Definições gerais, mas no ecrã da pessoa.
7. Versão para a **pessoa idosa**: texto grande, nada que pareça uma pontuação.

Decisões que o desenho tem de resolver:
- Como mostrar a sequência sem a transformar num jogo.
- Se o marco reutiliza a animação de sucesso ou precisa de uma nova.
- Onde fica o interruptor "Mostrar à pessoa", para ser fácil de encontrar e de explicar.

## Ordem de trabalho

1. **Desenho** e aprovação.
2. `sequencias`, `marcos` e o trabalho diário (com testes); `resumo-semanal` e preferências.
3. Resumo semanal na app, ligado às preferências.
4. Mensagens da família (tabela, rotas, ecrã de sucesso, escrita pelo cuidador).
5. Sequência e marcos na app, desligados por omissão.
6. Atualizar [[dpia-rascunho]] (mensagens são dados pessoais) e [[design]].

## Testes principais

- Resumo: as seis situações da tabela de texto; a mesma semana nunca se envia duas vezes; semana com pausa; fuso do perfil.
- Sequência: ver acima.
- Mensagens: uma por dia; expira ao fim de 14 dias; um leitor não escreve; outra pessoa não vê as mensagens de outro perfil (IDOR); a mensagem está cifrada na base.
- Marcos: nunca repetem; mantêm-se quando a sequência quebra.
- App: nenhum destes textos contém "falhou", "perdeu" ou "devia" (um teste simples que procura as palavras nos textos desta funcionalidade).

## Riscos

- **Ansiedade:** por isso tudo é opcional e desligado por omissão para a pessoa.
- **Gamificação a mais:** a tentação de acrescentar pontos, níveis e medalhas. Deixar de fora de propósito.
- **Mensagens a mais:** um cuidador insistente pode sobrecarregar. O limite de uma por dia protege a pessoa.

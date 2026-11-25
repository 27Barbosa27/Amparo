# Widget e modo simples da pessoa

Estado: por implementar. Relacionado com [[plano]], [[design]], [[fila-offline]], [[fotos-de-receitas]] e [[varios-cuidadores]].

> **Para quem vai implementar: desenhar primeiro.** Antes de escrever código na app, desenhar os ecrãs e o widget no artefacto do Claude Design (https://claude.ai/artifact/M1NgwcwbWDTxp2fK6r7s9R, ver [[design]]). Só depois de aprovado se implementa. A lista do que desenhar está em "Desenho (fazer primeiro)". No fim, atualizar a contagem de ecrãs em [[design]].

## Duas partes

1. **Widget** no ecrã inicial do telemóvel: ver a próxima toma e marcá-la sem abrir a app.
2. **Modo simples da pessoa**, levado mais longe: uma toma de cada vez, leitura em voz alta e confirmação por voz.

São independentes e podem ser feitas por esta ordem ou em paralelo. O widget depende de [[fila-offline]] para marcar sem rede.

## Regra de produto

Tudo aqui reduz o esforço de **registar** e **lembrar**. Nada decide, sugere ou interpreta: a voz lê o que a app já mostra ("São 14 horas. Ramipril, 1 comprimido") e não dá conselhos, e o widget não diz o que fazer, só o que está marcado.

---

## Parte 1: o widget

### Porque

Cada passo para abrir a app, entrar e procurar a toma é uma oportunidade de não registar. Um widget no ecrã inicial reduz a marcação a **um toque**. É a mudança que mais deve aumentar os registos feitos a tempo.

### O que o widget mostra

| Tamanho | Conteúdo |
|---|---|
| Pequeno | A hora da próxima toma e o botão **Tomei** |
| Médio | As próximas 3 tomas, com a hora e o estado (pendente, tomada, atrasada) |

- **Privacidade por omissão:** o widget fica visível no ecrã inicial e, às vezes, no bloqueado. Por omissão mostra **só a hora** ("Próxima toma às 14:00") e **não o nome do medicamento**. Quem quiser, ativa "Mostrar o nome do medicamento" quando **configura o widget** (o ecrã de configuração que o Android abre ao adicionar um widget), e não nas Definições da app.
- **Uma pessoa por widget:** num telemóvel de cuidador com várias pessoas acompanhadas, a configuração pergunta a que pessoa se refere. No telemóvel da própria pessoa, é o perfil dela.
- **Sem toma pendente:** "Hoje já está" ou "Sem tomas hoje".
- **Sessão expirada ou sem ligação:** "Abra a Amparo" ou a última informação com "atualizado às 13:42".

### Marcar a partir do widget

- Um toque em **Tomei** marca a toma como tomada **à hora do toque**, com a chave de idempotência e o `eventoEm`, pelo mesmo caminho da fila offline ([[fila-offline]]). Sem rede, fica guardada e envia-se depois, sem perder nada.
- **Contra toques acidentais:** depois de marcar, o botão passa a mostrar "Desfazer" durante **60 segundos**, porque é a janela que o servidor já aceita para desfazer (`DESFAZER_MS`). Passado o minuto, o widget mostra a toma como tomada.
- Um **leitor** ([[varios-cuidadores]]) não tem botão no widget: só vê.
- Sem o trabalho da fila offline, o widget só pode marcar com rede; nesse caso mostra "Sem ligação" e não finge que marcou.

### Como funciona por dentro

- **Pacote:** `home_widget` (Flutter), que liga o código Dart ao widget nativo.
- **Dados partilhados:** sempre que a app atualiza as tomas de hoje, escreve um pequeno resumo (as próximas 3 tomas: id, perfil, hora, estado, e o nome só se a pessoa escolheu mostrá-lo) num armazenamento partilhado com o widget (`SharedPreferences` no Android, `App Group` no iPhone).
- **Android (primeiro):** `AppWidgetProvider` com `RemoteViews`, um ecrã de configuração, e uma ação do botão que acorda o Dart em segundo plano para enviar o registo.
- **Atualização:** o Android limita as atualizações periódicas dos widgets (mínimo de cerca de 30 minutos). Para a informação não ficar velha: atualizar sempre que a app muda as tomas, ao arrancar o telemóvel, com um `WorkManager` a cada 15 minutos, e ao registar uma toma. O widget mostra "atualizado às HH:mm" quando a informação for antiga. **O widget não é um alarme** e não deve ser usado como tal (os alarmes são outro trabalho, ver [[plano]]).
- **iPhone (depois):** um widget **WidgetKit** em SwiftUI, numa extensão separada. Exige macOS com Xcode (ou a ferramenta `xtool`, que permite compilar apps iOS sem Xcode; não foi testada neste projeto). Só vale a pena depois de o Android estar validado.
- **Token:** o widget usa a sessão guardada de forma segura; nunca guarda a palavra-passe.

### Testes

- Lógica pura (em Dart): dado um conjunto de tomas, qual é a "próxima", como se escolhem as 3 do widget e o texto "atualizado às…". Testes de unidade normais.
- O marcar a partir do widget entra na fila offline com a chave e o `eventoEm` certos.
- O widget nativo (visual e toque) testa-se à mão, num telemóvel real, em tamanhos pequeno e médio, em claro e escuro, e com o tamanho de letra do sistema no máximo.

---

## Parte 2: o modo simples, mais longe

### O que já existe

`IdosoHoje` (`ui/ecras/idoso_hoje.dart`) já é o único modo no telemóvel de uma pessoa ligada por código: a toma atrasada ou a próxima em destaque, botões grandes, o resto mais abaixo, o botão "Ligar à Ana" e o tamanho de letra do perfil (`normal`, `grande`, `muito_grande`, com `EscalarTexto`).

### O que se acrescenta

1. **Uma toma de cada vez.** Quando chega a hora, o ecrã mostra só aquela toma, com o nome e a dose muito grandes e dois botões enormes: **Já tomei** e **Agora não**. Quem tem a foto da caixa ([[fotos-de-receitas]]) vê-a grande, para a reconhecer.
2. **Confirmar antes de registar.** O toque em "Já tomei" abre uma confirmação com "Sim" e "Não" muito grandes (evita registos por engano, comuns com mãos que tremem).
3. **Ler em voz alta.** Um botão com o altifalante lê o que está no ecrã: "São 14 horas. Ramipril, 1 comprimido." Só lê o texto da app, não acrescenta nada.
4. **Confirmar por voz.** Um botão de microfone: a pessoa diz "tomei" (ou "já tomei", "sim"). **O microfone só se liga quando a pessoa toca no botão**, nunca fica a ouvir.
5. **Alto contraste.** Uma variante do tema com mais contraste, para pouca visão. Aplica-se por perfil, e escolhe-se no ecrã do cuidador ao lado do tamanho do texto.

### Como a voz funciona (e os seus limites)

- **Pacotes:** `speech_to_text` para ouvir (língua `pt_PT`) e `flutter_tts` para ler.
- **A voz nunca regista sozinha.** Depois de ouvir "tomei", a app mostra a confirmação visual do ponto 2 ("Ouvi 'tomei'. Marcar o Ramipril das 14:00 como tomado?"). Só um "Sim" (por toque ou por voz) regista. O reconhecimento de voz erra, sobretudo com ruído e sotaques.
- **O botão é sempre o caminho principal**; a voz é um apoio. Se o reconhecimento não estiver disponível no telemóvel, o botão do microfone não aparece.
- **Privacidade:** o reconhecimento pode correr no próprio telemóvel ou no serviço de voz do sistema (no Android, por omissão, num serviço da Google). Preferir o reconhecimento **no telemóvel** (`onDevice`) sempre que o sistema o ofereça. Nenhum áudio se guarda nem se envia ao servidor da Amparo. Registar isto na [[dpia-rascunho]] e na [[politica-privacidade-rascunho]], e pedir a permissão do microfone só quando a pessoa toca no botão pela primeira vez, com uma frase simples a explicar porquê.
- **Acessibilidade:** testar com TalkBack e VoiceOver, com a letra do sistema a 200%, e com botões de pelo menos 56 px (as convenções de [[design]] vão de 44 a 56).

### Dependência dos alarmes

Este modo mostra-se bem **quando a pessoa abre a app**. Para a toma aparecer sozinha no momento certo, com o telemóvel bloqueado, são precisos os alarmes locais, que são outra funcionalidade. Esta parte não os substitui: assume-os.

### Testes

- A confirmação em dois passos: tocar em "Já tomei" só regista depois do "Sim".
- A voz: um reconhecimento falso (um dublê) que devolve "tomei", "sim", "não", ou uma frase qualquer. Só "tomei" e "sim" avançam para a confirmação; nada regista sem o "Sim".
- Com a letra no máximo, nenhum texto fica cortado (o teste de widget já usado para `EscalarTexto`).
- O ecrã de uma toma de cada vez com e sem foto da caixa.

---

## Desenho (fazer primeiro)

No artefacto do Claude Design, nos temas **claro e escuro**, com as convenções de [[design]]:

**Widget (Android, e depois iPhone)**
1. Widget **pequeno** (com a hora e "Tomei"; com e sem nome; sem toma pendente; sem ligação).
2. Widget **médio** com 3 tomas e estados (pendente, tomada, atrasada).
3. O botão depois de marcar: "Desfazer" durante 60 segundos.
4. **Ecrã de configuração** do widget: escolher a pessoa e "Mostrar o nome do medicamento".

**Modo simples**
5. **Uma toma de cada vez**, com e sem foto da caixa, nos três tamanhos de letra.
6. **Confirmação** "Sim" / "Não" grande.
7. **Voz**: estado "a ouvir", "Ouvi 'tomei'. Marcar…?", erro ("Não percebi. Toque no botão.").
8. Variante de **alto contraste**.
9. Explicação da **permissão do microfone** (uma frase, uma imagem).

Resolver no desenho: como se distingue visualmente "ainda é cedo" de "é a hora" no widget, sem usar só a cor (acessibilidade para daltonismo).

Só depois de aprovado se passa ao código.

## Ordem de trabalho

1. **Desenho** no artefacto e aprovação.
2. Em paralelo, e sem depender do desenho: lógica pura (próxima toma, resumo do widget) com testes.
3. Pôr em prática [[fila-offline]] (pelo menos o envio idempotente com `eventoEm`), porque o widget e a voz dependem de registar com segurança.
4. Parte 2, passos 1 e 2 (uma toma de cada vez e confirmação): ganho imediato e sem dependências novas.
5. Widget Android (pequeno, depois médio, depois configuração).
6. Leitura em voz alta, depois confirmação por voz, depois alto contraste.
7. Widget iPhone, se houver meios (macOS ou `xtool`).
8. Atualizar a [[dpia-rascunho]] e a [[politica-privacidade-rascunho]] (microfone) e o [[design]].

## Riscos

- **O widget mostra dados de saúde no ecrã inicial.** Por isso o nome do medicamento está desligado por omissão.
- **Toques acidentais:** a janela de 60 segundos para desfazer é a defesa principal. Não ligar o "Tomei" a nada que não passe por ela.
- **A voz a registar sem querer:** por isso nunca regista sem confirmação visual.
- **Expectativas:** o widget e a voz não são alarmes. Se a pessoa depender deles para lembrar, falham com o telemóvel em modo de poupança. Dizê-lo nos textos de ajuda e fazer os alarmes locais.

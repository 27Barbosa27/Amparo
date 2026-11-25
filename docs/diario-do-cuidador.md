# Diário do cuidador

Estado: por implementar. Depende de [[varios-cuidadores]] (só faz sentido com mais de um cuidador) e usa a tabela `notas` definida em [[sintomas-e-efeitos]]. Relacionado com [[plano]], [[design]] e [[plano-pago]].

> **Para quem vai implementar: desenhar primeiro.** Antes de escrever código na app, desenhar os ecrãs no artefacto do Claude Design (https://claude.ai/artifact/M1NgwcwbWDTxp2fK6r7s9R, ver [[design]]) e só depois implementar. A lista do que desenhar está em "Desenho (fazer primeiro)". O servidor pode avançar em paralelo. No fim, atualizar a contagem de ecrãs em [[design]].

## Para que serve

Quem cuida de alguém em equipa (os filhos, um casal, uma ajudante em horário) usa hoje o WhatsApp, um caderno na mesa da cozinha ou a memória: "hoje comeu pouco", "o médico ligou, volta na quinta", "o pai disse que o joelho doía". Quando o cuidador seguinte chega, parte do que se passou perdeu-se.

O **diário do cuidador** é o **caderno de passagem de turno**, partilhado entre cuidadores, ligado à pessoa e às tomas, sem espalhar dados de saúde pelo WhatsApp.

**A app guarda o que os cuidadores escrevem e nunca o interpreta.** Sem alertas por palavras, sem resumos automáticos, sem "o seu pai parece estar pior". Isto é a regra "a app não substitui o médico".

## O que se quer

1. **Escrever uma nota** em dois toques, visível aos outros cuidadores.
2. **Ver o que se passou hoje e ontem**, por ordem, com quem escreveu e a que horas.
3. **Fixar** o que é importante e não se pode perder ("Alergia à penicilina", "Prefere o comprimido com iogurte").
4. **Saber que o outro viu:** uma marca "Visto por…" na passagem de turno.
5. **Filtrar por etiqueta** (comida, sono, dor, visitas, outro) sem que a app as escolha.

Fora de âmbito: conversa em tempo real, resposta a notas, imagens (por agora), notas à pessoa acompanhada, resumos automáticos.

## Decisões

| Decisão | Escolha | Porquê |
|---|---|---|
| Tabela | A mesma `notas` de [[sintomas-e-efeitos]], com `tipo = 'cuidador'` | Uma só estrutura, uma só cifra, uma só exportação |
| Quem escreve e lê | **Dono e cuidadores.** O leitor e o telemóvel da pessoa **não** vêem estas notas | São observações sobre a pessoa, escritas para outros cuidadores |
| Transparência | A pessoa tem direito a saber que existem (ver "Privacidade e dignidade") | RGPD e respeito |
| Etiquetas | Fixas e escolhidas por quem escreve: Comida, Sono, Dor, Humor, Visitas, Medicação, Outro | Para filtrar, sem a app inferir nada |
| "Visto por" | Por nota, por utilizador, só entre cuidadores | Passagem de turno sem mensagens de "já viste?" |
| Edição | O autor edita e apaga as suas; o dono apaga qualquer uma | Evita notas que ninguém pode corrigir |
| Fixar | Dono e cuidadores; no máximo **5 fixadas** | Não vira uma lista infinita |
| Plano | Plano pago ([[plano-pago]]) | Só interessa com vários cuidadores, que já é parte do plano pago |

## Modelo de dados

Usa `notas` de [[sintomas-e-efeitos]] (`tipo = 'cuidador'`, `etiquetas`, `fixada`) e acrescenta a tabela de leituras:

```sql
create table notas_vistas (
  nota_id uuid not null references notas (id) on delete cascade,
  user_id uuid not null references users (id) on delete cascade,
  vista_em timestamptz not null default now(),
  primary key (nota_id, user_id)
);
create index notas_vistas_user_idx on notas_vistas (user_id, vista_em);

alter table alert_prefs add column notas_cuidador boolean not null default false;
```

- Etiquetas permitidas, validadas no servidor: `comida`, `sono`, `dor`, `humor`, `visitas`, `medicacao`, `outro`. Uma nota tem até 3.
- A nota é visível para quem tinha acesso **no momento em que lê** (se um cuidador sai, deixa de ver tudo, incluindo o que escreveu; o texto fica, sem o nome dele).

## Backend

Reutiliza as rotas de `notas` de [[sintomas-e-efeitos]] com estas diferenças:

- O filtro `?tipo=cuidador` só responde a dono e cuidador; ao leitor e ao dispositivo devolve vazio ou 403.
- `POST /profiles/:id/notas/:nid/vista` (cuidadores): marca como vista, idempotente. `GET` devolve, por nota, os nomes de quem a viu.
- `PATCH /profiles/:id/notas/:nid` com `{ fixada }` (dono e cuidador), recusando a 6.ª fixada com `limite_de_fixadas`.
- Push **opcional e sem conteúdo**: "O Rui acrescentou uma nota sobre a Maria." Quem o recebe é quem ligou `notas_cuidador` (desligado por omissão, para a passagem de turno não virar ruído).
- Auditoria sem conteúdo: `nota.criar`, `nota.fixar`, `nota.apagar`.

### Testes

- O leitor e o telemóvel da pessoa não vêem estas notas, em lista nem em detalhe (testar as duas rotas).
- Um cuidador marca "vista" duas vezes, só há uma linha.
- A 6.ª fixada é recusada.
- Um cuidador removido ([[varios-cuidadores]]) deixa de as ver; o texto das que escreveu fica e o nome some.
- O texto está cifrado; o push não leva texto.

## App

### Onde aparece (fora das Definições)

- No cartão da pessoa, junto de "Quem cuida da Maria": uma linha **"Diário"** com a última nota e a contagem de notas novas desde a última vez que o cuidador abriu.
- Abre o **diário**: as notas fixadas no topo, depois "Hoje", "Ontem" e "Mais antigas", cada nota com o nome de quem escreveu e a hora.
- Botão "Escrever" sempre à vista.

### Escrever

- Texto livre (até 500 caracteres), etiquetas opcionais, uma opção "Fixar".
- Sem rede, a nota entra na fila ([[fila-offline]]) com o `id` gerado na app.
- Quando se marca uma toma, o cuidador pode **acrescentar uma nota** a partir do ecrã de sucesso ("Acrescentar nota ao diário"), já ligada ao medicamento.

### Passagem de turno

- Ao abrir o diário, as notas novas desde a última visita têm um ponto de realce neutro. Ao fazer scroll até elas, ficam como vistas.
- Cada nota mostra "Visto por Rui, Ana"; se ainda ninguém viu, não mostra nada (sem "por ver" a pressionar).

### Privacidade e dignidade

- Texto de primeira utilização, uma vez: "As notas do diário são partilhadas entre os cuidadores da Maria. Escreva como se ela as pudesse ler: tem esse direito."
- A pessoa acompanhada tem **direito de acesso** a estes dados (RGPD). O que implica:
  - as notas entram na **exportação do perfil** (`perfis/exportacao.ts`), pedida pelo dono;
  - o dono pode ativar **"A Maria vê o diário"** (desligado por omissão), e então as notas passam a aparecer no telemóvel da pessoa. Se for ativado, os restantes cuidadores são avisados.
- Atualizar [[dpia-rascunho]] e [[politica-privacidade-rascunho]]: passa a haver observações de terceiros sobre a pessoa, guardadas e partilhadas.

### Testes

- Um leitor não vê "Diário" nem nada relacionado.
- Escrever, ver, fixar (e o limite de 5), apagar.
- O contador de novas só conta notas de outros.
- O texto de primeira utilização aparece uma só vez.
- A opção "A Maria vê o diário" mostra as notas no telemóvel da pessoa e avisa os cuidadores.

## Desenho (fazer primeiro)

No artefacto do Claude Design, nos temas claro e escuro:

1. **Linha "Diário"** no cartão da pessoa, com e sem notas novas.
2. **Lista do diário:** fixadas, hoje, ontem, mais antigas; vazia.
3. **Escrever uma nota:** texto, etiquetas, fixar, erro de limite.
4. **Detalhe de uma nota:** quem a escreveu, quem a viu, editar, apagar.
5. **Texto de primeira utilização** (sobre a dignidade e o direito de acesso).
6. **Opção "A Maria vê o diário"** e o aviso aos outros cuidadores.
7. **Acrescentar uma nota** a partir do ecrã de sucesso da toma.

Decisões a resolver no desenho:
- Como distinguir uma nota **fixada** (informação permanente) de uma do dia, sem poluir.
- Como mostrar "Visto por…" sem criar pressão.

## Ordem de trabalho

1. **Desenho** e aprovação.
2. Depende de [[varios-cuidadores]] e da tabela `notas` de [[sintomas-e-efeitos]].
3. Rotas de leitura e fixação, `notas_vistas` e testes de visibilidade.
4. App: lista, escrever, passagem de turno.
5. Opção "A pessoa vê o diário" e a exportação.
6. Atualizar [[dpia-rascunho]], [[politica-privacidade-rascunho]] e [[design]].

## Riscos

- **O diário vira um juízo sobre a pessoa.** Por isso o texto de dignidade, o direito de acesso e a opção de a pessoa o ver.
- **Ruído:** o push de notas novas está desligado por omissão.
- **Dados sensíveis em texto livre** ("está confusa", "agitada"): cifrados, fora de logs e de notificações. A app não os classifica nem os resume.

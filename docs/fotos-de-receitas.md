# Foto da receita ou da caixa

Estado: por implementar. Relacionado com [[plano]], [[design]], [[varios-cuidadores]] e [[consultas-e-analises]] (os anexos são partilhados).

> **Para quem vai implementar: desenhar primeiro.** Antes de escrever código na app, desenhar os ecrãs no artefacto do Claude Design (https://claude.ai/artifact/M1NgwcwbWDTxp2fK6r7s9R, ver [[design]]) e só depois implementar. A lista do que desenhar está mais abaixo. O servidor pode avançar em paralelo, porque não depende do desenho.

## Problema

A pessoa tem a receita em papel (ou no telemóvel) e caixas de medicamentos parecidas. Na farmácia ou numa consulta de urgência, ter à mão **o que o médico escreveu** e **como é a caixa** poupa tempo e evita trocas. Hoje a app só guarda texto.

## O que se quer

1. Associar a uma receita **uma ou mais fotos**: da receita (o papel) e da caixa.
2. Ver as fotos na receita, em miniatura, e ampliar com zoom.
3. As fotos ocuparem **pouco espaço na base de dados** sem perderem legibilidade: o texto da receita tem de se ler.
4. Estar tudo **cifrado** e visível só a quem tem acesso ao perfil.

Fora de âmbito: ler a foto (OCR) e preencher o formulário. A **importação de receitas está em espera**; este documento só trata de guardar e mostrar imagens. As fotos de [[consultas-e-analises]] (pedidos e resultados) usam o mesmo mecanismo, por isso ele é feito já com isso em mente.

## Decisões

| Decisão | Escolha | Porquê |
|---|---|---|
| Onde se guardam | Na **base de dados** (Postgres, `bytea`), em tabelas próprias, separadas das receitas | Pedido do projeto: um só sítio, um só backup. A interface deixa trocar por armazenamento de ficheiros mais tarde (ver "Escalar") |
| Formato final | **WebP** | Bem mais leve do que JPEG para a mesma legibilidade; suportado em todos os telemóveis atuais e no Flutter |
| Quem converte | O **servidor** (biblioteca `sharp`) | Uma só implementação, igual para Android, iOS e web, e o servidor nunca confia no que o telemóvel mandou |
| Compressão no telemóvel | Reduzir antes de enviar (máx. 2000 px, JPEG de boa qualidade) | Poupa dados móveis e tempo de envio; o servidor faz a compressão final |
| Cifra | Cifrar **depois** de comprimir, com a chave do perfil | Dados cifrados não se comprimem; fazê-lo por esta ordem dá o ficheiro mais pequeno |
| Metadados | Remover tudo (EXIF, GPS) | A localização de uma foto de receita não é para ninguém |
| Quanto | Máx. 5 por receita, 30 por perfil, 40 MB por perfil | Evita que a base cresça sem controlo |

## Compressão sem perder qualidade (o ponto principal)

**Objetivo:** cada foto fica ao redor de **100 a 250 KB** em vez de 3 a 8 MB, e o texto continua legível.

Uma nota de honestidade: o WebP com perdas descarta sempre um pouco de informação. O que se garante é que **não há perda visível** para o uso (ler uma receita, reconhecer uma caixa), e valida-se com fotografias reais antes de fixar os valores.

### Pipeline no servidor

1. **Receber** até 8 MB por pedido (JPEG, PNG ou WebP). Confirmar o tipo pelos primeiros bytes do ficheiro, não pela extensão.
2. **Decodificar e proteger:** `sharp(entrada, { limitInputPixels: 40_000_000, failOn: 'error' })`. Isto recusa imagens-bomba e ficheiros corrompidos.
3. **Endireitar:** `.rotate()` (sem argumentos) aplica a orientação EXIF. Sem isto, as fotos tiradas de lado ficam deitadas.
4. **Redimensionar:** `.resize({ width: 1600, height: 1600, fit: 'inside', withoutEnlargement: true })`. 1600 px no lado maior chega para ler uma receita A5 fotografada de perto; **nunca se aumenta** uma imagem pequena.
5. **Converter:** `.webp({ quality: 80, effort: 5, smartSubsample: true })`. Os metadados saem por omissão (o `sharp` só os mantém se se pedir).
6. **Validar o tamanho:** se o resultado passar de **400 KB**, repetir com `quality: 70`; se ainda assim passar, com 1400 px. **Nunca descer abaixo de qualidade 60** nem de 1200 px. Para além disso, aceita-se o ficheiro maior em vez de o estragar.
7. **Miniatura:** outra versão com 360 px no lado maior e `quality: 70`, ao redor de **10 a 25 KB**, para as listas.
8. **Cifrar** as duas versões com a chave do perfil e guardar.

### Valores a confirmar com um teste (fazer antes de fixar)

Com 10 fotos reais (receitas em papel com letra pequena, caixas com letra de rodapé, fotos com pouca luz), correr a conversão com `quality` 70, 75, 80 e 85 e 1200, 1600 e 2000 px, e escolher os valores mais baixos em que **todo o texto se lê no tamanho original de uma tela de telemóvel**. Se o texto fino não aguentar, **subir a qualidade antes de reduzir as dimensões**, e considerar `nearLossless` para fotos de documentos. Registar a decisão neste ficheiro, com os tamanhos medidos.

Guardar essas fotos de teste em `backend/tests/fixtures/` (sem dados reais: usar receitas inventadas) e escrever um teste que garanta que o resultado fica abaixo do limite e com as dimensões esperadas, para ninguém estragar a compressão sem dar por isso.

### Estimativa de espaço

Com 220 KB por foto e 10 fotos por perfil, são cerca de 2,2 MB por perfil. Mil perfis: cerca de 2,2 GB. A base cresce, mas de forma previsível. Atenção ao backup: o `deploy/backup.sh` guarda 14 cópias, e os ficheiros WebP cifrados **não se comprimem** de novo, por isso o espaço dos backups cresce na mesma medida.

## Modelo de dados

```sql
create type tipo_imagem as enum ('receita', 'caixa', 'pedido', 'resultado');

create table imagens (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles (id) on delete cascade,
  receita_id uuid references receitas (id) on delete cascade,
  compromisso_id uuid,              -- passa a referenciar compromissos quando existir ([[consultas-e-analises]])
  tipo tipo_imagem not null,
  largura int not null,
  altura int not null,
  bytes int not null,               -- tamanho da versão principal, para a quota
  sha256 bytea not null,            -- para recusar duplicados exatos
  criado_por_user_id uuid references users (id) on delete set null,
  criado_em timestamptz not null default now(),
  check (num_nonnulls(receita_id, compromisso_id) = 1)
);
create index imagens_receita_idx on imagens (receita_id);
create unique index imagens_duplicadas_idx on imagens (receita_id, sha256) where receita_id is not null;

create table imagens_dados (
  imagem_id uuid primary key references imagens (id) on delete cascade,
  principal bytea not null,         -- WebP cifrado
  miniatura bytea not null          -- WebP cifrado
);
alter table imagens_dados alter column principal set storage external;
alter table imagens_dados alter column miniatura set storage external;
```

- Os **metadados** estão em `imagens` e os **bytes** em `imagens_dados`: listar as fotos de uma receita nunca lê blobs.
- `storage external` diz ao Postgres para guardar os bytes fora da linha sem tentar comprimi-los (já estão comprimidos e cifrados).
- Quando se criar `compromissos`, juntar a chave estrangeira de `compromisso_id` nessa migração.

## Backend

### Módulo `backend/src/imagens/` (novo)

- **Interface `ArmazemImagens`** (`guardar`, `ler`, `apagar`) e uma implementação `ArmazemPostgres`. O resto do código só fala com a interface, para trocar por armazenamento de ficheiros no futuro sem tocar nas rotas.
- **`processarImagem(buffer)`**: o pipeline acima; devolve `{ principal, miniatura, largura, altura }`.
- **Cifra de bytes:** `auth/cifra.ts` cifra texto (`cifrar(texto, chave)`); acrescentar `cifrarBytes` e `decifrarBytes` com o mesmo AES-GCM e a mesma chave por perfil.
- **Controlo de recursos:** o `sharp` gasta CPU e memória. Limitar a 2 conversões em simultâneo (um semáforo simples) e `sharp.cache(false)`, para uma rajada de uploads não deitar abaixo o servidor pequeno.

### Rotas

| Pedido | Quem | Corpo | Resposta |
|---|---|---|---|
| `POST /profiles/:id/receitas/:rid/imagens?tipo=` | dono, cuidador | corpo bruto `image/jpeg \| png \| webp`, até 8 MB | `201 { id, largura, altura }` |
| `GET /profiles/:id/receitas/:rid/imagens` | qualquer membro | | lista de metadados (sem bytes) |
| `GET /profiles/:id/imagens/:iid?tam=mini\|grande` | qualquer membro | | `image/webp` decifrado |
| `DELETE /profiles/:id/imagens/:iid` | dono, cuidador | | `204` |

- `express.json({ limit: '100kb' })` está definido globalmente (`app.ts`); o upload usa **`express.raw`** só nesta rota, com o limite de 8 MB.
- Limite de envios por utilizador (por exemplo 20 por hora) com o `express-rate-limit` já usado.
- `GET` com `Cache-Control: private, max-age=86400` e `ETag` com o `sha256`, porque o conteúdo de uma imagem nunca muda. **Nunca** `public`.
- Verificar a quota (5 por receita, 30 por perfil, 40 MB) antes de converter, e devolver `limite_de_imagens` (409).
- Erros: `imagem_invalida` (400) para tipo errado ou ficheiro corrompido, `imagem_grande_demais` (413).
- Auditoria: `imagem.criar` e `imagem.apagar`. Nunca registar nada do conteúdo.
- A exportação do perfil (`perfis/exportacao.ts`) inclui as imagens decifradas; o `on delete cascade` apaga-as com a receita e com o perfil.

### Segurança

- A imagem enviada **nunca é servida tal como chegou**: é sempre reconvertida. Isto elimina ficheiros disfarçados.
- A foto de uma receita pode mostrar o **código de acesso e dispensa** e o **código de direito de opção**, que permitem levantar medicamentos, além do nome e do número de utente. Por isso:
  - o ecrã de carregar avisa: "A foto pode mostrar códigos e dados pessoais. Tire só a parte que precisa.";
  - numa fase seguinte, deixar **cortar** a imagem antes de enviar.
- O `sharp` usa binários pré-compilados; a imagem de produção é `node:24-slim` (glibc), compatível. Confirmar no `Containerfile` que o `npm ci` os instala e que o aviso sobre scripts de instalação não os bloqueia.

### Testes

- O fluxo completo: enviar um JPEG de 4 MB, receber WebP com menos de 400 KB, largura máxima de 1600 px.
- Ficheiro corrompido, tipo falso (PNG com extensão `.jpg`, executável renomeado), imagem enorme em píxeis: recusados.
- Os bytes na base estão cifrados (não começam por `RIFF…WEBP`).
- Uma foto com EXIF de GPS sai sem EXIF; uma foto tirada de lado sai endireitada.
- Quota: a 6.ª foto de uma receita dá `limite_de_imagens`.
- Acesso: outro perfil recebe 404; um leitor não consegue enviar nem apagar, mas consegue ver.
- Duplicado exato (mesmo `sha256` na mesma receita) não cria uma segunda linha.

## App

### Dependências

- `image_picker`: câmara e galeria, com `maxWidth`/`maxHeight: 2000` e `imageQuality: 85`. Faz já a redução no telemóvel e, no iPhone, entrega JPEG em vez de HEIC (o servidor não lê HEIC).
- Para o zoom, o `InteractiveViewer` que já vem no Flutter (sem dependência nova).
- Na web (Chrome, usado para testar), o `image_picker` abre o seletor de ficheiros.

### Modelo e estado

- `ImagemReceita` (`id`, `tipo`, `largura`, `altura`) em `dominio/modelos.dart`.
- `Repositorio`: `imagens(perfilId, receitaId)`, `enviarImagem(perfilId, receitaId, bytes, tipo)`, `apagarImagem`, `bytesDaImagem(perfilId, imagemId, miniatura)`. Versão real e falsa (`test/apoio/`).
- Sem cache em disco na primeira versão (as imagens são dados de saúde; só ficam em memória enquanto o ecrã está aberto). Pedir sempre com a sessão.

### Ecrãs

Ver "Desenho". A implementação reutiliza os componentes existentes.

- **Receita:** uma secção "Fotos" com as miniaturas, "Adicionar foto" e o contador "2 de 5".
- **Adicionar:** escolher "Tirar foto" ou "Galeria", escolher o tipo (receita ou caixa), pré-visualizar e confirmar, com barra de progresso e o aviso dos códigos.
- **Ver:** ecrã inteiro com zoom e "Apagar".
- **Sem ligação:** mensagem clara. Enviar fotos precisa de rede (não entra na fila offline, ver [[fila-offline]]).

### Testes

- Adicionar mostra o progresso e a miniatura; o limite mostra a mensagem certa; apagar pede confirmação.
- Um leitor ([[varios-cuidadores]]) vê as fotos sem os botões de adicionar e apagar.

## Desenho (fazer primeiro)

No artefacto do Claude Design, nos temas claro e escuro, com as convenções de [[design]]:

1. **Secção "Fotos"** na receita: vazia, com 1 foto, com várias, e no limite.
2. **Adicionar foto:** escolha câmara/galeria, escolha do tipo, pré-visualização, envio em curso, aviso dos códigos e dados pessoais.
3. **Visualizador** em ecrã inteiro, com zoom e apagar.
4. **Estados:** sem ligação, falha ao enviar, limite atingido, a carregar miniaturas.
5. **Modo simples da pessoa** (opcional, ver [[widget-e-modo-simples]]): mostrar a foto da caixa em grande no momento da toma, para a reconhecer.

Só depois de aprovado se passa ao código da app.

## Escalar (quando a base começar a pesar)

Guardar imagens em `bytea` serve bem até alguns GB. Reavaliar quando as imagens passarem de **cerca de 5 GB** ou o backup diário ficar lento: passar o `ArmazemPostgres` para um armazenamento de objetos compatível com S3, **mantendo as imagens cifradas antes de saírem do servidor** (a chave continua a ser a do perfil). Como as rotas só falam com a interface `ArmazemImagens`, a troca não toca na app.

## Ordem de trabalho

1. Teste de qualidade (10 fotos, ver acima) e fixar os valores de compressão. Escrever o resultado neste ficheiro.
2. Migração, `processarImagem`, cifra de bytes e testes.
3. Rotas e quotas, com os testes de segurança.
4. **Desenho** no artefacto (em paralelo com os passos 1 a 3).
5. App: `image_picker`, repositório, secção "Fotos" e visualizador, com testes.
6. Atualizar [[dpia-rascunho]] (as fotos podem mostrar dados de terceiros e códigos de levantamento) e [[deploy]] (espaço de backups).

## Em espera

A **importação por foto** (ler o texto da receita e sugerir o formulário) não faz parte deste trabalho. Se se retomar, usa estas mesmas imagens como entrada, e a pessoa confirma cada campo; a app nunca guarda os códigos de acesso nem de direito de opção.

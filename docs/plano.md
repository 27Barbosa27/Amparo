# Master Plan v3: Amparo, App de Gestão de Saúde e Medicação (MVP)

> **Nome da app: Amparo** (decidido a 22 nov 2026). Antes de publicar falta confirmar: pesquisa de marca no INPI (PT) e no EUIPO (classes de software e saúde), procura direta na App Store e Google Play a partir de Portugal, e domínio `amparo.pt`. Já se sabe que existem outras coisas chamadas Amparo noutros setores (uma app "Amparo Immigration Tracker", a devoção Nossa Senhora do Amparo, a Rádio Amparo), por isso o nome é pouco distintivo e deve vir acompanhado de uma descrição clara nas lojas (por exemplo "Amparo: lembretes de medicação e cuidadores"). Identificador sugerido da app: `pt.amparo.app` (só definitivo depois de confirmado, porque não se muda depois de publicar).

> Base: v2 (`message_v2.md`) + decisões tomadas no design (25 ecrãs, Claude Design: https://claude.ai/artifact/M1NgwcwbWDTxp2fK6r7s9R). As secções sem alterações vêm da v2 e estão aqui completas para este documento ser autónomo.

## 0. O que mudou face à v2

| Tema | v2 | v3 |
|---|---|---|
| Login | email + password | email + password **+ Apple + Google**. Sem botão de Face ID no Entrar: o iPhone já preenche as credenciais com o Face ID (Palavras-passe/Keychain). A biometria da app fica só no **desbloqueio ao abrir** (ecrã de biometria e PIN) |
| Registo | não descrito | ecrã de registo com **consentimento explícito** para dados de saúde |
| Perfis | cuidador gere vários idosos; idoso pode ter login (`self`) | **só cuidadores têm conta.** Quem cuida cria o perfil da pessoa ("Adicionar pessoa": pseudónimo, quem recebe os alarmes, tamanho do texto). A pessoa **não cria conta**: o telemóvel dela liga-se por **código de ligação** (secção 3.5) |
| Tomas | `pendente/tomada/saltada/falhada` | + **atrasada** (derivada), hora real da toma escolhida pelo utilizador, **quem registou** (idoso ou cuidador), **desfazer 1 min** |
| Alertas ao cuidador | fora do MVP | **ecrã desenhado** (toma não confirmada, toma feita, receita a acabar) → usa **push via FCM** (secção 3.4); decisão tomada |
| Receitas | intenção + geração de tomas | + validade, unidades restantes e "dias que restam" (MVP-lite de stock) |
| Texto | respeita o tamanho do sistema | + definição **por perfil** (Normal / Grande / Muito grande) |
| Permissões Android/iOS | onboarding genérico | **ecrã "Alarmes fiáveis"** com 3 permissões e estado |
| Offline | fila local | + **estado visível** (faixa "Sem ligação, as confirmações ficam guardadas") |

## 1. Visão Geral e Regras de Negócio

**Objetivo:** App de gestão de medicação (lembretes e registo de tomas), concebida para evoluir para controlo de stock e gestão de sintomas.

**Âmbito regulatório:** a app é um *lembrete e registo*. Não sugere doses, não alerta para interações, não dá aconselhamento clínico. Isto mantém-na fora da classificação de dispositivo médico (MDR). Qualquer funcionalidade que ultrapasse isto exige reavaliação. (O aviso "Não tome em dobro. Se tiver dúvidas, ligue à Ana." é só um lembrete de cuidado e remete para uma pessoa, não dá aconselhamento.)

**Público-Alvo:** Idosos (alto contraste, alvos de toque ≥ 44 px, respeita o tamanho de letra do sistema, compatível com leitor de ecrã, pt-PT) e Cuidadores.

**Contas e perfis:** **só os cuidadores têm conta** (email, Apple ou Google). Os idosos acompanhados **não criam conta**: é o cuidador que cria o perfil deles e que decide onde recebem os alarmes:
- **No telemóvel da pessoa:** o telemóvel liga-se ao perfil com um **código de ligação** (sem email, sem password) e passa a mostrar o **modo simples**.
- **No telemóvel do cuidador:** o cuidador recebe os alarmes e confirma por ela.

Um cuidador gere vários perfis; a interface exige a seleção do "Perfil Ativo" antes de apresentar dados. O cuidador pode **ver como a pessoa vê** (pré-visualização do modo simples) no seu próprio telemóvel.

**Dois modos de ecrã** (mesma app, vistas do mesmo perfil):
- **Modo cuidador:** Hoje (resumo, 7 dias, linha do tempo), Receitas, Mais.
- **Modo simples (idoso):** Hoje com a toma atrasada ou próxima em destaque, alarme em ecrã inteiro, confirmação. É o único modo no telemóvel de uma pessoa ligada por código.

**Alarmes (Snooze):** disparados localmente. "Adiar 10 minutos" funciona com a app fechada (notification actions em background). O ecrã "Alarme adiado" mostra a nova hora.

**Fora do MVP:** stock completo, sintomas, interações, relatório PDF.

## 2. Stack Tecnológica

| Camada | Escolha |
|---|---|
| Mobile | Flutter (Dart). Dev diário em Windows Desktop para UI; **testes de alarmes, biometria e background sempre em dispositivo Android real e em iPhone** (Face ID e "Entrar com a Apple" só testam no iPhone) |
| Backend | Node.js + Express (TypeScript), validação com Zod |
| Base de dados | PostgreSQL, migrações versionadas (node-pg-migrate ou Drizzle) |
| Local | Podman Desktop (WSL2), PostgreSQL na 5432 |
| Produção | VPS Linux na UE, Podman rootless, Caddy com TLS automático |

## 3. Regras Arquiteturais Críticas

### 3.1 Receitas e Tomas
- `receitas` guarda a **intenção**: medicamento, dose, tipo de horário (`intervalo` ou `horas_fixas`), intervalo em horas ou lista de horas locais, `timezone` IANA, início e fim, **validade** e **unidades iniciais**.
- O Node gera linhas em `tomas` (UTC) a partir da receita. **Janela rolante** de 30 a 90 dias com job diário.
- **Formulário "Adicionar receita"** mapeia assim: "de 8 em 8 horas" → `intervalo=8`; "2 vezes ao dia" / "1 vez ao dia" → `horas_fixas` a partir da "primeira toma"; "Outra" → editor avançado; duração 7 dias / 1 mês / 3 meses → `fim_utc` (máximo 3 meses por geração, depois renova).
- Estados persistidos: `pendente`, `tomada`, `saltada`, `falhada`. **"Atrasada" não é estado:** é derivada (`pendente` e `agendada_utc` + tolerância < agora). `falhada` é marcada por job quando passa a janela configurada.
- Ao registar uma toma o utilizador escolhe a **hora real**: Agora / Há 1 hora / À hora prevista / Outra hora → `tomada_em_utc`.
- **Quem registou:** `origem` (`dispositivo` quando a pessoa confirma no telemóvel dela, `cuidador` quando é o cuidador) e, no caso do cuidador, `registada_por_user_id`. O ecrã do cuidador mostra "Marcada pela Ana, hoje às 12:50" e a pessoa vê essa marcação.
- **Desfazer:** durante 1 minuto o registo pode ser revertido (volta a `pendente`, regista-se no audit log). Depois disso só por edição explícita.
- **Saltar:** estado `saltada`, também com `registada_por`.
- **Edição de receita:** regenera só tomas futuras com `editada_manualmente = false` e estado `pendente`. Tomas editadas ou registadas nunca são tocadas.
- **"De 8 em 8h"** é intervalo absoluto (UTC). **"Às 8h"** é hora local, gerada a partir da `timezone` da receita.
- **Unidades restantes:** `unidades_iniciais` menos tomas `tomada` (a dose define quantas unidades por toma). "Restam N dias" = unidades restantes / consumo médio. É um indicador, não stock completo.

### 3.2 Fuso Horário
Tudo em UTC. A hora local só existe na apresentação e na intenção da receita.

### 3.3 Alarmes Locais (limites das plataformas)
- **iOS:** ~64 notificações locais pendentes. Agendar os próximos ~7 dias (ou ~50 tomas) e reagendar a cada abertura e a cada background fetch.
- **Android:** `SCHEDULE_EXACT_ALARM`/`USE_EXACT_ALARM`; otimização de bateria (Doze, Xiaomi/Samsung/etc.).
- **Ecrã "Alarmes fiáveis"** acompanha 3 permissões, cada uma "Feito" ou "Falta": alarmes exatos, bateria sem limites, apresentar sobre o ecrã bloqueado. Em "Mais" aparece o aviso "N em falta" enquanto houver pendentes.
- O `workmanager` é complemento, nunca a única garantia.
- Os alarmes tocam **sem exigir desbloqueio biométrico**.
- **Spike obrigatório antes de tudo o resto** (secção 6).

### 3.4 Sincronização (Firebase só para push)
- **App Lifecycle:** `GET /tomas?since=` quando a app passa a `resumed`.
- **Background Fetch:** `workmanager` periódico, reagendando alarmes localmente.
- **Fila offline:** marcar toma sem rede grava numa fila local e é enviada com **chave de idempotência**. Conflitos: ganha o evento mais recente; o servidor guarda sempre o histórico.
- **Estado visível:** sem ligação, o ecrã mostra a faixa "As confirmações ficam guardadas e seguem quando houver rede".
- **Uma edição do cuidador** chega ao telemóvel da pessoa por um push de sincronização; sem push, só quando a app abre ou o background fetch corre.
- **Push: decisão tomada, Firebase Cloud Messaging (FCM), e só isso do Firebase.**
  - **O que se usa:** apenas o envio de notificações. O FCM é gratuito e leva os avisos ao Android e, via APNs, ao iPhone, com uma só integração (`firebase_messaging` no Flutter e o SDK de administração no Node).
  - **O que NÃO se usa do Firebase:** Firestore, Authentication, Analytics e Crashlytics. A base de dados continua a ser o PostgreSQL e o login é o descrito em 3.5. A regra "sem Firebase" da v2 passa a querer dizer "sem Firebase como backend".
  - **Conteúdo das mensagens:** nunca dados de saúde nem nomes de medicamentos. Só um tipo de evento e um identificador opaco (por exemplo `{ tipo: "alerta", perfil: <uuid> }`). A app, ao receber, vai ao servidor buscar o detalhe por HTTPS e mostra a notificação localmente, por isso o texto "Rosa não confirmou a toma" nasce no telemóvel e não passa pela Google.
  - **Tokens:** o telemóvel regista o seu token FCM no servidor (`push_tokens`, ligado ao utilizador ou ao dispositivo da pessoa). Tokens inválidos ou revogados são apagados quando o FCM os rejeita, e o cuidador ao desligar um telemóvel invalida o token.
  - **Tipos de push:** (1) **alerta ao cuidador** (toma não confirmada, toma feita, receita a acabar), notificação normal e visível; (2) **sync**, mensagem de dados para o telemóvel da pessoa recolher mudanças. No iPhone os (2) são menos fiáveis, por isso continuam a existir app lifecycle e background fetch como rede de segurança.
  - **Os alarmes das tomas continuam locais.** O push nunca é a garantia de um alarme tocar.
  - **Quem recebe:** respeita `alert_prefs` (toma não confirmada ao fim de 10, 15 ou 30 min, toma feita, receita a acabar N dias antes). O servidor gera o alerta de "toma não confirmada" com um job que corre a cada minuto.

### 3.5 Autenticação e Autorização
- **Métodos de entrada:**
  1. Email + password (**Argon2id**).
  2. **Entrar com a Apple** e **Entrar com a Google**: a app obtém o *ID token* do fornecedor e o Node valida-o (assinatura, `aud`, `exp`, `nonce`) e cria ou associa o utilizador. Sem Firebase Authentication.
  3. **Face ID / impressão digital**: **desbloqueio local** da app ao abrir ou regressar de segundo plano (`local_auth`), não é uma forma de criar conta nem de autenticar no servidor. **Não há botão "Entrar com Face ID"** nos ecrãs de Entrar e Criar conta: no iPhone o sistema já oferece o Face ID para preencher email e palavra-passe (campos com `autofillHints` corretos: `email`, `password`, `newPassword`), e o "Entrar com a Apple" usa o Face ID do próprio sistema.
- **Quem tem conta:** só cuidadores. Entrar e Criar conta são ecrãs de cuidador ("Criar conta de cuidador").
- **Ligação do telemóvel de uma pessoa (sem conta):**
  1. O cuidador cria o perfil e escolhe "A pessoa, no telemóvel dela". A app pede ao servidor um **código de ligação** de 6 dígitos (`POST /profiles/:id/pairing-codes`), **válido 15 minutos e de uso único**, guardado só como hash.
  2. Na app instalada no telemóvel da pessoa, o primeiro ecrã tem "Tenho um código". A pessoa introduz o código (`POST /pairing/redeem`), com **rate limiting** por IP e por código.
  3. O servidor devolve um **token de dispositivo** com âmbito de **um único perfil**, guardado no secure storage. Sem email, sem password, sem refresh de conta.
  4. O token de dispositivo **só pode:** ler as tomas do seu perfil, registar, saltar e desfazer tomas (≤ 1 min), e ler o contacto do cuidador. **Não pode:** editar receitas, ver outros perfis, alterar o perfil, nem gerar códigos.
  5. O cuidador pode **ver e revogar** os dispositivos ligados a cada perfil (`profile_devices.revogado_em`). Um telemóvel perdido deixa de funcionar de imediato.
  6. Cada ligação e revogação vai para o `audit_logs`.
- **Regra da Apple:** se a app oferece login com Google no iPhone, tem de oferecer também "Entrar com a Apple" (e vice-versa os dois aparecem juntos em Entrar e Registar).
- **Apple "esconder o meu email":** o email pode ser um *relay* e só chega na primeira autorização. Guardar o `sub` do fornecedor como identificador estável.
- **Email e recuperação de palavra-passe:** o email guarda-se de duas formas. O `email_hash` (HMAC com segredo) serve para encontrar a conta e impedir duplicados. O `email_cifrado` (AES-256-GCM, chave só no ambiente do servidor) serve para enviar o link de recuperação. O email nunca se guarda em claro, nunca se regista em logs e nunca se devolve à app. A chave de cifra tem versão no formato guardado, para se poder rodar.
- **Tokens:** access JWT 15 min + refresh com rotação e revogação em `flutter_secure_storage`. Rate limiting e bloqueio progressivo no login.
- **Tentativas locais:** biometria falhada mostra tentativas restantes e passa ao PIN; o PIN tem limite de tentativas, depois exige login completo (e remove a sessão do aparelho).
- **Perfil ativo:** header `X-Profile-Id`, validado por um middleware único contra `profile_access(user_id, profile_id, role, criado_em, revogado_em)`. Nenhuma rota acede a dados de perfil sem passar por ele.
- **Testes de IDOR obrigatórios** em todas as rotas.
- **Trocar de pessoa / adicionar pessoa** passam sempre por `profile_access` (o cuidador só vê perfis a que tem acesso ativo).

## 4. Cibersegurança e Conformidade (RGPD)

Dados de saúde são **categoria especial (art. 9.º)**. Pseudonimização é complementar, não suficiente.

- **Consentimento explícito** no registo do cuidador (caixa visível, não pré-aceite em produção), granular e revogável. Registar versão dos Termos e data.
- **Como a pessoa acompanhada não tem conta, o consentimento dela passa pelo cuidador.** Ao adicionar uma pessoa, o cuidador **declara que tem a autorização** da pessoa ou do seu representante legal (com data e versão do texto), e isto fica em `profile_access`. O primeiro ecrã do telemóvel da pessoa mostra uma **nota de privacidade em linguagem simples** (quem vê as tomas dela e como parar). A pessoa pode pedir o apagamento ao cuidador, e o apagamento do perfil apaga a chave cifrada.
- **DPIA** antes do lançamento.
- **Minimização:** pseudónimos nos perfis ("Avó Rosa"). A criação de perfil **não pede dados sensíveis**. Relações por UUID v4, nunca nomes ou emails como chave.
- **Encriptação:** TLS; disco e backups cifrados; campos clínicos cifrados na aplicação com **chave por perfil** (Crypto-Shredding).
- **Alojamento e subprocessadores na UE**, listados na política de privacidade. **Apple e Google passam a ser subprocessadores de autenticação** e têm de constar. **A Google (Firebase Cloud Messaging) e a Apple (APNs) são também subprocessadoras do envio de notificações:** constam na política de privacidade, com o acordo de tratamento de dados (DPA) da Google aceite na consola do Firebase, e só recebem identificadores opacos, nunca dados de saúde.
- **Retenção e apagamento:** política escrita; exportação (portabilidade) e apagamento de perfil.
- **Proteção local:** `local_auth` com tolerância de 30 a 60 s e fallback para PIN da app. **O PIN fica só no aparelho** (hash com sal no secure storage).
- **Número de telefone do cuidador** (botões "Ligar"): dado pessoal opcional, guardado cifrado e só visível a quem tem acesso ao perfil.
- **Log de Auditoria Imutável (`audit_logs`):** `ts_utc`, `user_id`, `profile_id`, `acao`, `entidade`, `entidade_id`, `ip`. **Nunca contém dados de saúde.** Regista escritas e leituras de dados de saúde por cuidadores, **incluindo "marcou como tomada" e "desfez registo"**. Imutabilidade imposta na BD (`REVOKE UPDATE, DELETE` + trigger), retenção documentada.

## 5. Esboço do Modelo de Dados

```
users(id uuid pk, email_hash null, email_cifrado null, password_hash null, telefone_cifrado null,
      consentimento_versao, consentimento_em, criado_em)
auth_providers(user_id fk, provider [apple|google], provider_sub, criado_em,
               pk(provider, provider_sub))
profiles(id uuid pk, pseudonimo, timezone, tamanho_texto [normal|grande|muito_grande],
         alarmes_em [dispositivo_da_pessoa|dispositivo_do_cuidador], chave_cifrada, criado_em)
profile_access(user_id fk, profile_id fk, role [owner|caregiver],
               autorizacao_declarada_em, autorizacao_versao, revogado_em,
               pk(user_id, profile_id))            -- só utilizadores com conta
pairing_codes(id uuid pk, profile_id fk, criado_por_user_id fk, codigo_hash,
              expira_em, usado_em null)             -- 6 dígitos, 15 min, uso único
profile_devices(id uuid pk, profile_id fk, token_hash, nome, criado_em,
                ultimo_uso_em, revogado_em)         -- telemóvel da pessoa, sem conta
push_tokens(id uuid pk, user_id fk null, device_id fk null, plataforma [android|ios],
            fcm_token_hash, criado_em, ultimo_uso_em, revogado_em)
            -- um token por telemóvel; o token em claro só é usado para enviar
alert_prefs(user_id fk, profile_id fk, toma_nao_confirmada bool, espera_min int,
            toma_feita bool, receita_a_acabar bool, dias_antes int,
            pk(user_id, profile_id))
medicamentos(id uuid pk, profile_id fk, nome_cifrado, notas_cifradas)
receitas(id uuid pk, profile_id fk, medicamento_id fk, dose_cifrada,
         tipo [intervalo|horas_fixas], intervalo_horas, horas_locais[],
         timezone, inicio_utc, fim_utc, valida_ate, unidades_iniciais, ativa)
tomas(id uuid pk, receita_id fk, profile_id fk, agendada_utc,
      estado [pendente|tomada|saltada|falhada], tomada_em_utc,
      registada_por_user_id null, origem [dispositivo|cuidador] null,
      editada_manualmente bool, idempotency_key unique)
refresh_tokens(id, user_id, hash, expira_em, revogado_em)
audit_logs(id bigserial, ts_utc, user_id, profile_id, acao, entidade,
           entidade_id, ip)   -- append-only
```
Índices: `tomas(profile_id, agendada_utc)`, `profile_access(profile_id)`, `auth_providers(user_id)`.

## 6. Mapa ecrãs → backend (resumo)

| Ecrã(s) | Endpoint / ação |
|---|---|
| Entrar, Criar conta | `POST /auth/login`, `/auth/register`, `/auth/apple`, `/auth/google`, `/auth/refresh` |
| Biometria, PIN | local (`local_auth` + secure storage); sem chamada de rede |
| Quem vai acompanhar | `GET /profiles` (só com acesso ativo) |
| Adicionar pessoa | `POST /profiles` (+ `profile_access` com a autorização declarada) |
| Ligar telemóvel de uma pessoa (cuidador) | `POST /profiles/:id/pairing-codes`; lista e revoga `GET/DELETE /profiles/:id/devices` |
| Telemóvel da pessoa · Código | `POST /pairing/redeem` → token de dispositivo de um só perfil |
| Trocar de pessoa | muda o `X-Profile-Id` ativo (local) |
| Hoje (cuidador / idoso) | `GET /tomas?since=` por perfil |
| Marcar como tomada / A que horas tomou | `POST /tomas/:id/registo` com `tomada_em_utc` e `idempotency_key` |
| Saltar / Desfazer registo | `POST /tomas/:id/saltar`, `POST /tomas/:id/desfazer` (≤ 1 min) |
| Receitas, Adicionar receita | `GET/POST/PATCH /receitas` (gera tomas) |
| Detalhe da toma | `GET /tomas/:id` + histórico dos 7 dias |
| Alertas ao cuidador | `GET/PUT /alert-prefs` |
| Lembrar a pessoa (card da próxima toma) | `POST /tomas/:id/lembrar` → push `lembrete` aos telemóveis dela, que mostram o alarme dessa toma |
| Ligar à pessoa | telefone opcional do perfil (`POST/PATCH /profiles`, `telefone`), abre o marcador |
| A sua conta | `GET /auth/me/exportacao` + `GET /profiles/:id/exportacao` (ficheiro JSON), `DELETE /auth/me` |
| Tamanho do texto | `PATCH /profiles/:id` (`tamanho_texto`) |
| Alarme / Adiar | local; reagenda a notificação 10 min |
| Alarmes fiáveis | local (estado das permissões) |
| Telemóveis ligados (estado) | `GET /profiles/:id/devices` devolve nome, ligado desde, **última ligação**, nº de alarmes agendados e estado das permissões. Estes dois últimos são **reportados pelo próprio telemóvel** num `POST /devices/heartbeat` (a cada sincronização) |
| Sucessos (conta, pessoa, telemóvel ligado, receita, definições, toma marcada) | respostas 2xx das ações acima; o ecrã de sucesso é só apresentação e mostra o que o servidor confirmou |
| Erros | códigos estáveis para a UI: `credenciais_invalidas`, `email_ja_existe`, `codigo_invalido`, `codigo_expirado` (mesma mensagem para inválido e expirado, para não revelar quais códigos existem), `sem_rede` (cliente), `falha_ao_guardar` |
| Carregamento | operações longas (gerar tomas da receita) são **assíncronas**: o cliente mostra os passos "Gerar as tomas, Agendar os alarmes, Sincronizar" e pode continuar em segundo plano |
| À espera da pessoa | o cuidador vê "À espera que a Rosa introduza o código…" por *polling* curto ou notificação; passa a "Telemóvel ligado" quando `POST /pairing/redeem` for usado |

## 7. Plano de Execução (por ordem)

> **Estado do backend (22 nov 2026):** os pontos 2, 3, 4 (servidor), 5 (servidor), 6 (servidor) e 7 (ficheiros de deploy, backups e CI) estão feitos e testados (256 testes, incluindo a recuperação de palavra-passe por email). Falta o que depende de contas externas ou da app: spike de alarmes (1), testes contra Firebase/Apple/Google verdadeiros, DPIA, política de privacidade e a VPS real. Ver `backend/README.md` e `docs/deploy.md`.

> **Estado da app (27 nov 2026):** alarmes locais ligados ao ecrã "Hoje" (só tocam no telemóvel de quem os recebe), alarme em ecrã inteiro com "Adiar 10 min", "Alarmes fiáveis" com as 3 permissões, push (FCM), estado do telemóvel da pessoa (heartbeat) e "Telemóveis ligados", "Lembrar" e "Ligar", entrar com a Apple (código pronto, sem conta Apple Developer para testar), exportar e apagar a conta. Falta testar tudo isto num Android real e o spike no iPhone (no iPhone os alarmes ainda estão desligados).

0. **Design:** feito (25 ecrãs). Manter o artefacto como referência; tokens (cores, tipografia, espaçamentos) passam para o tema Flutter.
1. **Spike técnico:** alarme exato com snooze em background, fiável em Android real **e iPhone**. Se falhar, o plano de alarmes muda antes de mais código.
2. **Modelo de dados e geração de tomas**, com testes unitários (intervalo, hora fixa, mudança de hora, edição, janela rolante, atrasada derivada, desfazer ≤ 1 min).
3. **Auth** (email, Apple, Google), **multi-perfil e autorização** (tokens, `profile_access`, IDOR).
4. **Sync:** delta, fila offline com idempotência, background fetch, estado offline visível.
5. **Segurança local e conformidade:** biometria com tolerância, PIN, cifra por perfil, auditoria, exportação e apagamento, consentimento.
6. **Alertas ao cuidador e push (FCM):** projeto Firebase só com Cloud Messaging, tabela `push_tokens`, job de alertas, mensagens sem conteúdo clínico, e testes em Android e iPhone reais (o push no iPhone exige a conta Apple Developer paga).
7. **Deploy:** Podman rootless na VPS, Caddy com TLS, backups cifrados com teste de restauro, logs e monitorização.
8. **Fecho:** CI, DPIA, política de privacidade (com Apple/Google), onboarding de permissões de alarme.

## 8. Decisões em Aberto
- **Push para alertas ao cuidador: DECIDIDO, FCM só para notificações** (ver 3.4). Sobra confirmar no momento da implementação que o Firebase Cloud Messaging continua gratuito e sem exigir plano pago, e aceitar o DPA da Google.
- **Custos de publicação (não são do push):** Apple Developer Program (cerca de 99 USD/ano, necessário para push em iPhone real e para publicar) e Google Play (cerca de 25 USD, uma vez). Desenvolver e testar em Android não custa nada.
- **Método de ligação:** código de 6 dígitos (desenhado) vs QR ou ligação por mensagem. O código é o mais simples para quem instala a app com a ajuda de alguém; um QR acelera quando o cuidador está presente. Decidir validade (15 min) e limites de tentativas.
- **Cuidador a "ver como a pessoa vê":** é só pré-visualização local, ou também permite confirmar tomas no modo simples? (Recomendado: só pré-visualização, as confirmações do cuidador passam pelo ecrã de cuidador, com registo de quem fez.)
- **Telemóvel da pessoa sem rede durante dias:** alarmes locais continuam, a sincronização fica em fila; o cuidador vê "última ligação" por dispositivo?
- **Biometria no telemóvel da pessoa:** por defeito desligada (os alarmes nunca são bloqueados e o modo simples não tem dados sensíveis para além das tomas); opcional nas definições.
- **Biblioteca de migrações e ORM:** node-pg-migrate vs Drizzle.
- **Tamanho do PIN local:** 4 dígitos (como desenhado) vs 6, com limite de tentativas.
- **Biometria no ecrã de desbloqueio:** o texto do botão ("Entrar com biometria") é neutro e serve para Face ID, impressão digital ou rosto; o ícone pode adaptar-se ao aparelho.
- **Animações Lottie** nos ecrãs de Entrar e Criar conta (entrada de ~3 s, uma só vez): usar `lottie` no Flutter (pacote `lottie`) com os mesmos ficheiros JSON do design; manter em `assets/` e respeitar "reduzir movimento" do sistema na app real (mostrar o último fotograma).


---
Ver também: [[index]], [[design]], [[deploy]], [[dpia-rascunho]], [[politica-privacidade-rascunho]]

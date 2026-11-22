# Backend

API do Amparo: Node.js 22+ · Express 5 · TypeScript · PostgreSQL 17 (em Podman).

O esquema de dados e os endpoints estão em [`../docs/plano.md`](../docs/plano.md) (secções 5 e 6). Como pôr em produção: [`../docs/deploy.md`](../docs/deploy.md).

## Arrancar (primeira vez)

```bash
cd backend
cp .env.example .env        # e preencha os segredos (ver os comandos no próprio ficheiro)
npm install
podman machine start        # só no Windows/macOS, se a máquina estiver parada
npm run db:up               # PostgreSQL em 127.0.0.1:5432
npm run migrate             # aplica o esquema
npm test                    # testes contra a base de dados real
npm run dev                 # API em http://127.0.0.1:3000
```

O `.env` nunca vai para o Git.

## Scripts

| Comando | O que faz |
|---|---|
| `npm run dev` | API em modo de desenvolvimento (recarrega ao gravar) |
| `npm test` | Testes (Vitest + Supertest) contra a base de dados real |
| `npm run typecheck` | Verificação de tipos |
| `npm run build` / `npm start` | Compila para `dist/` e arranca |
| `npm run migrate` / `migrate:down` | Aplica / desfaz a última migração |
| `npm run db:up` / `db:down` | Liga / desliga a base de dados |

## Estado: o backend do plano está completo

**Autenticação** (`/auth`): `registo` (ou `register`), `login`, `apple`, `google`, `refresh`, `logout`, `me` (GET, PATCH telefone e nome, DELETE para apagar a conta), `me/exportacao`.
Argon2id; emails só como HMAC mais uma cópia cifrada; JWT de acesso de 15 min; refresh de 30 dias com rotação e revogação da família; bloqueio progressivo; Apple e Google validados no servidor (assinatura, `aud`, `exp`, `nonce`), sem Firebase Authentication.

**Perfis e permissões** (`/profiles`, `/perfil-ativo`): papéis `owner`/`caregiver`; uma só verificação de acesso à frente de tudo; perfil alheio responde como inexistente (404); chave de cifra própria por perfil; `GET /profiles/:id/exportacao` (portabilidade).

**Medicação** (sob `/profiles/:id`): `medicamentos`, `receitas` (por intervalo ou horas fixas, gera e refaz as tomas, unidades e dias que restam). Nome, notas e dose cifrados.

**Tomas** (`/tomas`, serve cuidadores com `X-Profile-Id` e o telemóvel da pessoa): `GET` com `since` (delta), `GET /:id` com histórico de 7 dias, `POST /:id/registo|saltar|desfazer` (≤ 1 min), idempotência, hora real, conflitos da fila offline, "atrasada" derivada.

**Telemóvel da pessoa, sem conta**: `POST /profiles/:id/pairing-codes` (6 dígitos, 15 min, uso único), `POST /pairing/redeem`, `GET/DELETE /profiles/:id/devices`, `POST /devices/heartbeat`, `GET /contacto`. O token de dispositivo só alcança o seu perfil.

**Alertas e push** (só Firebase Cloud Messaging): `PUT/DELETE /push-tokens`, `GET/PUT /alert-prefs`. Mensagens só com tipo e ids opacos. Trabalhos: marcar tomas falhadas, "toma não confirmada", "receita a acabar", janela de 90 dias, limpeza; agendador com trinco consultivo.

**Conformidade**: `audit_logs` só de acrescentar, com escritas e leituras de dados de saúde por cuidadores; exportação e apagamento (perfil e conta); registos de pedidos sem dados pessoais; limite de pedidos por IP.

**Deploy**: `Containerfile`, `deploy/compose.prod.yaml` (Podman rootless + Caddy), backups cifrados com gpg e teste de restauro (`deploy/backup.sh`, `deploy/restore-test.sh`), CI no GitHub Actions.

### Variáveis opcionais

| Variável | Para quê |
|---|---|
| `APPLE_CLIENT_ID`, `GOOGLE_CLIENT_IDS` | Ligam o "Entrar com a Apple/Google" (sem elas, `501`) |
| `FCM_SERVICE_ACCOUNT_FILE` | Liga o push (sem ele, o servidor avisa e continua) |
| `HOST`, `TRUST_PROXY` | Atrás do Caddy: `0.0.0.0` e `1` (o `compose.prod.yaml` já os define) |

### Fica para depois de haver app e contas externas

- Recuperação de palavra-passe por email: a cifra do email já está pronta; falta escolher o fornecedor de email e os endpoints (ver `../docs/plano.md`).
- Testar o push e o "Entrar com a Apple/Google" contra os serviços verdadeiros: precisa das contas Firebase, Apple Developer e Google Cloud.
- Rotação das chaves `EMAIL_ENC_KEY` e `PROFILE_MASTER_KEY` (o formato já tem versão; falta o script).

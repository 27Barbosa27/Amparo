# Backend

API do Amparo: Node.js 22+ · Express 5 · TypeScript · PostgreSQL 17 (em Podman).

O esquema de dados e os endpoints previstos estão em [`../docs/plano.md`](../docs/plano.md) (secções 5 e 6).

## Arrancar (primeira vez)

```bash
cd backend
cp .env.example .env        # e escolha uma palavra-passe para POSTGRES_PASSWORD e DATABASE_URL
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
| `npm test` | Testes (Vitest + Supertest) |
| `npm run typecheck` | Verificação de tipos |
| `npm run migrate` / `migrate:down` | Aplica / desfaz a última migração |
| `npm run db:up` / `db:down` | Liga / desliga a base de dados |

## Estado

- `GET /health` e `GET /health/db`.
- Esquema inicial completo (13 tabelas), incluindo o `audit_logs` append-only imposto por trigger.
- Por fazer: geração de tomas, autenticação, perfis e autorização, ligação por código, sincronização e push. Ver o plano de execução em `docs/plano.md`.

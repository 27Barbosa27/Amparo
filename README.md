# Amparo

App de lembretes de medicação para cuidadores e para as pessoas de quem cuidam.

- **Alarmes locais** que tocam à hora certa, mesmo com a app fechada, com "Adiar 10 minutos".
- **Vários perfis:** um cuidador acompanha várias pessoas. A pessoa acompanhada usa um modo simples e liga o telemóvel por código, sem criar conta.
- **Acompanhamento:** o cuidador vê as tomas, marca-as por quem precisa e recebe alertas.
- **Privacidade:** pensada para dados de saúde (RGPD), com consentimento explícito e registo de auditoria.

## Estrutura

| Pasta | Conteúdo |
|---|---|
| `app/` | A app (Flutter) |
| `backend/` | A API (Node.js + Express + TypeScript + PostgreSQL) |
| `docs/` | O plano técnico e o desenho dos ecrãs |

## Tecnologia

Flutter · Node.js + Express + TypeScript · PostgreSQL · Podman.

## Estado

Em desenvolvimento. O plano técnico está em [`docs/plano.md`](docs/plano.md) e o desenho dos ecrãs em [`docs/design.md`](docs/design.md).

## Segurança

Este repositório não deve conter segredos: palavras-passe, ficheiros `.env`, chaves, certificados ou ficheiros `google-services.json` / `GoogleService-Info.plist`. O `.gitignore` bloqueia os mais comuns.

# Amparo: instruções para agentes

## Como correr a app

Quando alguém pedir para **correr, abrir, arrancar ou testar a app**, faz-se **sempre assim e de nenhuma outra maneira**: a app Flutter numa janela do Chrome com tamanho de telemóvel, através de `app/scripts/chrome.ps1`.

**Não usar** `flutter run -d windows`, `flutter run -d chrome`, `flutter run -d web-server` à mão, o emulador Android nem qualquer outra forma, a não ser que o utilizador o peça por escrito.

### Passos (no PowerShell, a partir da raiz do repositório)

1. **Base de dados** (Podman). Só se ainda não estiver a correr (`podman ps` mostra `backend-db-1`):

   ```powershell
   podman machine start        # se a máquina estiver parada
   cd backend
   npm run db:up
   npm run migrate
   ```

2. **API** (noutro processo, em segundo plano). Só se `http://127.0.0.1:3000/health` não responder `{"estado":"ok"}`:

   ```powershell
   cd backend
   npm run dev
   ```

3. **App no Chrome**, em segundo plano (o script fica a correr e faz hot reload ao gravar um `.dart`):

   ```powershell
   cd app
   .\scripts\chrome.ps1
   ```

   A janela abre em `http://127.0.0.1:8099`, com 412×915. A primeira vez demora cerca de 1 a 2 minutos; esperar pela linha `Aberto em http://127.0.0.1:8099`.

### Regras

- **Uma só janela** ligada ao servidor. Antes de relançar, correr `.\scripts\chrome.ps1 -Parar`; com duas páginas abertas o Flutter não reinicia.
- Para ver alterações que o hot reload não apanha (`main.dart`, assets, `pubspec.yaml`), parar e relançar o script.
- O script aceita `-Tela hoje` (ou `simples`, `receitas`, `mais`…) para abrir direto num ecrã e `-Api http://...` para outra API.
- O script lê o ID de cliente Google do primeiro valor de `GOOGLE_CLIENT_IDS` em `backend/.env` e passa-o à app. Se esse valor mudar, **reiniciar a API e a app**: nenhuma das duas o relê sozinha.
- `backend/.env` não vai para o git. Tem de ter `CORS_ORIGINS=http://127.0.0.1:8099`, senão o Chrome bloqueia os pedidos à API. Se não existir, **não inventar segredos em silêncio**: dizer ao utilizador, e só o criar com o consentimento dele.
- Se a palavra-passe do Postgres no `backend/.env` não bater com a do volume (erro `password authentication failed for user "amparo"`), acertar a base de dados à do `.env` com `ALTER USER` dentro do contentor. **Nunca apagar o volume `backend_amparo_pgdata` sem o utilizador o dizer.**
- No fim, dizer ao utilizador em que endereços ficou tudo (app `8099`, API `3000`).

### Parar tudo

```powershell
cd app
.\scripts\chrome.ps1 -Parar
```

A API (`npm run dev`) e a base de dados (`npm run db:down`, em `backend/`) param-se à parte, só se o utilizador o pedir.

## Regras de produto

- **A app não substitui o médico.** Regista e lembra o que o médico decidiu; nunca sugere, calcula nem interpreta nada clínico (doses, interações, valores de sinais).
- **Ecrãs novos:** desenhar primeiro no artefacto do Claude Design (ver `docs/design.md`) e só depois implementar.
- **Sem anúncios nem venda de dados.** Segurança e acessibilidade ficam sempre gratuitas (ver `docs/plano-pago.md`).

Os planos das funcionalidades estão em `docs/` (ver `docs/index.md`).

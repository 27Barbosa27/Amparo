# App Amparo (Flutter)

App para cuidadores e para as pessoas que acompanham. O desenho está em [`../docs/design.md`](../docs/design.md); o backend em [`../backend`](../backend).

## Correr

```bash
# 1. a API (noutro terminal, em backend/)
npm run db:up && npm run migrate
npm run dev

# 2. a app (em app/)
flutter run -d windows                      # ou:  .\scripts\chrome.ps1   (janela de telemóvel no Chrome)
```

A app não traz dados de exemplo: começa-se criando uma conta no ecrã **Criar conta**, depois adiciona-se a primeira pessoa e as receitas, tudo contra a API.

### Opções de desenvolvimento (`--dart-define`)

| Opção | Para quê |
|---|---|
| `API_URL=http://127.0.0.1:3000` | Endereço da API. No emulador Android usa-se `http://10.0.2.2:3000` (já é o valor por omissão lá) |
| `TELA=hoje` / `simples` / `sucesso` / `entrar-erro` / `receitas` / `pessoa-nova` / `receita-nova` | Abre direto num ecrã (para capturas) |
| `DEV_EMAIL`, `DEV_SENHA` | Entram sozinhos quando se usa `TELA` (credenciais de uma conta tua) |

Para a app web (Chrome) falar com a API, o backend tem de autorizar a origem: `CORS_ORIGINS=http://127.0.0.1:8099` no `backend/.env`.

## Testes

```bash
flutter analyze
flutter test                                              # sem servidor (o repositório falso vive em test/apoio)
flutter test --dart-define=API_REAL=http://127.0.0.1:3000 test/integracao_api_test.dart   # contra a API a sério: cada teste cria a sua conta e apaga-a no fim
```

## Telemóvel virtual e Chrome

- `.\scripts\chrome.ps1`: a app numa janela do Chrome com tamanho de telemóvel. Rápido e leve. Serve para o aspeto e os fluxos.
- `.\scripts\emulador.ps1 ligar|desligar|estado`: Android 11 leve (cerca de 3 GB de RAM medidos). Só faz falta para alarmes, notificações e permissões.

## Estado

- Feito: tema do design (claro e escuro), Entrar (com Lottie e Apple/Google), Hoje do cuidador, modo simples, "Toma marcada", Receitas (aviso do que está a acabar, stock e validade), Adicionar pessoa, Adicionar receita (com a geração das tomas em segundo plano, resultado e erro), Mais; ligação à API (login, renovação da sessão, perfis, tomas, marcar/saltar/desfazer, adesão de 7 dias, contacto).
- A sessão fica só em memória. O armazenamento seguro do sistema (Keychain/Keystore) exige o **Modo de Programador do Windows** ligado (Definições → Para programadores) porque os plugins nativos precisam de *symlinks*. O mesmo vale para as notificações e os alarmes.
- Por fazer: Entrar com Apple/Google a sério, criar conta, "Tenho um código", editar e apagar receitas e pessoas, pedir renovação ao médico, alarmes locais, push, sincronização delta e fila offline, bloqueio com biometria/PIN, fonte Plus Jakarta Sans nos assets.
- Os Lottie em `assets/lottie/` vieram de `Downloads`: falta confirmar as licenças.

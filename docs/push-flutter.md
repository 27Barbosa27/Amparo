# Push no Flutter (FCM)

Plano de implementação do lado da app. O desenho e as decisões estão em [[plano]] (secção 3.4); o backend já está feito (`backend/src/push/`). Aqui só se descreve o que falta na app.

## Estado de partida

| Peça | Estado |
|---|---|
| Projeto Firebase `amparo-f95ab` (só Cloud Messaging) | feito |
| `app/android/app/google-services.json` e plugin `com.google.gms.google-services` no Gradle | feito |
| Chave da conta de serviço em `backend/secrets/` e `FCM_SERVICE_ACCOUNT_FILE` no `backend/.env` | feito |
| Backend: `PUT/DELETE /push-tokens`, envio, tokens inválidos, alertas sem repetição | feito |
| Código Flutter (`firebase_messaging`, permissão, token, mensagens) | feito (`app/lib/dados/push.dart`), falta testar num Android real |
| iPhone (`GoogleService-Info.plist`, chave APNs, conta Apple Developer paga) | por fazer, mais tarde |

## O que o backend envia

Só campos opacos em `data` (ver `backend/src/push/enviador.ts`):

```json
{ "tipo": "alerta" | "sync", "perfil": "<uuid>", "subtipo": "toma_nao_confirmada" | "toma_feita" | "receita_a_acabar" }
```

- `alerta` (para cuidadores): leva também uma notificação visível genérica, `Amparo — Tem um aviso novo.` Com a app fechada, quem a mostra é o sistema.
- `sync` (para o telemóvel da pessoa): só dados, sem nada visível. A app vai buscar as mudanças.
- Nunca vem nome de pessoa, de medicamento nem valor clínico. O texto detalhado nasce no telemóvel.

## Passos

### 1. Dependências

Em `app/`:

```powershell
flutter pub add firebase_core firebase_messaging flutter_local_notifications
```

- `firebase_core` + `firebase_messaging`: receber o push e obter o token.
- `flutter_local_notifications`: mostrar a notificação com o texto detalhado, e mostrar o alerta quando a app está aberta (o FCM não desenha nada em primeiro plano).
- Se o Gradle reclamar do `minSdk`, o `firebase_messaging` pede 23 ou mais (`app/android/app/build.gradle.kts`, `minSdk`).
- Android 13+: acrescentar `<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>` ao `app/android/app/src/main/AndroidManifest.xml`.

### 2. Serviço de push (`app/lib/dados/push.dart`)

Uma classe `ServicoPush` isolada, para o resto da app não conhecer o Firebase (igual a `google.dart`). Interface mínima:

```dart
abstract class ServicoPush {
  /// Pede permissão, regista o token no servidor e fica a ouvir. Não faz nada no Chrome.
  Future<void> iniciar();
  /// Ao sair da conta ou desligar o telemóvel: apaga o token no servidor e no Firebase.
  Future<void> parar();
  /// Chamado quando chega um push `sync` ou `alerta` com a app aberta.
  Stream<MensagemPush> get mensagens;
}
```

Duas implementações: `ServicoPushFirebase` (Android/iOS) e `ServicoPushNulo` (web e testes). Escolher com `kIsWeb`.

`ServicoPushFirebase.iniciar()`:
1. `Firebase.initializeApp()` (sem `firebase_options.dart`: no Android lê o `google-services.json`).
2. `FirebaseMessaging.instance.requestPermission()`. No Android 13+ abre o pedido do sistema. Se for recusado, não insistir (ver "Pedidos de permissão" abaixo).
3. `getToken()` e `PUT /push-tokens` com `{ plataforma: 'android' | 'ios', token }`.
4. `onTokenRefresh` → repetir o `PUT` com o token novo.
5. `FirebaseMessaging.onMessage` (app aberta) e `onMessageOpenedApp` (toque na notificação) → emitir em `mensagens`.

### 3. Cliente da API

Em `app/lib/dados/api.dart` já existe `ClienteApi` com `Authorization` e `X-Profile-Id`. Acrescentar em `repositorio_api.dart` (ou numa classe `PushApi` ao lado de `LigacaoApi`):

- `registarPush(plataforma, token)` → `PUT /push-tokens`
- `removerPush(token)` → `DELETE /push-tokens`

O mesmo endpoint serve o cuidador (JWT de utilizador) e a pessoa (token de dispositivo): o backend escolhe o dono pelo principal.

### 4. Quando arrancar e parar

| Momento | Ação |
|---|---|
| Login feito, ou sessão restaurada em `main.dart` | `servicoPush.iniciar()` |
| Telemóvel da pessoa ligado com o código (`ligar_telemovel.dart`) | `servicoPush.iniciar()` |
| Terminar sessão | `servicoPush.parar()` **antes** de limpar a sessão (o `DELETE` precisa do token de acesso) |
| Cuidador desliga um telemóvel | o backend revoga; a app da pessoa, ao receber 401, para |

Ligar isto em `main.dart` e `app.dart`, sem mexer nos ecrãs.

### 5. Mensagens em segundo plano

Em `main.dart`, uma função de topo (obrigatório pelo `firebase_messaging`):

```dart
@pragma('vm:entry-point')
Future<void> _aoReceberEmSegundoPlano(RemoteMessage m) async {
  await Firebase.initializeApp();
  // tipo == 'sync' → marcar "há mudanças por buscar" (ver passo 6)
}
// no main(): FirebaseMessaging.onBackgroundMessage(_aoReceberEmSegundoPlano);
```

Não fazer chamadas de rede pesadas aqui; no segundo plano o Android dá poucos segundos.

### 6. Tratar cada tipo

**`sync` (telemóvel da pessoa)**
- Em primeiro plano: `HojeControlador` recarrega as tomas e reagenda os alarmes locais.
- Em segundo plano: guardar uma marca e recarregar quando a app abre. O alarme local nunca depende disto.

**`alerta` (cuidador)**
- Buscar o detalhe por HTTPS (as tomas do perfil, `GET /tomas` com `X-Profile-Id: <perfil>`) e compor o texto no telemóvel, por exemplo "Rosa não confirmou a toma das 08:00".
- Mostrar com `flutter_local_notifications`. Em primeiro plano é a única notificação; em segundo plano o sistema já mostrou a genérica, por isso o toque abre a app e atualiza o ecrã.
- Toque → abrir o perfil `perfil` no ecrã Hoje do cuidador.
- **Lacuna:** não existe um endpoint "o que aconteceu" por alerta. Para `toma_feita` e `toma_nao_confirmada` serve o `GET /tomas`. Para `receita_a_acabar` serve `GET /receitas` (dias restantes). Se ficar desajeitado, criar `GET /alertas/recentes` no backend como passo à parte.

### 7. Pedidos de permissão

Regra do produto: nada de pedidos repetitivos (ver [[plano]] e a preferência de UX). Pedir **uma vez**, no momento em que faz sentido:

- Cuidador: ao ativar um alerta no ecrã "Alertas ao cuidador" (`alertas_cuidador.dart`), com uma frase a explicar porquê.
- Pessoa: ao ligar o telemóvel.
- Se recusar, mostrar um aviso discreto nesse ecrã com "Abrir definições". Não voltar a pedir sozinho.
- Sem permissão, os alarmes das tomas continuam a tocar: são locais.

## Testar

O Chrome não recebe FCM: nele o `ServicoPushNulo` não faz nada, e a app tem de correr na mesma. Para testar de verdade é preciso um **telemóvel Android** (ou emulador com Google Play):

1. `flutter run` no Android, com `--dart-define=API_URL=http://<IP do PC>:3000` (no emulador, `10.0.2.2`). Um telemóvel físico tem de ver o PC na rede, e o `CORS_ORIGINS` não conta para apps nativas.
2. Iniciar sessão como cuidador, aceitar a permissão, e confirmar que o token aparece na tabela `push_tokens`.
3. Disparar um alerta:
   - "toma feita": marcar uma toma com outro utilizador (o autor não recebe o próprio aviso), com `toma_feita` ativo nas preferências.
   - "toma não confirmada" e "receita a acabar": vêm dos jobs (`backend/src/jobs/trabalhos.ts`); baixar `esperaMin` para 1 e deixar passar o tempo.
4. Verificar com a app aberta, em segundo plano e fechada (retirar dos recentes).
5. Verificar que sem `FCM_SERVICE_ACCOUNT_FILE` o backend avisa "Push desligado" e nada rebenta.

## Testes automáticos

- `ServicoPushNulo` nos testes de widgets existentes, para nada tocar no Firebase.
- Teste unitário da composição do texto do alerta a partir dos dados da API (função pura).
- No backend já existem testes do `corpoMensagem` e do envio; não duplicar.

## Fora de âmbito

- iPhone: depois de haver conta Apple Developer. Acrescenta-se `GoogleService-Info.plist`, a capacidade Push Notifications e Background Modes no Xcode, e a chave APNs `.p8` carregada na Firebase.
- Alarmes locais das tomas e "Adiar 10 minutos": peça à parte ([[plano]], secção 3), nunca dependem do push.
- Texto clínico no push: **proibido**. Se alguma vez aparecer em `data` ou `notification`, é um defeito.

## Ordem sugerida

1. Passos 1 a 4 (token registado no servidor, verificável em `push_tokens`).
2. Passo 6, `sync`, depois `alerta`.
3. Passos 5 e 7.
4. Teste em Android real.

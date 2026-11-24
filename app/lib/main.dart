import 'package:flutter/foundation.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'dados/api.dart';
import 'dados/autenticacao.dart';
import 'dados/google.dart';
import 'dados/ligacao.dart';
import 'dados/repositorio_api.dart';
import 'dados/sessao_segura.dart';

/// Escolhas de desenvolvimento, por `--dart-define`:
///   API_URL=http://127.0.0.1:3000   endereço da API (no emulador Android é http://10.0.2.2:3000)
///   TELA=hoje|simples|sucesso|receitas|pessoa-nova|receita-nova|entrar-erro   abre direto num ecrã
///   DEV_EMAIL / DEV_SENHA           entram sozinhos quando se usa TELA (só desenvolvimento)
/// A app não traz dados de exemplo: tudo vem da API.
const _apiUrl = String.fromEnvironment('API_URL');
const _tela = String.fromEnvironment('TELA');

/// O ID de cliente "Aplicação Web" do Google Cloud (--dart-define=GOOGLE_CLIENT_ID=...). Sem ele, o botão
/// da Google avisa que ainda não está configurado. `GOOGLE_CLIENT_ID_IOS` é o ID de cliente iOS (só no iPhone).
const _googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
const _googleClientIdIos = String.fromEnvironment('GOOGLE_CLIENT_ID_IOS');
const _devEmail = String.fromEnvironment('DEV_EMAIL');
const _devSenha = String.fromEnvironment('DEV_SENHA');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_PT');

  final credenciais = _devEmail.isEmpty
      ? null
      : (email: _devEmail, senha: _devSenha);

  // O emulador Android vê o computador em 10.0.2.2; no resto, 127.0.0.1.
  final porOmissao = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? 'http://10.0.2.2:3000'
      : 'http://127.0.0.1:3000';
  // A sessão fica guardada no armazenamento seguro: reabrir a app não pede o login outra vez.
  final sessao = SessaoSegura();
  await sessao.carregar();
  final api = ClienteApi(
    base: Uri.parse(_apiUrl.isEmpty ? porOmissao : _apiUrl),
    sessao: sessao,
  );
  runApp(
    AmparoApp(
      repositorio: RepositorioApi(api),
      autenticacao: AutenticacaoApi(api),
      // No Chrome, `?tela=...` no endereço faz o mesmo que `--dart-define=TELA=...` (só desenvolvimento).
      // `?claro=1` abre no tema claro (só desenvolvimento, para comparar com o design).
      escuroInicial: !(kIsWeb && Uri.base.queryParameters['claro'] == '1'),
      telaInicial: _tela.isNotEmpty
          ? _tela
          : (kIsWeb ? Uri.base.queryParameters['tela'] ?? '' : ''),
      ligacao: LigacaoApi(api),
      google: EntradaGoogleReal(
        clientId: _googleClientId,
        clientIdIos: _googleClientIdIos,
      ),
      credenciaisDev: credenciais,
    ),
  );
}

import 'package:flutter/foundation.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'dados/api.dart';
import 'dados/autenticacao.dart';
import 'dados/repositorio_api.dart';

/// Escolhas de desenvolvimento, por `--dart-define`:
///   API_URL=http://127.0.0.1:3000   endereço da API (no emulador Android é http://10.0.2.2:3000)
///   TELA=hoje|simples|sucesso|receitas|pessoa-nova|receita-nova|entrar-erro   abre direto num ecrã
///   DEV_EMAIL / DEV_SENHA           entram sozinhos quando se usa TELA (só desenvolvimento)
/// A app não traz dados de exemplo: tudo vem da API.
const _apiUrl = String.fromEnvironment('API_URL');
const _tela = String.fromEnvironment('TELA');
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
  final api = ClienteApi(
    base: Uri.parse(_apiUrl.isEmpty ? porOmissao : _apiUrl),
    sessao: SessaoMemoria(),
  );
  runApp(
    AmparoApp(
      repositorio: RepositorioApi(api),
      autenticacao: AutenticacaoApi(api),
      telaInicial: _tela,
      credenciaisDev: credenciais,
    ),
  );
}

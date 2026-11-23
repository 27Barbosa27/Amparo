import 'package:flutter/foundation.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'dados/api.dart';
import 'dados/autenticacao.dart';
import 'dados/repositorio_api.dart';
import 'dados/repositorio_memoria.dart';

/// Escolhas de desenvolvimento, por `--dart-define`:
///   API_URL=http://127.0.0.1:3000   endereço da API (no emulador Android é http://10.0.2.2:3000)
///   DADOS=falsos                    usa os dados falsos, sem servidor
///   TELA=hoje|simples|sucesso|entrar-erro   abre direto num ecrã
///   DEV_EMAIL / DEV_SENHA           entram sozinhos quando se usa TELA (só desenvolvimento)
const _apiUrl = String.fromEnvironment('API_URL');
const _dados = String.fromEnvironment('DADOS');
const _tela = String.fromEnvironment('TELA');
const _devEmail = String.fromEnvironment('DEV_EMAIL');
const _devSenha = String.fromEnvironment('DEV_SENHA');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_PT');

  final credenciais = _devEmail.isEmpty
      ? null
      : (email: _devEmail, senha: _devSenha);
  if (_dados == 'falsos') {
    runApp(
      AmparoApp(
        repositorio: RepositorioMemoria(agora: DateTime.now()),
        autenticacao: AutenticacaoMemoria(),
        telaInicial: _tela,
        credenciaisDev: credenciais,
      ),
    );
    return;
  }

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

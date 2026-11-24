import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'google_botao_stub.dart'
    if (dart.library.js_interop) 'google_botao_web.dart';

/// O que o Google devolve depois de a pessoa escolher a conta: o ID token (que o servidor valida) e o
/// `nonce` com que foi pedido.
class CredencialGoogle {
  const CredencialGoogle({
    required this.idToken,
    required this.nonce,
    this.nome,
  });
  final String idToken;
  final String nonce;
  final String? nome;
}

/// "Entrar com a Google". Nos telemóveis a app mostra o seu botão e chama [entrar]; no browser o Google só
/// deixa entrar pelo botão dele ([botaoWeb]) e a credencial chega por [eventos].
abstract class EntradaGoogle {
  /// Há um ID de cliente Google configurado.
  bool get configurado;

  /// No browser, o botão do Google; nos telemóveis, nulo.
  Widget? botaoWeb();

  /// No browser: as credenciais que chegam quando a pessoa usa o botão do Google.
  Stream<CredencialGoogle> get eventos;

  /// Nos telemóveis: abre a folha de contas do Google. `erro` é `cancelado`, `google_indisponivel` ou `google_falhou`.
  Future<({CredencialGoogle? credencial, String? erro})> entrar();
}

class EntradaGoogleReal implements EntradaGoogle {
  EntradaGoogleReal({required this.clientId, this.clientIdIos = ''});

  /// O ID de cliente "Aplicação Web" do Google Cloud (é o `aud` do token que o servidor valida).
  final String clientId;

  /// O ID de cliente "iOS" (só no iPhone).
  final String clientIdIos;

  /// Um valor novo a cada arranque: vai dentro do token e o servidor confere-o.
  final String _nonce = List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  Future<void>? _iniciado;
  final _eventos = StreamController<CredencialGoogle>.broadcast();

  @override
  bool get configurado => clientId.isNotEmpty;

  Future<void> _iniciar() => _iniciado ??= () async {
    await GoogleSignIn.instance.initialize(
      clientId: kIsWeb ? clientId : (clientIdIos.isEmpty ? null : clientIdIos),
      serverClientId: kIsWeb ? null : clientId,
      nonce: _nonce,
    );
    GoogleSignIn.instance.authenticationEvents.listen((e) {
      if (e is GoogleSignInAuthenticationEventSignIn) {
        final idToken = e.user.authentication.idToken;
        if (idToken != null) {
          _eventos.add(
            CredencialGoogle(
              idToken: idToken,
              nonce: _nonce,
              nome: e.user.displayName,
            ),
          );
        }
      }
    }, onError: (_) {});
  }();

  @override
  Stream<CredencialGoogle> get eventos {
    if (configurado && kIsWeb) _iniciar();
    return _eventos.stream;
  }

  @override
  Widget? botaoWeb() => configurado && kIsWeb ? botaoGoogleWeb() : null;

  @override
  Future<({CredencialGoogle? credencial, String? erro})> entrar() async {
    if (!configurado) return (credencial: null, erro: 'google_indisponivel');
    try {
      await _iniciar();
      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        return (credencial: null, erro: 'google_indisponivel');
      }
      final conta = await GoogleSignIn.instance.authenticate();
      final idToken = conta.authentication.idToken;
      if (idToken == null) return (credencial: null, erro: 'google_falhou');
      return (
        credencial: CredencialGoogle(
          idToken: idToken,
          nonce: _nonce,
          nome: conta.displayName,
        ),
        erro: null,
      );
    } on GoogleSignInException catch (e) {
      return (
        credencial: null,
        erro: e.code == GoogleSignInExceptionCode.canceled
            ? 'cancelado'
            : 'google_falhou',
      );
    } catch (_) {
      return (credencial: null, erro: 'google_falhou');
    }
  }
}

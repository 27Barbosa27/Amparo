import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// O que a Apple devolve: o ID token (que o servidor valida), o `nonce` em claro com que foi pedido e o nome
/// (a Apple só o dá na primeira autorização).
class CredencialApple {
  const CredencialApple({
    required this.idToken,
    required this.nonce,
    this.nome,
  });
  final String idToken;
  final String nonce;
  final String? nome;
}

/// "Entrar com a Apple". No iPhone usa a folha do sistema; no Android abre a página da Apple e volta pela
/// API (`/auth/apple/callback`). No browser não se oferece. Igual a `google.dart`: o resto da app não conhece
/// o plugin.
abstract class EntradaApple {
  /// Neste aparelho dá para entrar com a Apple (no Android, só com o Services ID e o endereço de retorno).
  bool get configurado;

  /// `erro` é `cancelado`, `apple_indisponivel` ou `apple_falhou`.
  Future<({CredencialApple? credencial, String? erro})> entrar();
}

class EntradaAppleReal implements EntradaApple {
  EntradaAppleReal({this.servicesId = '', this.retorno = ''});

  /// O Services ID da Apple (é o `aud` do token no Android). Vem de `--dart-define=APPLE_SERVICE_ID=...`.
  final String servicesId;

  /// O endereço de retorno registado no Services ID: `https://<api>/auth/apple/callback`.
  final String retorno;

  @override
  bool get configurado {
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => true,
      TargetPlatform.android => servicesId.isNotEmpty && retorno.isNotEmpty,
      _ => false,
    };
  }

  @override
  Future<({CredencialApple? credencial, String? erro})> entrar() async {
    if (!configurado) return (credencial: null, erro: 'apple_indisponivel');
    // Um nonce novo por tentativa: a Apple guarda o SHA-256 no token e o servidor confere-o com o valor em claro.
    final nonce = List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    try {
      final c = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: sha256.convert(utf8.encode(nonce)).toString(),
        webAuthenticationOptions:
            defaultTargetPlatform == TargetPlatform.android
            ? WebAuthenticationOptions(
                clientId: servicesId,
                redirectUri: Uri.parse(retorno),
              )
            : null,
      );
      final idToken = c.identityToken;
      if (idToken == null) return (credencial: null, erro: 'apple_falhou');
      final nome = [
        c.givenName,
        c.familyName,
      ].whereType<String>().join(' ').trim();
      return (
        credencial: CredencialApple(
          idToken: idToken,
          nonce: nonce,
          nome: nome.isEmpty ? null : nome,
        ),
        erro: null,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      return (
        credencial: null,
        erro: e.code == AuthorizationErrorCode.canceled
            ? 'cancelado'
            : 'apple_falhou',
      );
    } on SignInWithAppleNotSupportedException {
      return (credencial: null, erro: 'apple_indisponivel');
    } catch (_) {
      return (credencial: null, erro: 'apple_falhou');
    }
  }
}

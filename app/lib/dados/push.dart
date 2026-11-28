// Push (FCM) do lado da app (docs/push-flutter.md). O Firebase serve só para receber notificações: o resto
// da app não o conhece, tal como em `google.dart`. O servidor só manda ids opacos; o texto nasce aqui.

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'repositorio.dart';

/// O que chega num push. `tipo`: `alerta` (cuidador), `sync` (telemóvel da pessoa) ou `lembrete`.
class MensagemPush {
  const MensagemPush({
    required this.tipo,
    required this.perfil,
    this.subtipo,
    this.toma,
    this.tocada = false,
  });

  final String tipo;
  final String perfil;

  /// Só nos alertas: `toma_nao_confirmada`, `toma_feita` ou `receita_a_acabar`.
  final String? subtipo;

  /// Só nos lembretes: a toma a lembrar.
  final String? toma;

  /// Verdadeiro se veio de um toque na notificação (a app estava em segundo plano ou fechada).
  final bool tocada;

  static MensagemPush? deDados(Map<String, dynamic> d, {bool tocada = false}) {
    final tipo = d['tipo'];
    final perfil = d['perfil'];
    if (tipo is! String || perfil is! String) return null;
    return MensagemPush(
      tipo: tipo,
      perfil: perfil,
      subtipo: d['subtipo'] as String?,
      toma: d['toma'] as String?,
      tocada: tocada,
    );
  }
}

/// O texto do aviso ao cuidador, composto no telemóvel (o push nunca traz nomes nem nada clínico).
String textoDoAlerta(String? subtipo, String nome) => switch (subtipo) {
  'toma_nao_confirmada' => '$nome ainda não confirmou uma toma.',
  'toma_feita' => 'Foi marcada uma toma de $nome.',
  'receita_a_acabar' => 'Uma receita de $nome está a acabar.',
  _ => 'Há um aviso novo sobre $nome.',
};

abstract class ServicoPush {
  /// Regista o token deste telemóvel no servidor (pela sessão de [repositorio]) e fica a ouvir. Não pede
  /// permissão: isso faz-se uma vez, quando faz sentido ([pedirPermissao]). Não faz nada no Chrome.
  Future<void> iniciar(Repositorio repositorio);

  /// Ao sair da conta: apaga o token no servidor (antes de limpar a sessão) e no Firebase.
  Future<void> parar(Repositorio repositorio);

  /// Pede a permissão de notificações (no Android 13+ abre o pedido do sistema). Verdadeiro se ficou dada.
  Future<bool> pedirPermissao();

  /// As mensagens que chegam com a app aberta e os toques nas notificações do sistema.
  Stream<MensagemPush> get mensagens;

  /// Se foi um toque numa notificação de push que abriu a app.
  Future<MensagemPush?> mensagemDoArranque();
}

class ServicoPushNulo implements ServicoPush {
  const ServicoPushNulo();
  @override
  Future<void> iniciar(Repositorio repositorio) async {}
  @override
  Future<void> parar(Repositorio repositorio) async {}
  @override
  Future<bool> pedirPermissao() async => false;
  @override
  Stream<MensagemPush> get mensagens => const Stream.empty();
  @override
  Future<MensagemPush?> mensagemDoArranque() async => null;
}

/// Em segundo plano o Android dá poucos segundos: não se faz nada aqui. Os alertas visíveis já trazem a
/// notificação genérica (o sistema mostra-a); o `sync` fica para quando a app abrir, e o alarme local nunca
/// depende disto.
@pragma('vm:entry-point')
Future<void> aoReceberPushEmSegundoPlano(RemoteMessage m) async {}

/// Usa o token FCM (`getToken`), que é o que o backend envia em `message.token` (FCM HTTP v1). O
/// firebase_messaging 17 marca-o como obsoleto a favor de `register()`/`onRegistered`, que dão o ID de
/// instalação (FID); mudar para aí só depois de confirmar que o envio do backend aceita FIDs.
class ServicoPushFirebase implements ServicoPush {
  final _mensagens = StreamController<MensagemPush>.broadcast();
  Future<bool>? _pronto;
  String? _token;
  StreamSubscription<String>? _renovacoes;

  /// Sem `google-services.json` (ou no iPhone, sem o `GoogleService-Info.plist`) o Firebase não arranca:
  /// fica tudo desligado e a app continua a funcionar.
  Future<bool> _preparar() => _pronto ??= () async {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(aoReceberPushEmSegundoPlano);
      FirebaseMessaging.onMessage.listen((m) {
        final msg = MensagemPush.deDados(m.data);
        if (msg != null) _mensagens.add(msg);
      });
      FirebaseMessaging.onMessageOpenedApp.listen((m) {
        final msg = MensagemPush.deDados(m.data, tocada: true);
        if (msg != null) _mensagens.add(msg);
      });
      return true;
    } catch (_) {
      return false;
    }
  }();

  String get _plataforma =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  @override
  Future<void> iniciar(Repositorio repositorio) async {
    if (!await _preparar()) return;
    try {
      // ignore: deprecated_member_use
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      _token = token;
      await repositorio.registarPush(_plataforma, token);
      await _renovacoes?.cancel();
      // ignore: deprecated_member_use
      _renovacoes = FirebaseMessaging.instance.onTokenRefresh.listen((novo) {
        _token = novo;
        repositorio.registarPush(_plataforma, novo).catchError((_) {});
      });
    } catch (_) {
      // sem rede ou sem Google Play: tenta outra vez no próximo arranque
    }
  }

  @override
  Future<void> parar(Repositorio repositorio) async {
    await _renovacoes?.cancel();
    _renovacoes = null;
    final token = _token;
    _token = null;
    if (token == null || !await _preparar()) return;
    try {
      await repositorio.removerPush(token);
    } catch (_) {
      // sem rede: o servidor revoga o token sozinho quando o FCM o rejeitar
    }
    try {
      // ignore: deprecated_member_use
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  @override
  Future<bool> pedirPermissao() async {
    if (!await _preparar()) return false;
    try {
      final s = await FirebaseMessaging.instance.requestPermission();
      return s.authorizationStatus == AuthorizationStatus.authorized ||
          s.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<MensagemPush> get mensagens => _mensagens.stream;

  @override
  Future<MensagemPush?> mensagemDoArranque() async {
    if (!await _preparar()) return null;
    try {
      final m = await FirebaseMessaging.instance.getInitialMessage();
      return m == null ? null : MensagemPush.deDados(m.data, tocada: true);
    } catch (_) {
      return null;
    }
  }
}

/// No Chrome não há FCM: a `ServicoPushNulo` não faz nada (docs/push-flutter.md, "Testar").
ServicoPush criarServicoPush() =>
    !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)
    ? ServicoPushFirebase()
    : const ServicoPushNulo();

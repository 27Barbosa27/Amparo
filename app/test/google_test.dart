import 'dart:async';

import 'package:amparo/app.dart';
import 'package:amparo/dados/google.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'apoio/autenticacao_memoria.dart';
import 'apoio/repositorio_memoria.dart';

final agora = DateTime(2026, 11, 21, 13, 0);

/// A Google, falsa: devolve o que se lhe mandar.
class GoogleMemoria implements EntradaGoogle {
  GoogleMemoria({this.configurado = true});
  @override
  final bool configurado;
  ({CredencialGoogle? credencial, String? erro}) resposta = (
    credencial: const CredencialGoogle(
      idToken: 'token-da-ana',
      nonce: 'nonce-12345678',
      nome: 'Ana Google',
    ),
    erro: null,
  );
  int pedidos = 0;
  final controlador = StreamController<CredencialGoogle>.broadcast();

  @override
  Widget? botaoWeb() => null;

  @override
  Stream<CredencialGoogle> get eventos => controlador.stream;

  @override
  Future<({CredencialGoogle? credencial, String? erro})> entrar() async {
    pedidos++;
    return resposta;
  }
}

Future<({AutenticacaoMemoria auth, GoogleMemoria google})> abrir(
  WidgetTester tester, {
  GoogleMemoria? google,
}) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final auth = AutenticacaoMemoria();
  final g = google ?? GoogleMemoria();
  await tester.pumpWidget(
    AmparoApp(
      repositorio: RepositorioMemoria(agora: agora),
      autenticacao: auth,
      relogio: () => agora,
      google: g,
    ),
  );
  await tester.pumpAndSettle();
  return (auth: auth, google: g);
}

void main() {
  setUpAll(() => initializeDateFormatting('pt_PT'));

  group('Entrar com a Google', () {
    testWidgets('uma conta que já existe entra sem pedir nada', (tester) async {
      final a = await abrir(tester);
      a.auth.contasGoogleExistentes.add('token-da-ana');
      await tester.tap(find.bySemanticsLabel('Entrar com Google'));
      await tester.pumpAndSettle();
      expect(a.google.pedidos, 1);
      expect(a.auth.entradasGoogle.single.aceitaTermos, isFalse);
      expect(find.text('Olá, Ana Google'), findsOneWidget);
    });

    testWidgets('uma conta nova pede o consentimento antes de criar', (
      tester,
    ) async {
      final a = await abrir(tester);
      await tester.tap(find.bySemanticsLabel('Entrar com Google'));
      await tester.pumpAndSettle();
      expect(find.text('Criar conta com a Google'), findsOneWidget);
      // ainda não entrou
      expect(find.text('Olá, Ana Google'), findsNothing);

      await tester.tap(find.text('Aceitar e criar conta'));
      await tester.pumpAndSettle();
      expect(a.auth.entradasGoogle.map((e) => e.aceitaTermos), [false, true]);
      expect(find.text('Olá, Ana Google'), findsOneWidget);
    });

    testWidgets('recusar o consentimento não cria a conta', (tester) async {
      final a = await abrir(tester);
      await tester.tap(find.bySemanticsLabel('Entrar com Google'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(a.auth.entradasGoogle, hasLength(1));
      expect(find.text('Olá, Ana Google'), findsNothing);
      expect(find.text('Entrar'), findsWidgets);
    });

    testWidgets('cancelar a folha da Google não mostra erro', (tester) async {
      final a = await abrir(tester);
      a.google.resposta = (credencial: null, erro: 'cancelado');
      await tester.tap(find.bySemanticsLabel('Entrar com Google'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(a.auth.entradasGoogle, isEmpty);
    });

    testWidgets('um token recusado pelo servidor avisa', (tester) async {
      final a = await abrir(tester);
      a.auth.erroGoogle = 'provedor_invalido';
      await tester.tap(find.bySemanticsLabel('Entrar com Google'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Não foi possível entrar com a Google'),
        findsOneWidget,
      );
    });

    testWidgets('servidor sem Google configurado avisa', (tester) async {
      final a = await abrir(tester);
      a.auth.erroGoogle = 'provedor_nao_configurado';
      await tester.tap(find.bySemanticsLabel('Entrar com Google'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('ainda não está ligada no servidor'),
        findsOneWidget,
      );
    });

    testWidgets('sem ID de cliente a app avisa e nem chama a Google', (
      tester,
    ) async {
      final a = await abrir(tester, google: GoogleMemoria(configurado: false));
      await tester.tap(find.bySemanticsLabel('Entrar com Google'));
      await tester.pumpAndSettle();
      expect(a.google.pedidos, 0);
      expect(find.textContaining('falta o ID de cliente'), findsOneWidget);
    });

    testWidgets('no browser a credencial chega pelo botão do Google', (
      tester,
    ) async {
      final a = await abrir(tester);
      a.auth.contasGoogleExistentes.add('token-web');
      a.google.controlador.add(
        const CredencialGoogle(
          idToken: 'token-web',
          nonce: 'nonce-12345678',
          nome: 'Ana Web',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Olá, Ana Web'), findsOneWidget);
    });
  });
}

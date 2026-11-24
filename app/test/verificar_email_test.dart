import 'package:amparo/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'apoio/autenticacao_memoria.dart';
import 'apoio/repositorio_memoria.dart';

final agora = DateTime(2026, 11, 21, 13, 0);

Future<AutenticacaoMemoria> abrir(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final auth = AutenticacaoMemoria()..exigirVerificacao = true;
  await tester.pumpWidget(
    AmparoApp(
      repositorio: RepositorioMemoria(agora: agora, vazio: true),
      autenticacao: auth,
      relogio: () => agora,
    ),
  );
  await tester.pumpAndSettle();
  return auth;
}

Future<void> criarConta(WidgetTester tester) async {
  await tester.tap(find.text('Criar conta'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).at(0), 'Ana');
  await tester.enterText(find.byType(TextField).at(1), 'ana@exemplo.pt');
  await tester.enterText(find.byType(TextField).at(2), 'uma-senha-segura-123');
  await tester.tap(find.byKey(const ValueKey('caixa-termos')));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(InkWell, 'Criar conta'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('pt_PT'));

  group('Criar conta pede o código do email', () {
    testWidgets('depois de criar, pede o código e só então abre a conta', (
      tester,
    ) async {
      final auth = await abrir(tester);
      await criarConta(tester);

      expect(find.text('Confirme o seu email'), findsOneWidget);
      expect(find.textContaining('ana@exemplo.pt'), findsWidgets);
      // ainda não há sessão: não chegou ao "Conta criada"
      expect(find.text('Conta criada'), findsNothing);
      expect(auth.nome, isNull);

      await tester.enterText(find.byType(TextField), '482 915');
      await tester.pumpAndSettle();
      expect(auth.tentativasDeVerificacao, ['482915']);
      expect(find.text('Confirme o seu email'), findsNothing);
      expect(auth.nome, 'Ana');
    });

    testWidgets('um código errado explica e não abre a conta', (tester) async {
      final auth = await abrir(tester);
      await criarConta(tester);
      await tester.enterText(find.byType(TextField), '111111');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Código errado, expirado ou já usado'),
        findsOneWidget,
      );
      expect(find.text('Confirme o seu email'), findsOneWidget);
      expect(auth.nome, isNull);
    });

    testWidgets('o botão fica desativado até haver 6 números', (tester) async {
      await abrir(tester);
      await criarConta(tester);
      await tester.enterText(find.byType(TextField), '123');
      await tester.pump();
      await tester.tap(find.text('Confirmar email'));
      await tester.pump();
      expect(find.text('Confirme o seu email'), findsOneWidget);
    });

    testWidgets('"Reenviar código" espera 30 s e depois pede outro', (
      tester,
    ) async {
      final auth = await abrir(tester);
      await criarConta(tester);
      expect(find.textContaining('Reenviar código ('), findsOneWidget);
      await tester.tap(find.textContaining('Reenviar código ('));
      await tester.pump();
      expect(auth.reenvios, isEmpty);

      await tester.pump(const Duration(seconds: 31));
      await tester.tap(find.text('Reenviar código'));
      await tester.pump();
      await tester.pump();
      expect(auth.reenvios, ['ana@exemplo.pt']);
      expect(find.text('Enviámos um código novo.'), findsOneWidget);
    });
  });

  testWidgets('entrar com uma conta por confirmar leva ao código', (
    tester,
  ) async {
    final auth = await abrir(tester);
    auth.emailsPorVerificar.add('ana@exemplo.pt');
    await tester.enterText(find.byType(TextField).at(0), 'ana@exemplo.pt');
    await tester.enterText(
      find.byType(TextField).at(1),
      'uma-senha-segura-123',
    );
    await tester.tap(find.widgetWithText(InkWell, 'Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('Confirme o seu email'), findsOneWidget);
    // sem mensagem de erro no ecrã de entrar
    expect(find.textContaining('Não foi possível entrar'), findsNothing);

    await tester.enterText(find.byType(TextField), auth.codigoDeVerificacao);
    await tester.pumpAndSettle();
    expect(find.text('Confirme o seu email'), findsNothing);
    expect(auth.nome, isNotNull);
  });
}

import 'package:amparo/app.dart';
import 'package:amparo/ui/ecras/recuperar_senha.dart';
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
  final auth = AutenticacaoMemoria();
  await tester.pumpWidget(
    AmparoApp(
      repositorio: RepositorioMemoria(agora: agora),
      autenticacao: auth,
      relogio: () => agora,
    ),
  );
  await tester.pumpAndSettle();
  return auth;
}

void main() {
  setUpAll(() => initializeDateFormatting('pt_PT'));

  group('validarNovaSenha', () {
    test('exige 8 caracteres e que as duas sejam iguais', () {
      expect(validarNovaSenha('curta', 'curta').senha, isNotNull);
      expect(
        validarNovaSenha('uma-senha-longa', 'outra-diferente').repetir,
        isNotNull,
      );
      final ok = validarNovaSenha('uma-senha-longa', 'uma-senha-longa');
      expect(ok.senha, isNull);
      expect(ok.repetir, isNull);
    });
  });

  group('Esqueci-me da palavra-passe', () {
    testWidgets('pede o email, valida e mostra a resposta neutra', (
      tester,
    ) async {
      final auth = await abrir(tester);
      await tester.tap(find.text('Esqueci-me da palavra-passe'));
      await tester.pumpAndSettle();
      expect(find.text('Recuperar palavra-passe'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'isto-nao-e-email');
      await tester.tap(find.text('Enviar código'));
      await tester.pumpAndSettle();
      expect(find.textContaining('email válido'), findsOneWidget);
      expect(auth.pedidosDeRecuperacao, isEmpty);

      await tester.enterText(find.byType(TextField), 'ana@exemplo.pt');
      await tester.tap(find.text('Enviar código'));
      await tester.pumpAndSettle();
      expect(auth.pedidosDeRecuperacao, ['ana@exemplo.pt']);
      // enviado: passa logo ao ecrã onde se escreve o código; não há botão "Já tenho o código"
      expect(find.text('Código do email'), findsOneWidget);
      expect(find.text('Já tenho o código'), findsNothing);
    });

    testWidgets('com o código certo a palavra-passe muda e pede para entrar', (
      tester,
    ) async {
      final auth = await abrir(tester);
      await tester.tap(find.text('Esqueci-me da palavra-passe'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ana@exemplo.pt');
      await tester.tap(find.text('Enviar código'));
      await tester.pumpAndSettle();

      final campos = find.byType(TextField);
      await tester.enterText(campos.at(0), auth.tokenValido);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Código confirmado'), findsOneWidget);
      await tester.enterText(campos.at(1), 'nova-senha-segura');
      await tester.enterText(campos.at(2), 'nova-senha-segura');
      await tester.tap(find.text('Guardar palavra-passe'));
      await tester.pumpAndSettle();

      expect(auth.senhaReposta, 'nova-senha-segura');
      expect(find.text('Palavra-passe alterada'), findsOneWidget);
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();
      expect(find.text('Palavra-passe alterada'), findsNothing);
      expect(find.text('Esqueci-me da palavra-passe'), findsOneWidget);
    });

    testWidgets(
      'as palavras-passe ficam bloqueadas até o código ser confirmado',
      (tester) async {
        final auth = await abrir(tester);
        await tester.tap(find.text('Esqueci-me da palavra-passe'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'ana@exemplo.pt');
        await tester.tap(find.text('Enviar código'));
        await tester.pumpAndSettle();

        bool ativo(int i) =>
            tester.widget<TextField>(find.byType(TextField).at(i)).enabled ??
            true;
        // sem código: as duas palavras-passe estão desativadas e o botão não faz nada
        expect(ativo(1), isFalse);
        expect(ativo(2), isFalse);
        await tester.tap(find.text('Guardar palavra-passe'));
        await tester.pumpAndSettle();
        expect(auth.senhaReposta, isNull);

        // um código errado (6 números) é recusado e continua tudo bloqueado
        await tester.enterText(find.byType(TextField).at(0), '111111');
        await tester.pumpAndSettle();
        expect(auth.verificacoes, ['111111']);
        expect(
          find.textContaining('Código errado, expirado ou já usado'),
          findsOneWidget,
        );
        expect(ativo(1), isFalse);
        expect(ativo(2), isFalse);

        // o código certo desbloqueia
        await tester.enterText(find.byType(TextField).at(0), auth.tokenValido);
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('Código confirmado'), findsOneWidget);
        expect(ativo(1), isTrue);
        expect(ativo(2), isTrue);

        // mexer no código volta a bloquear
        await tester.enterText(find.byType(TextField).at(0), '48291');
        await tester.pumpAndSettle();
        expect(ativo(1), isFalse);
        expect(find.bySemanticsLabel('Código confirmado'), findsNothing);
      },
    );

    testWidgets('as palavras-passe diferentes não avançam', (tester) async {
      final auth = await abrir(tester);
      await tester.tap(find.text('Esqueci-me da palavra-passe'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ana@exemplo.pt');
      await tester.tap(find.text('Enviar código'));
      await tester.pumpAndSettle();

      final campos = find.byType(TextField);
      await tester.enterText(campos.at(0), auth.tokenValido);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Código confirmado'), findsOneWidget);
      await tester.enterText(campos.at(1), 'nova-senha-segura');
      await tester.enterText(campos.at(2), 'outra-senha-diferente');
      await tester.tap(find.text('Guardar palavra-passe'));
      await tester.pumpAndSettle();
      expect(find.text('As palavras-passe não são iguais.'), findsOneWidget);
      expect(auth.senhaReposta, isNull);
    });
  });

  testWidgets('"Reenviar código" espera 30 s e depois manda um código novo', (
    tester,
  ) async {
    final auth = await abrir(tester);
    await tester.tap(find.text('Esqueci-me da palavra-passe'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ana@exemplo.pt');
    await tester.tap(find.text('Enviar código'));
    await tester.pump();
    await tester.pump();
    expect(auth.pedidosDeRecuperacao, hasLength(1));

    // acabou de se enviar: o botão está à espera e não faz nada
    expect(find.textContaining('Reenviar código ('), findsOneWidget);
    await tester.tap(find.textContaining('Reenviar código ('));
    await tester.pump();
    expect(auth.pedidosDeRecuperacao, hasLength(1));

    await tester.pump(const Duration(seconds: 31));
    expect(find.text('Reenviar código'), findsOneWidget);
    await tester.tap(find.text('Reenviar código'));
    await tester.pump();
    await tester.pump();
    expect(auth.pedidosDeRecuperacao, ['ana@exemplo.pt', 'ana@exemplo.pt']);
    expect(find.textContaining('Enviámos um código novo'), findsOneWidget);
    // e volta a esperar antes de se poder pedir outro
    expect(find.textContaining('Reenviar código ('), findsOneWidget);
  });
}

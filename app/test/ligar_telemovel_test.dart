import 'package:amparo/app.dart';
import 'package:amparo/ui/ecras/ligar_telemovel.dart';
import 'package:amparo/dominio/modelos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'apoio/autenticacao_memoria.dart';
import 'apoio/ligacao_memoria.dart';
import 'apoio/repositorio_memoria.dart';

final agora = DateTime(2026, 11, 21, 13, 0);

Future<({RepositorioMemoria repo, LigacaoMemoria ligacao})> abrir(
  WidgetTester tester,
) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final repo = RepositorioMemoria(agora: agora);
  final ligacao = LigacaoMemoria(agora: agora);
  await tester.pumpWidget(
    AmparoApp(
      repositorio: repo,
      autenticacao: AutenticacaoMemoria(),
      relogio: () => agora,
      ligacao: ligacao,
    ),
  );
  await tester.pumpAndSettle();
  return (repo: repo, ligacao: ligacao);
}

Future<void> entrarComoCuidador(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).at(0), 'ana@exemplo.pt');
  await tester.enterText(find.byType(TextField).at(1), 'uma-senha-segura-123');
  await tester.tap(find.widgetWithText(InkWell, 'Entrar'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('pt_PT'));

  group('Tenho um código (telemóvel da pessoa)', () {
    testWidgets('um código certo liga e abre o modo simples', (tester) async {
      await abrir(tester);
      await tester.tap(find.textContaining('Tenho um código'));
      await tester.pumpAndSettle();
      expect(find.text('Tenho um código'), findsWidgets);
      await tester.enterText(find.byType(TextField), '482 915');
      await tester.tap(find.text('Ligar este telemóvel'));
      await tester.pumpAndSettle();
      expect(find.text('Este telemóvel está ligado'), findsOneWidget);
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      // o modo simples da Maria (sem barra de navegação do cuidador)
      expect(find.byKey(const ValueKey('nav-receitas')), findsNothing);
      expect(find.textContaining('Maria'), findsWidgets);
    });

    testWidgets('um código errado explica o que fazer', (tester) async {
      final a = await abrir(tester);
      await tester.tap(find.textContaining('Tenho um código'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '111111');
      await tester.tap(find.text('Ligar este telemóvel'));
      await tester.pumpAndSettle();
      expect(a.ligacao.tentativas, 1);
      expect(
        find.textContaining('Código errado, expirado ou já usado'),
        findsOneWidget,
      );
    });

    testWidgets('menos de 6 números nem chega a ir ao servidor', (
      tester,
    ) async {
      final a = await abrir(tester);
      await tester.tap(find.textContaining('Tenho um código'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '123');
      await tester.tap(find.text('Ligar este telemóvel'));
      await tester.pumpAndSettle();
      expect(find.text('O código tem 6 números.'), findsOneWidget);
      expect(a.ligacao.tentativas, 0);
    });
  });

  group('Ligar o telemóvel (cuidador)', () {
    testWidgets('mostra o código e passa a "ligado" quando a pessoa o usa', (
      tester,
    ) async {
      final a = await abrir(tester);
      await entrarComoCuidador(tester);
      await tester.tap(find.byKey(const ValueKey('nav-configurações')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Telemóveis ligados'));
      await tester.pump();
      await tester.pump();
      expect(find.text('482 915'), findsOneWidget);
      expect(find.textContaining('À espera de Maria'), findsOneWidget);

      a.repo.estadoDoCodigo = EstadoCodigo.ligado;
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('O telemóvel de Maria está ligado'), findsOneWidget);
      await tester.tap(find.text('Concluir'));
      await tester.pumpAndSettle();
      expect(find.text('Telemóveis ligados'), findsOneWidget);
    });

    testWidgets('um código expirado oferece gerar outro', (tester) async {
      final a = await abrir(tester);
      await entrarComoCuidador(tester);
      await tester.tap(find.byKey(const ValueKey('nav-configurações')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Telemóveis ligados'));
      await tester.pump();
      await tester.pump();

      a.repo.estadoDoCodigo = EstadoCodigo.expirado;
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(find.text('O código expirou'), findsOneWidget);
      await tester.tap(find.text('Gerar outro código').last);
      await tester.pump();
      await tester.pump();
      expect(a.repo.codigosCriados, 2);
      expect(find.text('482 915'), findsOneWidget);
    });
  });

  testWidgets('o ecrã aceita só números e mostra o código em dois grupos', (
    tester,
  ) async {
    await abrir(tester);
    await tester.tap(find.textContaining('Tenho um código'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ab12cd');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '12',
    );
    expect(find.byType(CodigoEcra), findsOneWidget);
  });
}

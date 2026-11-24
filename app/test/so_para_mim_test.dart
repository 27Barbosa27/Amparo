import 'package:amparo/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'apoio/autenticacao_memoria.dart';
import 'apoio/repositorio_memoria.dart';

final agora = DateTime(2026, 11, 21, 13, 0);

void main() {
  setUpAll(() => initializeDateFormatting('pt_PT'));

  testWidgets('uma conta nova pode usar a app só para si, sem formulários', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(
      AmparoApp(
        repositorio: RepositorioMemoria(agora: agora, vazio: true),
        autenticacao: AutenticacaoMemoria(),
        relogio: () => agora,
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'ana@exemplo.pt');
    await tester.enterText(
      find.byType(TextField).at(1),
      'uma-senha-segura-123',
    );
    await tester.tap(find.widgetWithText(InkWell, 'Entrar'));
    await tester.pumpAndSettle();

    expect(find.text('Usar só para mim'), findsOneWidget);
    expect(find.text('Acompanhar outra pessoa'), findsOneWidget);
    await tester.tap(find.text('Usar só para mim'));
    await tester.pumpAndSettle();

    // já está na página principal, com a sua própria medicação (sem Ligar/Lembrar)
    expect(find.text('Olá, Ana'), findsOneWidget);
    expect(find.text('A minha medicação'), findsOneWidget);
    expect(find.text('Ana'), findsWidgets);
  });

  testWidgets('ao marcar uma toma, nada fala de outra pessoa a ver', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final repo = RepositorioMemoria(agora: agora);
    // o perfil "maria" é o do próprio cuidador: a conta chama-se Maria
    await tester.pumpWidget(
      AmparoApp(
        repositorio: repo,
        autenticacao: AutenticacaoMemoria(nomeFixo: 'Maria'),
        relogio: () => agora,
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'maria@exemplo.pt');
    await tester.enterText(
      find.byType(TextField).at(1),
      'uma-senha-segura-123',
    );
    await tester.tap(find.widgetWithText(InkWell, 'Entrar'));
    await tester.pumpAndSettle();

    expect(find.text('Confirmar que tomei'), findsWidgets);
    expect(find.textContaining('Maria tomou'), findsNothing);
    await tester.tap(find.text('Confirmar que tomei').first);
    await tester.pumpAndSettle();

    expect(find.text('Toma marcada'), findsOneWidget);
    expect(find.textContaining('marcado por si'), findsNothing);
    expect(find.textContaining('vê esta marcação'), findsNothing);
    expect(find.textContaining('No ecrã dela'), findsNothing);

    await tester.tap(find.text('Voltar à página principal'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Marcada por'), findsNothing);
  });
}

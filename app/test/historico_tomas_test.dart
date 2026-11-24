import 'package:amparo/app.dart';
import 'package:amparo/dominio/modelos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'apoio/autenticacao_memoria.dart';
import 'apoio/repositorio_memoria.dart';

final agora = DateTime(2026, 11, 21, 13, 0); // sábado

Toma toma(
  String id,
  DateTime quando,
  EstadoToma estado, {
  String med = 'Lisinopril',
}) => Toma(
  id: id,
  medicamento: med,
  dose: '10 mg',
  agendada: quando,
  estado: estado,
  tomadaEm: estado == EstadoToma.tomada ? quando : null,
);

void main() {
  setUpAll(() => initializeDateFormatting('pt_PT'));

  group('ResumoHistorico', () {
    test('a adesão só conta o que já tinha de estar feito', () {
      final tomas = [
        toma('1', DateTime(2026, 11, 20, 8), EstadoToma.tomada),
        toma('2', DateTime(2026, 11, 20, 20), EstadoToma.saltada),
        toma('3', DateTime(2026, 11, 20, 12), EstadoToma.falhada),
        toma('4', DateTime(2026, 11, 21, 8), EstadoToma.tomada),
        toma(
          '5',
          DateTime(2026, 11, 21, 9),
          EstadoToma.pendente,
        ), // por confirmar
        toma('6', DateTime(2026, 11, 21, 21), EstadoToma.pendente), // por tomar
      ];
      final r = ResumoHistorico.de(tomas, agora);
      expect(
        (r.tomadas, r.saltadas, r.esquecidas, r.porConfirmar, r.porTomar),
        (2, 1, 1, 1, 1),
      );
      expect(r.adesao, 50); // 2 de 4: o por confirmar e o por tomar não entram
    });

    test('uma toma pendente de um dia que já acabou é esquecida', () {
      final ontem = toma('1', DateTime(2026, 11, 20, 8), EstadoToma.pendente);
      expect(ontem.resultado(agora), ResultadoToma.esquecida);
    });

    test('sem nada a avaliar não há percentagem (nunca se inventa)', () {
      final r = ResumoHistorico.de([
        toma('1', DateTime(2026, 11, 21, 21), EstadoToma.pendente),
      ], agora);
      expect(r.adesao, isNull);
      expect(ResumoHistorico.de(const [], agora).adesao, isNull);
    });
  });

  testWidgets('Configurações → Histórico de tomas mostra a adesão e os dias', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final repo = RepositorioMemoria(agora: agora);
    repo.historicoExtra['maria'] = [
      toma('a', DateTime(2026, 11, 20, 8), EstadoToma.tomada, med: 'Ramipril'),
      toma(
        'b',
        DateTime(2026, 11, 20, 20),
        EstadoToma.saltada,
        med: 'Ramipril',
      ),
      toma(
        'c',
        DateTime(2026, 11, 20, 12),
        EstadoToma.falhada,
        med: 'Ramipril',
      ),
      toma('d', DateTime(2026, 11, 10, 8), EstadoToma.tomada, med: 'Antigo'),
    ];
    await tester.pumpWidget(
      AmparoApp(
        repositorio: repo,
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
    await tester.tap(find.byKey(const ValueKey('nav-configurações')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Histórico de tomas'));
    await tester.pumpAndSettle();

    // 7 dias: a de dia 10 fica de fora. Hoje: 1 tomada (08:00 da Metformina e Vitamina D); ontem: 1, 1, 1.
    expect(find.text('Histórico de tomas'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('de adesão nos últimos 7 dias'), findsOneWidget);
    expect(find.text('Hoje'), findsOneWidget);
    expect(find.text('Ontem'), findsOneWidget);
    expect(find.text('Não foi tomada'), findsOneWidget);
    expect(find.text('Saltada'), findsOneWidget);
    expect(find.text('Por confirmar'), findsWidgets);
    expect(find.text('Antigo'), findsNothing);

    // 30 dias: já aparece a de dia 10
    await tester.tap(find.text('Últimos 30 dias'));
    await tester.pumpAndSettle();
    expect(find.text('Antigo'), findsOneWidget);
    expect(find.text('de adesão nos últimos 30 dias'), findsOneWidget);
    expect(find.text('Terça-feira, 10 de novembro'), findsOneWidget);
  });
}

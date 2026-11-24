import 'package:amparo/app.dart';
import 'package:amparo/dominio/modelos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'apoio/autenticacao_memoria.dart';
import 'apoio/repositorio_memoria.dart';

final agora = DateTime(2026, 11, 21, 13, 0);

/// Uma conta que acabou de ser criada: nenhum dia tem tomas registadas.
class SemHistorico extends RepositorioMemoria {
  SemHistorico() : super(agora: agora);

  @override
  Future<List<DiaAdesao>> ultimos7Dias(String perfilId, DateTime agora) async {
    final hoje = DateTime(agora.year, agora.month, agora.day);
    return [
      for (var i = 0; i < 7; i++)
        DiaAdesao(
          dia: hoje.subtract(Duration(days: 6 - i)),
          resultado: i == 6 ? ResultadoDia.emCurso : ResultadoDia.semDados,
        ),
    ];
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('pt_PT'));

  testWidgets(
    'uma conta sem histórico NÃO mostra "100% de adesão": diz que ainda não há histórico',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(
        AmparoApp(
          repositorio: SemHistorico(),
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

      expect(find.text('Últimos 7 dias'), findsOneWidget);
      expect(find.text('Ainda sem histórico'), findsOneWidget);
      expect(find.textContaining('% de adesão'), findsNothing);
      expect(find.textContaining('100%'), findsNothing);

      // só a bolinha de hoje, encostada à esquerda (alinhada com o título "Últimos 7 dias")
      final pontos = find.byWidgetPredicate(
        (w) => w.key.toString().contains('ponto-dia'),
      );
      expect(pontos, findsOneWidget);
      expect(
        tester.getTopLeft(pontos).dx,
        closeTo(tester.getTopLeft(find.text('Últimos 7 dias')).dx, 1),
      );
    },
  );
}

import 'package:amparo/app.dart';
import 'package:amparo/dominio/modelos.dart';
import 'package:amparo/ui/ecras/cuidador_hoje.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'apoio/autenticacao_memoria.dart';
import 'apoio/repositorio_memoria.dart';

final sabado = DateTime(2026, 11, 21, 13, 0);

Future<void> entrarAs(WidgetTester tester, DateTime Function() relogio) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(
    AmparoApp(
      repositorio: RepositorioMemoria(agora: sabado),
      autenticacao: AutenticacaoMemoria(),
      relogio: relogio,
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).at(0), 'ana@exemplo.pt');
  await tester.enterText(find.byType(TextField).at(1), 'uma-senha-segura-123');
  await tester.tap(find.widgetWithText(InkWell, 'Entrar'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('pt_PT'));

  group('Botões da toma só na hora', () {
    testWidgets('a mais de 5 min da hora não há botões, só o tempo que falta', (
      tester,
    ) async {
      await entrarAs(tester, () => DateTime(2026, 11, 21, 12, 40));
      // a próxima toma é às 13:00 (faltam 20 min)
      expect(find.text('Faltam 20 min'), findsOneWidget);
      expect(find.text('Ligar a Maria'), findsNothing);
      expect(find.text('Lembrar Maria'), findsNothing);
      // a atrasada (09:00) continua a poder ser confirmada
      expect(find.text('Confirmar que Maria tomou'), findsOneWidget);
    });

    testWidgets('a 5 min da hora já aparecem os botões', (tester) async {
      await entrarAs(tester, () => DateTime(2026, 11, 21, 12, 55));
      expect(find.text('É a hora desta toma'), findsOneWidget);
      expect(find.text('Ligar a Maria'), findsOneWidget);
      expect(find.text('Lembrar Maria'), findsOneWidget);
      expect(find.text('Confirmar que Maria tomou'), findsNWidgets(2));
    });

    test('o tempo que falta arredonda para cima', () {
      final h = DateTime(2026, 11, 21, 13);
      expect(tempoQueFalta(h, DateTime(2026, 11, 21, 12, 55, 30)), '5 min');
      expect(tempoQueFalta(h, DateTime(2026, 11, 21, 12)), '1 h');
      expect(tempoQueFalta(h, DateTime(2026, 11, 21, 7, 38)), '5 h 22 min');
      expect(tempoQueFalta(h, DateTime(2026, 11, 21, 13, 1)), 'agora');
    });
  });

  group('Nomes das páginas', () {
    testWidgets('Principal e Configurações; a conta é "Cuidador"', (
      tester,
    ) async {
      await entrarAs(tester, () => sabado);
      expect(find.text('Principal'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nav-configurações')));
      await tester.pumpAndSettle();
      expect(find.text('Configurações'), findsWidgets);
      expect(find.text('A sua conta · Cuidador'), findsOneWidget);
    });
  });

  group('Receitas: editar e apagar', () {
    testWidgets('tocar numa receita oferece editar e apagar', (tester) async {
      await entrarAs(tester, () => sabado);
      await tester.tap(find.byKey(const ValueKey('nav-receitas')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Metformina 500 mg'));
      await tester.pumpAndSettle();
      expect(find.text('Editar receita'), findsOneWidget);
      expect(find.text('Apagar receita'), findsOneWidget);
      await tester.tap(find.text('Editar receita'));
      await tester.pumpAndSettle();
      expect(find.text('Guardar alterações'), findsOneWidget);
      expect(find.text('Durante quanto tempo?'), findsNothing);
    });
  });

  group('Tipo de medicação', () {
    test('a dose sugere o tipo', () {
      expect(TipoMedicacao.daDose('1 comprimido'), TipoMedicacao.comprimido);
      expect(TipoMedicacao.daDose('5 ml'), TipoMedicacao.liquido);
      expect(TipoMedicacao.daDose('10 gotas'), TipoMedicacao.gotas);
      expect(TipoMedicacao.daDose('1 injeção'), TipoMedicacao.injecao);
      expect(TipoMedicacao.daDose('2 puffs'), TipoMedicacao.inalador);
      expect(TipoMedicacao.daDose('1'), TipoMedicacao.outro);
    });

    test('uma receita existente volta a abrir com a frequência certa', () {
      const duas = Receita(
        id: 'r',
        medicamento: 'X',
        dose: '1 comprimido',
        horario: '08:00, 20:00',
        ativa: true,
        horasFixas: ['08:00', '20:00'],
      );
      expect(duas.comoNova().frequencia, Frequencia.duasVezesDia);
      const oito = Receita(
        id: 'r',
        medicamento: 'X',
        dose: '5 ml',
        horario: 'De 8 em 8 horas',
        ativa: true,
        intervaloHoras: 8,
      );
      expect(oito.comoNova().frequencia, Frequencia.cadaOitoHoras);
      expect(oito.comoNova().tipo, TipoMedicacao.liquido);
    });
  });

  test('o cuidador também pode tomar medicação: o perfil tem o nome dele', () {
    const eu = Perfil(id: 'a', nome: 'Ana');
    expect(eProprioCuidador(eu, ' ana '), isTrue);
    expect(
      eProprioCuidador(const Perfil(id: 'm', nome: 'Maria'), 'Ana'),
      isFalse,
    );
    expect(eProprioCuidador(eu, null), isFalse);
  });
}

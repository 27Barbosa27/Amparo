import 'package:amparo/app.dart';
import 'package:amparo/dados/api.dart';

import 'apoio/autenticacao_memoria.dart';

import 'package:amparo/dados/corpo_receita.dart';

import 'apoio/repositorio_memoria.dart';

import 'package:amparo/dominio/modelos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

final agora = DateTime(2026, 11, 21, 13, 0); // sábado, 13:00

/// Falha a criar a receita as primeiras vezes, para testar o ecrã de erro e o "Tentar de novo".
class RepositorioQueFalha extends RepositorioMemoria {
  RepositorioQueFalha({required super.agora, this.falhas = 1});
  int falhas;

  @override
  Future<Receita> criarReceita(
    String perfilId,
    NovaReceita receita,
    DateTime agora,
  ) async {
    if (falhas > 0) {
      falhas--;
      throw const ErroApi('sem_rede');
    }
    return super.criarReceita(perfilId, receita, agora);
  }
}

Future<void> abrir(WidgetTester tester, RepositorioMemoria repo) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(
    AmparoApp(
      repositorio: repo,
      autenticacao: AutenticacaoMemoria(),
      relogio: () => agora,
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).at(0), 'ana@exemplo.pt');
  await tester.enterText(find.byType(TextField).at(1), 'uma-senha-segura-123');
  await tester.tap(find.widgetWithText(InkWell, 'Entrar'));
  await tester.pumpAndSettle();
}

Future<void> irParaReceitas(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('nav-receitas')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('pt_PT'));

  group('Tradução do formulário para a API', () {
    NovaReceita receita(
      Frequencia f, {
      String hora = '08:00',
      List<String> outras = const [],
    }) => NovaReceita(
      medicamento: 'Lisinopril 10 mg',
      dose: '1 comprimido',
      frequencia: f,
      hora: int.parse(hora.substring(0, 2)),
      minuto: int.parse(hora.substring(3)),
      duracao: Duracao.tresMeses,
      horasOutra: outras,
    );

    test(
      '"de 8 em 8 horas" é um intervalo, a contar da próxima primeira toma',
      () {
        final c = corpoDaReceita(
          receita(Frequencia.cadaOitoHoras),
          'm1',
          agora,
        );
        expect(c['horario'], {'tipo': 'intervalo', 'intervaloHoras': 8});
        // às 13:00 já passou das 08:00 de hoje: começa amanhã às 08:00
        expect(
          DateTime.parse(c['inicio']! as String).toLocal(),
          DateTime(2026, 11, 22, 8),
        );
        expect(
          DateTime.parse(c['fim']! as String).toLocal(),
          DateTime(2026, 11, 22, 8).add(const Duration(days: 90)),
        );
        expect(c['medicamentoId'], 'm1');
        expect(c['dose'], '1 comprimido');
      },
    );

    test('"2 vezes ao dia" são duas horas fixas, 12 horas depois uma da outra, e começam já', () {
      final c = corpoDaReceita(
        receita(Frequencia.duasVezesDia, hora: '09:30'),
        'm1',
        agora,
      );
      expect(c['horario'], {
        'tipo': 'horas_fixas',
        'horasLocais': ['09:30', '21:30'],
      });
      expect(DateTime.parse(c['inicio']! as String).toLocal(), agora);
    });

    test('"2 vezes ao dia" a partir das 20:00 dá 08:00 e 20:00, por ordem', () {
      final c = corpoDaReceita(
        receita(Frequencia.duasVezesDia, hora: '20:00'),
        'm1',
        agora,
      );
      expect((c['horario']! as Map)['horasLocais'], ['08:00', '20:00']);
    });

    test(
      '"1 vez ao dia" e "Outra" usam horas fixas (sem repetições, por ordem)',
      () {
        expect(
          corpoDaReceita(
            receita(Frequencia.umaVezDia, hora: '07:15'),
            'm',
            agora,
          )['horario'],
          {
            'tipo': 'horas_fixas',
            'horasLocais': ['07:15'],
          },
        );
        final c = corpoDaReceita(
          receita(
            Frequencia.outra,
            outras: ['21:00', '08:00', '14:00', '08:00'],
          ),
          'm',
          agora,
        );
        expect((c['horario']! as Map)['horasLocais'], [
          '08:00',
          '14:00',
          '21:00',
        ]);
      },
    );

    test('a duração define o fim: 7 dias, 1 mês (30) e 3 meses (90)', () {
      for (final (d, dias) in [
        (Duracao.seteDias, 7),
        (Duracao.umMes, 30),
        (Duracao.tresMeses, 90),
      ]) {
        final r = NovaReceita(
          medicamento: 'X',
          dose: '1',
          frequencia: Frequencia.umaVezDia,
          hora: 8,
          minuto: 0,
          duracao: d,
        );
        final c = corpoDaReceita(r, 'm', agora);
        final diferenca = DateTime.parse(c['fim']! as String)
            .difference(DateTime.parse(c['inicio']! as String));
        expect(diferenca, Duration(days: dias));
      }
    });

    test('lerHoras aceita várias formas e recusa o que não é hora', () {
      expect(lerHoras('08:00, 14:00 21:00'), ['08:00', '14:00', '21:00']);
      expect(lerHoras('8:05'), ['08:05']);
      for (final mau in ['', '25:00', '08:60', '8h', '08:00 e 14:00', 'abc']) {
        expect(lerHoras(mau), isNull, reason: mau);
      }
    });

    test(
      'a primeira toma por extenso: hoje se ainda não passou, senão amanhã',
      () {
        expect(
          receita(
            Frequencia.umaVezDia,
            hora: '21:00',
          ).primeiraTomaPorExtenso(agora),
          'Hoje, às 21:00',
        );
        expect(
          receita(
            Frequencia.umaVezDia,
            hora: '08:00',
          ).primeiraTomaPorExtenso(agora),
          'Amanhã, às 08:00',
        );
      },
    );

    test(
      'os dias que restam definem o aviso "a acabar" e a barra de stock',
      () {
        const r = Receita(
          id: 'r',
          medicamento: 'X',
          dose: '1',
          horario: '08:00',
          ativa: true,
          unidadesIniciais: 40,
          unidadesRestantes: 10,
          diasRestantes: 4,
        );
        expect(r.aAcabar(), isTrue);
        expect(r.aAcabar(3), isFalse);
        expect(r.fracaoRestante, .25);
        const sem = Receita(
          id: 'r',
          medicamento: 'X',
          dose: '1',
          horario: '08:00',
          ativa: true,
        );
        expect(sem.aAcabar(), isFalse);
        expect(sem.fracaoRestante, isNull);
      },
    );
  });

  group('Receitas', () {
    testWidgets(
      'mostra o aviso do que está a acabar, as receitas em dia e a barra do design',
      (tester) async {
        await abrir(tester, RepositorioMemoria(agora: agora));
        await irParaReceitas(tester);
        expect(find.text('3 medicamentos de Maria'), findsOneWidget);
        expect(find.text('Acaba em 4 dias'), findsOneWidget);
        expect(
          find.text('Restam 4 unidades. Receita válida até 15/03/2027.'),
          findsOneWidget,
        );
        expect(find.text('Pedir renovação ao médico'), findsOneWidget);
        expect(find.text('Em dia'), findsOneWidget);
        expect(find.text('Metformina 500 mg'), findsOneWidget);
        expect(find.text('23 dias'), findsOneWidget);
        expect(find.text('41 dias'), findsOneWidget);
        expect(find.text('Válida até 02/06/2027'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
        expect(find.text('Adicionar receita'), findsOneWidget);
      },
    );
  });

  group('Adicionar receita', () {
    Future<void> abrirFormulario(
      WidgetTester tester,
      RepositorioMemoria repo,
    ) async {
      await abrir(tester, repo);
      await irParaReceitas(tester);
      await tester.tap(find.text('Adicionar receita'));
      await tester.pumpAndSettle();
    }

    testWidgets('valida os campos e mostra o erro por baixo de cada um', (
      tester,
    ) async {
      await abrirFormulario(tester, RepositorioMemoria(agora: agora));
      await tester.enterText(find.byType(TextField).at(1), '');
      await tester.enterText(find.byType(TextField).at(2), '25:99');
      await tester.tap(find.text('Criar tomas e alarmes'));
      await tester.pumpAndSettle();
      expect(find.text('Escreva o nome do medicamento.'), findsOneWidget);
      expect(
        find.text('Escreva a dose (por exemplo, 1 comprimido).'),
        findsOneWidget,
      );
      expect(find.text('Escreva uma hora como 08:00.'), findsOneWidget);
      expect(find.text('A criar as tomas'), findsNothing);
    });

    testWidgets('"Outra" pede as horas e valida-as', (tester) async {
      await abrirFormulario(tester, RepositorioMemoria(agora: agora));
      await tester.tap(find.text('Outra'));
      await tester.pumpAndSettle();
      expect(find.text('Horas das tomas'), findsOneWidget);
      expect(find.text('Primeira toma'), findsNothing);
      await tester.enterText(find.byType(TextField).at(0), 'Ramipril 5 mg');
      await tester.enterText(find.byType(TextField).at(2), 'de manhã');
      await tester.tap(find.text('Criar tomas e alarmes'));
      await tester.pumpAndSettle();
      expect(find.text('Use horas como 08:00, 14:00, 21:00.'), findsOneWidget);
    });

    testWidgets(
      'fluxo completo: carregar, receita criada, e as tomas aparecem em Hoje',
      (tester) async {
        await abrirFormulario(tester, RepositorioMemoria(agora: agora));
        await tester.enterText(find.byType(TextField).at(0), 'Ramipril 5 mg');
        await tester.tap(find.text('1 vez ao dia'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).at(2), '21:00');
        await tester.tap(find.text('3 meses'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Criar tomas e alarmes'));
        await tester.pumpAndSettle();

        expect(find.text('A criar as tomas'), findsOneWidget);
        expect(find.text('Ramipril 5 mg · 3 meses'), findsOneWidget);
        expect(find.text('Gerar as tomas (1)'), findsOneWidget);
        expect(find.text('Agendar os alarmes'), findsOneWidget);
        expect(
          find.text('Em breve'),
          findsOneWidget,
        ); // os alarmes locais ainda não existem: não se finge
        expect(find.text('Sincronizar com Maria'), findsOneWidget);
        await tester.tap(find.text('Continuar'));
        await tester.pumpAndSettle();

        expect(find.text('Receita criada'), findsOneWidget);
        expect(find.text('Ramipril 5 mg'), findsOneWidget);
        expect(find.text('1 vez ao dia · 3 meses'), findsOneWidget);
        expect(find.text('Hoje, às 21:00'), findsOneWidget);
        await tester.tap(find.text('Ver página principal'));
        await tester.pumpAndSettle();
        expect(find.text('Ramipril 5 mg'), findsOneWidget);
        expect(find.text('1 comprimido'), findsOneWidget);
      },
    );

    testWidgets('"Adicionar outra receita" abre um formulário limpo', (
      tester,
    ) async {
      await abrirFormulario(tester, RepositorioMemoria(agora: agora));
      await tester.enterText(find.byType(TextField).at(0), 'Ramipril 5 mg');
      await tester.tap(find.text('Criar tomas e alarmes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adicionar outra receita'));
      await tester.pumpAndSettle();
      expect(find.text('Adicionar receita'), findsOneWidget);
      expect(
        (tester.widget(
          find.byType(TextField).at(0),
        ) as TextField).controller!.text,
        isEmpty,
      );
    });

    testWidgets(
      'se guardar falha mostra o erro com a mensagem certa, e "Tentar de novo" resolve',
      (tester) async {
        await abrirFormulario(tester, RepositorioQueFalha(agora: agora));
        await tester.enterText(find.byType(TextField).at(0), 'Ramipril 5 mg');
        await tester.tap(find.text('Criar tomas e alarmes'));
        await tester.pumpAndSettle();
        expect(find.text('Não foi possível guardar'), findsOneWidget);
        expect(
          find.text(
            'Sem ligação à internet. Verifique a ligação e tente outra vez.',
          ),
          findsOneWidget,
        );
        expect(find.text('Receita do Ramipril 5 mg'), findsOneWidget);
        expect(
          find.text('Guardar para depois'),
          findsNothing,
        ); // só existirá com a fila offline
        await tester.tap(find.text('Tentar de novo'));
        await tester.pumpAndSettle();
        expect(find.text('A criar as tomas'), findsOneWidget);
        await tester.tap(find.text('Continuar'));
        await tester.pumpAndSettle();
        expect(find.text('Receita criada'), findsOneWidget);
      },
    );

    testWidgets('"Cancelar" no erro volta atrás sem criar nada', (
      tester,
    ) async {
      final repo = RepositorioQueFalha(agora: agora, falhas: 5);
      await abrirFormulario(tester, repo);
      await tester.enterText(find.byType(TextField).at(0), 'Ramipril 5 mg');
      await tester.tap(find.text('Criar tomas e alarmes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(
        (await repo.receitas('maria'))
            .where((r) => r.medicamento == 'Ramipril 5 mg'),
        isEmpty,
      );
    });
  });

  group('Adicionar pessoa', () {
    Future<void> abrirFormulario(WidgetTester tester) async {
      await abrir(tester, RepositorioMemoria(agora: agora));
      await tester.tap(find.widgetWithText(InkWell, 'Maria'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adicionar pessoa'));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'o botão só fica ativo depois de declarar a autorização, e o nome é obrigatório',
      (tester) async {
        await abrirFormulario(tester);
        expect(
          find.text('Basta um nome ou apelido. Não pedimos dados sensíveis.'),
          findsOneWidget,
        );
        expect(find.text('A pessoa, no telemóvel dela'), findsOneWidget);
        expect(find.text('Eu, no meu telemóvel'), findsOneWidget);
        // sem a caixa marcada, não se cria
        await tester.tap(find.text('Criar perfil'));
        await tester.pumpAndSettle();
        expect(find.text('Rosa já está no Amparo'), findsNothing);
        await tester.tap(find.byType(Checkbox));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Criar perfil'));
        await tester.pumpAndSettle();
        expect(find.text('Escreva um nome ou apelido.'), findsOneWidget);
      },
    );

    testWidgets(
      'cria a pessoa, passa a acompanhá-la e mostra o resultado, sem assumir o género',
      (tester) async {
        await abrirFormulario(tester);
        await tester.enterText(find.byType(TextField).at(0), 'Avó Rosa');
        await tester.tap(find.text('Muito grande'));
        await tester.tap(find.byType(Checkbox));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Criar perfil'));
        await tester.pumpAndSettle();

        expect(find.text('Avó Rosa já está no Amparo'), findsOneWidget);
        expect(
          find.text(
            'O perfil está criado. Falta ligar o telemóvel de Avó Rosa.',
          ),
          findsOneWidget,
        );
        expect(find.text('Ligar o telemóvel de Avó Rosa'), findsOneWidget);
        expect(find.text('Adicionar uma receita primeiro'), findsOneWidget);
        await tester.tap(find.text('Concluir'));
        await tester.pumpAndSettle();
        // a app passa a mostrar a nova pessoa
        expect(find.widgetWithText(InkWell, 'Avó Rosa'), findsOneWidget);
        expect(find.text('Hoje não há tomas.'), findsOneWidget);
      },
    );

    testWidgets(
      'se os alarmes tocam no telemóvel do cuidador, não pede para ligar o da pessoa',
      (tester) async {
        await abrirFormulario(tester);
        await tester.enterText(find.byType(TextField).at(0), 'Manuel');
        await tester.tap(find.text('Eu, no meu telemóvel'));
        await tester.tap(find.byType(Checkbox));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Criar perfil'));
        await tester.pumpAndSettle();
        expect(
          find.text('O perfil está criado. Os alarmes tocam no seu telemóvel.'),
          findsOneWidget,
        );
        expect(find.textContaining('Ligar o telemóvel'), findsNothing);
      },
    );

    testWidgets(
      '"Adicionar uma receita primeiro" abre o formulário da receita para essa pessoa',
      (tester) async {
        await abrirFormulario(tester);
        await tester.enterText(find.byType(TextField).at(0), 'Rosa');
        await tester.tap(find.byType(Checkbox));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Criar perfil'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Adicionar uma receita primeiro'));
        await tester.pumpAndSettle();
        expect(find.text('Adicionar receita'), findsOneWidget);
        expect(
          find.text('Criamos as tomas por si, para Rosa.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('uma conta nova (sem ninguém) começa por "Adicionar pessoa"', (
      tester,
    ) async {
      await abrir(tester, RepositorioMemoria(agora: agora, vazio: true));
      expect(
        find.text(
          'Pode usá-lo só para si, para os seus medicamentos, ou acompanhar outra pessoa. Pode fazer as duas coisas.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(InkWell, 'Acompanhar outra pessoa'));
      await tester.pumpAndSettle();
      expect(find.text('Nome ou apelido'), findsOneWidget);
    });
  });
}

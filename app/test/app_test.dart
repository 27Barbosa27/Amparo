import 'dart:math' as math;

import 'package:amparo/app.dart';
import 'package:amparo/dados/repositorio_memoria.dart';
import 'package:amparo/tema/tokens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

final agora = DateTime(2026, 11, 21, 13, 0); // sábado

Future<void> abrir(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AmparoApp(
      repositorio: RepositorioMemoria(agora: agora),
      relogio: () => agora,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> entrar(WidgetTester tester) async {
  await abrir(tester);
  await tester.enterText(
    find.widgetWithText(TextField, 'Email'),
    'ana@exemplo.pt',
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'Palavra-passe'),
    'uma-senha-segura-123',
  );
  await tester.tap(find.text('Entrar'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('pt_PT'));

  group('Entrar', () {
    testWidgets(
      'mostra os dois métodos de início de sessão juntos e nenhum botão de Face ID',
      (tester) async {
        await abrir(tester);
        expect(find.text('Continuar com a Apple'), findsOneWidget);
        expect(find.text('Continuar com a Google'), findsOneWidget);
        expect(find.textContaining('Face ID'), findsNothing);
      },
    );

    testWidgets('pede o email e a palavra-passe e não avança sem eles', (
      tester,
    ) async {
      await abrir(tester);
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();
      expect(find.text('Escreva o email e a palavra-passe.'), findsOneWidget);
      expect(find.text('Hoje'), findsNothing);
    });

    testWidgets('com os dados preenchidos abre o "Hoje" do cuidador', (
      tester,
    ) async {
      await entrar(tester);
      expect(find.text('Sábado, 21 de novembro'), findsOneWidget);
      expect(find.text('Maria'), findsWidgets);
    });
  });

  group('Hoje (cuidador)', () {
    testWidgets('mostra o resumo, a adesão e a linha do tempo do design', (
      tester,
    ) async {
      await entrar(tester);
      expect(find.text('1/4'), findsOneWidget);
      expect(find.text('Últimos 7 dias'), findsOneWidget);
      expect(find.text('83% de adesão'), findsOneWidget);
      expect(find.text('08:00 · Metformina e Vitamina D'), findsOneWidget);
      expect(find.text('Tomadas às 08:12'), findsOneWidget);
      expect(find.text('09:00 · Lisinopril 10 mg'), findsOneWidget);
      expect(find.text('Por confirmar'), findsWidgets);
      expect(find.text('21:00 · Atorvastatina 20 mg'), findsOneWidget);
    });

    testWidgets(
      'marcar a toma atrasada como tomada atualiza o resumo e diz quem a marcou',
      (tester) async {
        await entrar(tester);
        await tester.tap(find.text('Marcar como tomada'));
        await tester.pumpAndSettle();
        expect(find.text('2/4'), findsOneWidget);
        expect(find.textContaining('Marcada por Ana'), findsOneWidget);
      },
    );

    testWidgets('trocar de pessoa mostra as tomas dela', (tester) async {
      await entrar(tester);
      await tester.tap(find.widgetWithText(InkWell, 'Maria'));
      await tester.pumpAndSettle();
      expect(find.text('Quem vai acompanhar?'), findsOneWidget);
      await tester.tap(find.text('Manuel'));
      await tester.pumpAndSettle();
      expect(find.text('10:00 · Ramipril 5 mg'), findsOneWidget);
      expect(find.text('09:00 · Lisinopril 10 mg'), findsNothing);
    });

    testWidgets('a barra em ilha leva a Receitas e a Mais', (tester) async {
      await entrar(tester);
      await tester.tap(find.bySemanticsLabel('Receitas'));
      await tester.pumpAndSettle();
      expect(find.text('Medicamentos de Maria'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Mais'));
      await tester.pumpAndSettle();
      expect(find.text('Ver como a pessoa vê'), findsOneWidget);
    });
  });

  group('Modo simples (ver como a pessoa vê)', () {
    Future<void> abrirModoSimples(WidgetTester tester) async {
      await entrar(tester);
      await tester.tap(find.bySemanticsLabel('Mais'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver como a pessoa vê'));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'põe a toma atrasada em destaque, com botões grandes e o aviso de não tomar em dobro',
      (tester) async {
        await abrirModoSimples(tester);
        expect(find.text('Boa tarde, Maria'), findsOneWidget);
        expect(find.text('1 de 4 tomas feitas'), findsOneWidget);
        expect(find.text('Atrasada desde as 09:00'), findsOneWidget);
        expect(find.text('há 4 h'), findsOneWidget);
        expect(find.text('Lisinopril'), findsOneWidget);
        expect(
          find.text('Não tome em dobro. Se tiver dúvidas, ligue à Ana.'),
          findsOneWidget,
        );
        final alturaTomei = tester
            .getSize(find.widgetWithText(InkWell, 'Tomei').first)
            .height;
        expect(alturaTomei, greaterThanOrEqualTo(64));
      },
    );

    testWidgets(
      '"Tomei" regista, avança para a toma seguinte e oferece desfazer',
      (tester) async {
        await abrirModoSimples(tester);
        await tester.tap(find.text('Tomei'));
        await tester.pumpAndSettle();
        expect(find.text('2 de 4 tomas feitas'), findsOneWidget);
        expect(find.text('Próxima toma, às 13:00'), findsOneWidget);
        expect(find.text('Desfazer'), findsOneWidget);
        await tester.tap(find.text('Desfazer'));
        await tester.pumpAndSettle();
        expect(find.text('1 de 4 tomas feitas'), findsOneWidget);
        expect(find.text('Atrasada desde as 09:00'), findsOneWidget);
      },
    );

    testWidgets('saltar não conta como tomada', (tester) async {
      await abrirModoSimples(tester);
      await tester.tap(find.text('Saltar'));
      await tester.pumpAndSettle();
      expect(find.text('1 de 4 tomas feitas'), findsOneWidget);
      expect(find.text('Atrasada desde as 09:00'), findsNothing);
    });

    testWidgets('sair da pré-visualização volta ao modo cuidador', (
      tester,
    ) async {
      await abrirModoSimples(tester);
      await tester.tap(find.text('Sair da pré-visualização'));
      await tester.pumpAndSettle();
      expect(
        find.text('Ver como a pessoa vê'),
        findsOneWidget,
      ); // volta ao separador de onde veio (Mais)
    });
  });

  group('Tema', () {
    testWidgets('é escuro por defeito, com os tokens do design', (
      tester,
    ) async {
      await abrir(tester);
      final ctx = tester.element(find.text('Amparo'));
      expect(ctx.t.escuro, isTrue);
      expect(ctx.t.primaria, const Color(0xFF2DD4BF));
    });

    testWidgets(
      'o interruptor muda para o tema claro (verde-azulado mais escuro)',
      (tester) async {
        await entrar(tester);
        await tester.tap(find.bySemanticsLabel('Mais'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        final ctx = tester.element(find.text('Mais').first);
        expect(ctx.t.escuro, isFalse);
        expect(ctx.t.primaria, const Color(0xFF0F766E));
      },
    );

    test(
      'o texto sobre cada superfície tem contraste suficiente (WCAG AA, 4.5:1)',
      () {
        double lum(Color c) {
          double f(double v) => v <= .03928
              ? v / 12.92
              : math.pow((v + .055) / 1.055, 2.4).toDouble();
          return .2126 * f(c.r) + .7152 * f(c.g) + .0722 * f(c.b);
        }

        double contraste(Color a, Color b) {
          final (x, y) = (lum(a), lum(b));
          return (math.max(x, y) + .05) / (math.min(x, y) + .05);
        }

        for (final t in [Tokens.escuroTema, Tokens.claroTema]) {
          final pares = {
            'texto/superficie': (t.texto, t.superficie),
            'texto2/superficie': (t.texto2, t.superficie),
            'sobrePrimaria/primaria': (t.sobrePrimaria, t.primaria),
            'sobreHeroi/heroi': (t.sobreHeroi, t.heroi),
            'sobreHeroi2/heroi': (t.sobreHeroi2, t.heroi),
            'sobrePrimariaSuave/primariaSuave': (
              t.sobrePrimariaSuave,
              t.primariaSuave,
            ),
            'okTexto/okSuave': (t.okTexto, t.okSuave),
            'avisoTexto/avisoSuave': (t.avisoTexto, t.avisoSuave),
            'mauTexto/mauSuave': (t.mauTexto, t.mauSuave),
            'sobreAv2/av2': (t.sobreAv2, t.av2),
            'sobreAviso/aviso': (Tokens.sobreAviso, t.aviso),
          };
          pares.forEach((nome, p) {
            expect(
              contraste(p.$1, p.$2),
              greaterThanOrEqualTo(4.5),
              reason: '${t.escuro ? "escuro" : "claro"}: $nome',
            );
          });
        }
      },
    );
  });
}

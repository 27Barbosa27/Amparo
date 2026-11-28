import 'package:amparo/app.dart';
import 'package:amparo/dados/alarmes.dart';
import 'package:amparo/dados/push.dart';
import 'package:amparo/dominio/modelos.dart';
import 'package:amparo/estado/hoje_controlador.dart';
import 'package:amparo/ui/ecras/telemoveis.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'apoio/alarmes_memoria.dart';
import 'apoio/autenticacao_memoria.dart';
import 'apoio/ligacao_memoria.dart';
import 'apoio/repositorio_memoria.dart';

/// Dois minutos antes da toma das 13:00 (Metformina): já aparecem "Ligar" e "Lembrar".
final agora = DateTime(2026, 11, 21, 12, 58);

typedef Montagem = ({
  RepositorioMemoria repo,
  AlarmesMemoria alarmes,
  AutenticacaoMemoria auth,
  LigacaoMemoria ligacao,
  List<String> ficheiros,
});

Future<Montagem> abrir(WidgetTester tester, {AlarmesMemoria? alarmes}) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final repo = RepositorioMemoria(agora: agora);
  final a = alarmes ?? AlarmesMemoria();
  final auth = AutenticacaoMemoria();
  final ligacao = LigacaoMemoria(agora: agora);
  final ficheiros = <String>[];
  await tester.pumpWidget(
    AmparoApp(
      repositorio: repo,
      autenticacao: auth,
      relogio: () => agora,
      alarmes: a,
      ligacao: ligacao,
      guardarFicheiro: (nome, bytes) async {
        ficheiros.add(nome);
        return true;
      },
    ),
  );
  await tester.pumpAndSettle();
  return (
    repo: repo,
    alarmes: a,
    auth: auth,
    ligacao: ligacao,
    ficheiros: ficheiros,
  );
}

Future<void> entrar(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).at(0), 'ana@exemplo.pt');
  await tester.enterText(find.byType(TextField).at(1), 'uma-senha-segura-123');
  await tester.tap(find.widgetWithText(InkWell, 'Entrar'));
  await tester.pumpAndSettle();
}

Future<void> irParaMais(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('nav-configurações')));
  await tester.pumpAndSettle();
}

final _metformina = AlarmeToma(
  tomaId: 't3',
  perfilId: 'maria',
  medicamento: 'Metformina',
  dose: '500 mg',
  hora: DateTime(2026, 11, 21, 13),
);

void main() {
  setUpAll(() => initializeDateFormatting('pt_PT'));

  group('Alarme: o que vai na notificação', () {
    test('o payload leva a toma e a pessoa, e volta igual', () {
      final a = AlarmeToma(
        tomaId: 't3',
        perfilId: 'maria',
        medicamento: 'Metformina',
        dose: '500 mg',
        hora: DateTime(2026, 11, 21, 13),
      );
      final b = AlarmeToma.doPayload(a.paraPayload())!;
      expect(b.tomaId, 't3');
      expect(b.perfilId, 'maria');
      expect(b.medicamento, 'Metformina');
      expect(b.dose, '500 mg');
      expect(b.hora, DateTime(2026, 11, 21, 13));
      // o formato antigo do spike ("nome|dose") não é um alarme reconhecível
      expect(AlarmeToma.doPayload('Metformina|500 mg'), isNull);
    });

    test(
      'tocar no alarme abre-o; "Tomei" regista; "Adiar" fica em segundo plano',
      () {
        final payload = AlarmeToma(
          tomaId: 't3',
          perfilId: 'maria',
          medicamento: 'Metformina',
          dose: '',
          hora: DateTime(2026, 11, 21, 13),
        ).paraPayload();
        NotificationResponse r(String? acao) => NotificationResponse(
          notificationResponseType: acao == null
              ? NotificationResponseType.selectedNotification
              : NotificationResponseType.selectedNotificationAction,
          actionId: acao,
          payload: payload,
        );
        expect(RespostaAlarme.de(r(null))!.acao, AcaoAlarme.abrir);
        expect(RespostaAlarme.de(r('tomei'))!.acao, AcaoAlarme.tomei);
        expect(RespostaAlarme.de(r('adiar10')), isNull);
        final aviso = RespostaAlarme.de(
          const NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            payload: '{"aviso":"maria"}',
          ),
        )!;
        expect(aviso.acao, AcaoAlarme.aviso);
        expect(aviso.perfilId, 'maria');
      },
    );

    test('as permissões em falta contam-se uma a uma', () {
      expect(PermissoesAlarme.todas.emFalta, 0);
      expect(
        const PermissoesAlarme(
          alarmesExatos: true,
          bateriaSemLimites: false,
          ecraBloqueado: false,
        ).emFalta,
        2,
      );
    });
  });

  group('Quem agenda os alarmes', () {
    test('só agenda quando os alarmes tocam neste telemóvel', () async {
      for (final aqui in [true, false]) {
        final alarmes = AlarmesMemoria();
        final c = HojeControlador(
          repositorio: RepositorioMemoria(agora: agora),
          perfil: const Perfil(id: 'maria', nome: 'Maria'),
          relogio: () => agora,
          alarmes: alarmes,
          agendarAlarmes: aqui,
        );
        await c.carregar();
        expect(alarmes.agendados_.containsKey('maria'), aqui);
        if (aqui) expect(alarmes.agendados_['maria'], ['t2', 't3', 't4']);
        c.dispose();
      }
    });

    testWidgets('o cuidador que vê a Maria não agenda os alarmes dela', (
      tester,
    ) async {
      final m = await abrir(tester);
      await entrar(tester);
      expect(m.alarmes.agendados_, isEmpty);
    });

    testWidgets('terminar a sessão cancela os alarmes', (tester) async {
      final m = await abrir(tester);
      await entrar(tester);
      await irParaMais(tester);
      await tester.scrollUntilVisible(find.text('Terminar sessão'), 200);
      await tester.tap(find.text('Terminar sessão'));
      await tester.pumpAndSettle();
      expect(m.alarmes.cancelamentosTotais, 1);
    });
  });

  group('Alarme em ecrã inteiro', () {
    testWidgets('mostra a hora e o medicamento; "Tomei" regista a toma', (
      tester,
    ) async {
      final m = await abrir(tester);
      await entrar(tester);
      m.alarmes.responder(
        RespostaAlarme(AcaoAlarme.abrir, alarme: _metformina),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hora do medicamento'), findsOneWidget);
      expect(find.text('13:00'), findsOneWidget);
      expect(find.text('Metformina'), findsWidgets);
      await tester.tap(find.text('Tomei'));
      await tester.pumpAndSettle();
      expect(find.text('Hora do medicamento'), findsNothing);
      final t3 = (await m.repo.tomasDeHoje(
        'maria',
        agora,
      )).firstWhere((t) => t.id == 't3');
      expect(t3.estado, EstadoToma.tomada);
      // fora do alarme, a app volta a pedir para desbloquear
      expect(m.alarmes.sobreBloqueio.last, isFalse);
    });

    testWidgets('"Adiar 10 min" diz quando volta a avisar', (tester) async {
      final m = await abrir(tester);
      await entrar(tester);
      m.alarmes.responder(
        RespostaAlarme(AcaoAlarme.abrir, alarme: _metformina),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adiar 10 min'));
      await tester.pumpAndSettle();
      expect(m.alarmes.adiados, ['t3']);
      expect(find.text('Volto a avisar às 13:10'), findsOneWidget);
      expect(find.text('Tomei agora'), findsOneWidget);
      await tester.tap(find.text('Está bem'));
      await tester.pumpAndSettle();
      expect(find.text('Adiado'), findsNothing);
    });

    testWidgets('"Tomei" na notificação regista sem abrir o alarme', (
      tester,
    ) async {
      final m = await abrir(tester);
      await entrar(tester);
      m.alarmes.responder(
        RespostaAlarme(AcaoAlarme.tomei, alarme: _metformina),
      );
      await tester.pumpAndSettle();
      expect(find.text('Metformina marcada como tomada.'), findsOneWidget);
      expect(find.text('Hora do medicamento'), findsNothing);
    });
  });

  group('Alarmes fiáveis', () {
    testWidgets('o Mais diz quantas faltam; o botão pede só as que faltam', (
      tester,
    ) async {
      final alarmes = AlarmesMemoria(
        estado: const PermissoesAlarme(
          alarmesExatos: true,
          bateriaSemLimites: false,
          ecraBloqueado: false,
        ),
      );
      await abrir(tester, alarmes: alarmes);
      await entrar(tester);
      await irParaMais(tester);
      expect(find.text('2 em falta'), findsOneWidget);
      await tester.tap(find.text('Alarmes fiáveis'));
      await tester.pumpAndSettle();
      expect(find.text('Para os alarmes tocarem sempre'), findsOneWidget);
      expect(find.text('Feito'), findsOneWidget);
      expect(find.text('Falta'), findsNWidgets(2));
      await tester.tap(find.text('Abrir definições do telemóvel'));
      await tester.pumpAndSettle();
      expect(alarmes.pedidos, 1);
      expect(find.text('Alarmes prontos'), findsOneWidget);
      await tester.tap(find.text('Concluir'));
      await tester.pumpAndSettle();
      expect(find.text('2 em falta'), findsNothing);
    });

    testWidgets('"Mais tarde" sai sem pedir nada', (tester) async {
      final alarmes = AlarmesMemoria(
        estado: const PermissoesAlarme(
          alarmesExatos: false,
          bateriaSemLimites: true,
          ecraBloqueado: true,
        ),
      );
      await abrir(tester, alarmes: alarmes);
      await entrar(tester);
      await irParaMais(tester);
      await tester.tap(find.text('Alarmes fiáveis'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Falta 1 passo'), findsOneWidget);
      await tester.tap(find.text('Mais tarde'));
      await tester.pumpAndSettle();
      expect(alarmes.pedidos, 0);
      expect(find.text('1 em falta'), findsOneWidget);
    });

    testWidgets(
      'ao ligar o telemóvel da pessoa: pede as permissões e conta ao servidor como estão',
      (tester) async {
        final alarmes = AlarmesMemoria(
          estado: const PermissoesAlarme(
            alarmesExatos: true,
            bateriaSemLimites: false,
            ecraBloqueado: true,
          ),
        );
        final m = await abrir(tester, alarmes: alarmes);
        await tester.tap(find.textContaining('Tenho um código'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '482 915');
        await tester.tap(find.text('Ligar este telemóvel'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continuar'));
        await tester.pumpAndSettle();
        expect(find.text('Para os alarmes tocarem sempre'), findsOneWidget);
        // o telemóvel da pessoa agenda os alarmes dela e reporta-os
        expect(alarmes.agendados_['maria'], isNotEmpty);
        final enviados = m.ligacao.repoDoTelemovel!.estadosDeAlarmes;
        expect(enviados, isNotEmpty);
        expect(enviados.last.agendados, alarmes.agendados_['maria']!.length);
        expect(enviados.last.permissoes.bateriaSemLimites, isFalse);
      },
    );
  });

  group('Ligar e Lembrar', () {
    testWidgets('"Lembrar Maria" envia o lembrete', (tester) async {
      final m = await abrir(tester);
      await entrar(tester);
      await tester.tap(find.text('Lembrar Maria'));
      await tester.pumpAndSettle();
      expect(m.repo.lembretes, ['t3']);
      expect(
        find.text('Enviámos um lembrete para o telemóvel de Maria.'),
        findsOneWidget,
      );
    });

    testWidgets('sem telemóvel ligado, o lembrete explica porquê', (
      tester,
    ) async {
      final m = await abrir(tester);
      m.repo.erroDoLembrete = 'sem_telemovel';
      await entrar(tester);
      await tester.tap(find.text('Lembrar Maria'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'O telemóvel de Maria ainda não está ligado ou não recebe notificações.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('sem número guardado não há "Ligar"; com número, há', (
      tester,
    ) async {
      final m = await abrir(tester);
      await m.repo.atualizarTelefone('maria', null);
      await entrar(tester);
      expect(find.text('Ligar a Maria'), findsNothing);
      expect(find.text('Lembrar Maria'), findsOneWidget);

      await irParaMais(tester);
      expect(find.text('Número de Maria'), findsOneWidget);
      expect(find.text('Adicionar'), findsOneWidget);
      await tester.tap(find.text('Número de Maria'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Escreva só os números'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '961 111 222');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('961 111 222'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('nav-principal')));
      await tester.pumpAndSettle();
      expect(find.text('Ligar a Maria'), findsOneWidget);
    });
  });

  group('Telemóveis ligados', () {
    testWidgets('mostra o que o telemóvel reportou e desliga-o', (
      tester,
    ) async {
      final m = await abrir(tester);
      m.repo.telemoveis['maria'] = [
        Dispositivo(
          id: 'd1',
          nome: 'Samsung Galaxy A14',
          ligadoDesde: DateTime(2026, 11, 18),
          ultimaLigacao: agora.subtract(const Duration(minutes: 5)),
          alarmesAgendados: 14,
          permissoes: const PermissoesAlarme(
            alarmesExatos: true,
            bateriaSemLimites: false,
            ecraBloqueado: true,
          ),
        ),
      ];
      await entrar(tester);
      await irParaMais(tester);
      await tester.tap(find.text('Telemóveis ligados'));
      await tester.pumpAndSettle();
      expect(find.text('Telemóveis de Maria'), findsOneWidget);
      expect(find.text('Samsung Galaxy A14'), findsOneWidget);
      expect(find.text('há 5 minutos'), findsOneWidget);
      expect(find.text('14 próximos'), findsOneWidget);
      expect(find.text('1 em falta'), findsOneWidget);
      await tester.tap(find.text('Desligar este telemóvel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Desligar'));
      await tester.pumpAndSettle();
      expect(m.repo.desligados, ['d1']);
      expect(find.text('Samsung Galaxy A14'), findsNothing);
      expect(find.text('Ligar o telemóvel de Maria'), findsOneWidget);
    });

    test('"há quanto tempo" em palavras', () {
      final agora = DateTime(2026, 11, 21, 12);
      expect(haQuantoTempo(agora, agora), 'agora mesmo');
      expect(
        haQuantoTempo(agora.subtract(const Duration(minutes: 1)), agora),
        'há 1 minuto',
      );
      expect(
        haQuantoTempo(agora.subtract(const Duration(hours: 3)), agora),
        'há 3 horas',
      );
      expect(
        haQuantoTempo(DateTime(2026, 11, 20, 8, 12), agora),
        'ontem, 08:12',
      );
    });
  });

  group('A sua conta', () {
    testWidgets('exporta os dados para um ficheiro', (tester) async {
      final m = await abrir(tester);
      await entrar(tester);
      await irParaMais(tester);
      await tester.tap(find.text('A sua conta · Cuidador'));
      await tester.pumpAndSettle();
      expect(find.text('A sua conta'), findsOneWidget);
      await tester.tap(find.text('Exportar os meus dados'));
      await tester.pumpAndSettle();
      expect(m.ficheiros, ['amparo-dados-2026-11-21.json']);
      expect(
        find.text('Os seus dados foram guardados num ficheiro.'),
        findsOneWidget,
      );
    });

    testWidgets('apagar pede a palavra-passe e volta ao Entrar', (
      tester,
    ) async {
      final m = await abrir(tester);
      await entrar(tester);
      await irParaMais(tester);
      await tester.tap(find.text('A sua conta · Cuidador'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apagar a conta'));
      await tester.pumpAndSettle();
      expect(find.text('Apagar a conta?'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'errada-errada');
      await tester.tap(find.text('Apagar a conta'));
      await tester.pumpAndSettle();
      expect(find.text('A palavra-passe não está certa.'), findsOneWidget);
      expect(m.auth.contaApagada, isFalse);
      await tester.enterText(find.byType(TextField), 'uma-senha-segura-123');
      await tester.tap(find.text('Apagar a conta'));
      await tester.pumpAndSettle();
      expect(m.auth.contaApagada, isTrue);
      expect(find.text('A sua conta foi apagada.'), findsOneWidget);
      expect(find.text('Esqueci-me da palavra-passe'), findsOneWidget);
      expect(m.alarmes.cancelamentosTotais, 1);
    });

    testWidgets('uma conta só da Apple ou da Google não pede palavra-passe', (
      tester,
    ) async {
      final m = await abrir(tester);
      m.auth.temSenha = false;
      await entrar(tester);
      await irParaMais(tester);
      await tester.tap(find.text('A sua conta · Cuidador'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apagar a conta'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('Apagar a conta'));
      await tester.pumpAndSettle();
      expect(m.auth.contaApagada, isTrue);
    });
  });

  group('Push', () {
    test('o aviso ao cuidador nasce no telemóvel, sem nada clínico', () {
      expect(
        textoDoAlerta('toma_nao_confirmada', 'Maria'),
        'Maria ainda não confirmou uma toma.',
      );
      expect(
        textoDoAlerta('toma_feita', 'Maria'),
        'Foi marcada uma toma de Maria.',
      );
      expect(
        textoDoAlerta('receita_a_acabar', 'Maria'),
        'Uma receita de Maria está a acabar.',
      );
      expect(textoDoAlerta(null, 'Maria'), 'Há um aviso novo sobre Maria.');
    });

    test('só aceita mensagens com tipo e perfil', () {
      expect(MensagemPush.deDados({'tipo': 'sync'}), isNull);
      final m = MensagemPush.deDados({
        'tipo': 'lembrete',
        'perfil': 'maria',
        'toma': 't3',
      })!;
      expect(m.toma, 't3');
      expect(m.tocada, isFalse);
    });
  });
}

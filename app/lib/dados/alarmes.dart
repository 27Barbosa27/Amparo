// Alarmes locais das tomas (docs/plano.md secção 3.3): disparam no telemóvel independentemente
// da rede e do servidor, com "Adiar 10 minutos" a funcionar mesmo com a app fechada. Validado
// em dispositivo Android real (spike em lib/spike_alarme_main.dart) antes desta integração.
//
// Segue o padrão de `dados/google.dart` e `dados/push.dart`: uma interface, uma implementação real
// (Android) e uma nula (web, testes e, por agora, o iPhone), escolhidas em [criarServicoAlarmes].

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../dominio/modelos.dart';

const _canalId = 'amparo_alarmes_tomas';
const _canalAvisos = 'amparo_avisos';
const _acaoTomei = 'tomei';
const _acaoAdiar = 'adiar10';

/// Quanto o "Adiar" empurra o alarme.
const adiamento = Duration(minutes: 10);

/// Converte o `id` (string/uuid) da toma num `int` estável para o plugin de notificações.
int idNotificacaoDaToma(String tomaId) => tomaId.hashCode & 0x7fffffff;

/// O que cada alarme leva consigo (no payload da notificação): chega para mostrar o ecrã do alarme e
/// registar a toma sem ir primeiro ao servidor. Só fica neste telemóvel.
class AlarmeToma {
  const AlarmeToma({
    required this.tomaId,
    required this.perfilId,
    required this.medicamento,
    required this.dose,
    required this.hora,
  });

  final String tomaId;
  final String perfilId;
  final String medicamento;
  final String dose;

  /// A hora prevista da toma (não a do adiamento).
  final DateTime hora;

  factory AlarmeToma.daToma(String perfilId, Toma t) => AlarmeToma(
    tomaId: t.id,
    perfilId: perfilId,
    medicamento: t.medicamento,
    dose: t.dose,
    hora: t.agendada,
  );

  String paraPayload() => jsonEncode({
    't': tomaId,
    'p': perfilId,
    'm': medicamento,
    'd': dose,
    'h': hora.toUtc().toIso8601String(),
  });

  /// Nulo se o payload não é de um alarme (por exemplo, um aviso do push ou um alarme antigo do spike).
  static AlarmeToma? doPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final j = jsonDecode(payload);
      if (j is! Map || j['t'] is! String || j['p'] is! String) return null;
      return AlarmeToma(
        tomaId: j['t'] as String,
        perfilId: j['p'] as String,
        medicamento: j['m'] as String? ?? 'Medicação',
        dose: j['d'] as String? ?? '',
        hora: DateTime.parse(j['h'] as String).toLocal(),
      );
    } catch (_) {
      return null;
    }
  }
}

enum AcaoAlarme {
  /// Tocou no alarme (ou o alarme abriu a app por cima do ecrã bloqueado): mostrar o ecrã do alarme.
  abrir,

  /// Tocou em "Tomei" na notificação: registar a toma.
  tomei,

  /// Tocou num aviso ao cuidador: abrir o perfil.
  aviso,
}

class RespostaAlarme {
  const RespostaAlarme(this.acao, {this.alarme, this.perfilId});
  final AcaoAlarme acao;
  final AlarmeToma? alarme;

  /// Só nos avisos ([AcaoAlarme.aviso]).
  final String? perfilId;

  static RespostaAlarme? de(NotificationResponse r) {
    final payload = r.payload;
    if (payload != null && payload.startsWith('{"aviso":')) {
      try {
        return RespostaAlarme(
          AcaoAlarme.aviso,
          perfilId: (jsonDecode(payload) as Map)['aviso'] as String?,
        );
      } catch (_) {
        return null;
      }
    }
    final alarme = AlarmeToma.doPayload(payload);
    if (alarme == null) return null;
    return switch (r.actionId) {
      null || '' => RespostaAlarme(AcaoAlarme.abrir, alarme: alarme),
      _acaoTomei => RespostaAlarme(AcaoAlarme.tomei, alarme: alarme),
      _ => null, // "Adiar" trata-se em segundo plano, sem abrir a app
    };
  }
}

abstract class ServicoAlarmes {
  /// Este telemóvel tem alarmes locais (no Chrome e nos testes não há).
  bool get suportado;

  /// Prepara o canal de notificações. Chamar uma vez, no arranque da app.
  Future<void> iniciar();

  /// Substitui os alarmes deste perfil pelos das tomas pendentes dadas (reagendar é sempre "tudo outra
  /// vez": mais simples e seguro do que comparar). Os alarmes de outros perfis ficam como estavam.
  Future<void> agendarParaTomas(String perfilId, List<Toma> tomas);

  /// Ao sair da conta ou desligar o telemóvel: nenhum alarme de ninguém deve continuar agendado.
  Future<void> cancelarTodos();

  /// Os toques nas notificações enquanto a app está aberta (ou em segundo plano).
  Stream<RespostaAlarme> get respostas;

  /// Se foi uma notificação que abriu a app (incluindo o alarme por cima do ecrã bloqueado).
  Future<RespostaAlarme?> respostaDoArranque();

  /// "Adiar 10 min" dentro da app: volta a tocar daqui a [adiamento]. Devolve a hora do novo alarme.
  Future<DateTime> adiar(AlarmeToma alarme);

  /// Quantos alarmes estão agendados neste telemóvel (para "Telemóveis ligados").
  Future<int> agendados();

  /// O estado das três permissões de "Alarmes fiáveis".
  Future<PermissoesAlarme> permissoes();

  /// Abre, uma de cada vez, as definições das permissões que faltam. Devolve o estado no fim.
  Future<PermissoesAlarme> pedirPermissoes();

  /// Uma notificação simples (os avisos ao cuidador que chegam pelo push com a app aberta).
  Future<void> mostrarAviso(String perfilId, String texto);

  /// O alarme pode abrir a app por cima do ecrã bloqueado; ao fechar o ecrã do alarme volta a não poder.
  Future<void> mostrarSobreBloqueio(bool sim);
}

class ServicoAlarmesNulo implements ServicoAlarmes {
  const ServicoAlarmesNulo();
  @override
  bool get suportado => false;
  @override
  Future<void> iniciar() async {}
  @override
  Future<void> agendarParaTomas(String perfilId, List<Toma> tomas) async {}
  @override
  Future<void> cancelarTodos() async {}
  @override
  Stream<RespostaAlarme> get respostas => const Stream.empty();
  @override
  Future<RespostaAlarme?> respostaDoArranque() async => null;
  @override
  Future<DateTime> adiar(AlarmeToma alarme) async =>
      DateTime.now().add(adiamento);
  @override
  Future<int> agendados() async => 0;
  @override
  Future<PermissoesAlarme> permissoes() async => PermissoesAlarme.todas;
  @override
  Future<PermissoesAlarme> pedirPermissoes() async => PermissoesAlarme.todas;
  @override
  Future<void> mostrarAviso(String perfilId, String texto) async {}
  @override
  Future<void> mostrarSobreBloqueio(bool sim) async {}
}

/// Chamado pelo sistema quando se toca numa ação da notificação com a app fechada. Função de topo
/// com `@pragma('vm:entry-point')`: sem isto o Android não consegue invocar o isolate em segundo plano.
@pragma('vm:entry-point')
void aoResponderAlarmeEmSegundoPlano(NotificationResponse resposta) {
  if (resposta.actionId != _acaoAdiar) return;
  final alarme = AlarmeToma.doPayload(resposta.payload);
  if (alarme == null) return;
  _agendarAdiado(FlutterLocalNotificationsPlugin(), alarme);
}

Future<DateTime> _agendarAdiado(
  FlutterLocalNotificationsPlugin notificacoes,
  AlarmeToma alarme,
) async {
  final quando = tz.TZDateTime.now(tz.UTC).add(adiamento);
  await notificacoes.zonedSchedule(
    id: idNotificacaoDaToma(alarme.tomaId),
    title: 'Amparo — alarme adiado',
    body: alarme.dose.isEmpty
        ? alarme.medicamento
        : '${alarme.medicamento} · ${alarme.dose}',
    scheduledDate: quando,
    notificationDetails: _detalhesAlarme,
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    payload: alarme.paraPayload(),
  );
  return quando.toLocal();
}

const _detalhesAlarme = NotificationDetails(
  android: AndroidNotificationDetails(
    _canalId,
    'Alarmes de medicação',
    channelDescription: 'Avisa quando é hora de tomar uma medicação.',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.alarm,
    fullScreenIntent: true,
    playSound: true,
    actions: [
      // "Tomei" abre a app: o registo vai ao servidor com a sessão deste telemóvel.
      AndroidNotificationAction(_acaoTomei, 'Tomei', showsUserInterface: true),
      AndroidNotificationAction(_acaoAdiar, 'Adiar 10 minutos'),
    ],
  ),
);

const _detalhesAviso = NotificationDetails(
  android: AndroidNotificationDetails(
    _canalAvisos,
    'Avisos ao cuidador',
    channelDescription:
        'Tomas por confirmar, tomas feitas e receitas a acabar.',
    importance: Importance.high,
    priority: Priority.high,
  ),
);

class ServicoAlarmesAndroid implements ServicoAlarmes {
  ServicoAlarmesAndroid();

  final _notificacoes = FlutterLocalNotificationsPlugin();
  final _respostas = StreamController<RespostaAlarme>.broadcast();

  /// O que o plugin não dá: se o alarme pode aparecer por cima do ecrã bloqueado (MainActivity.kt).
  static const _canalNativo = MethodChannel('pt.amparo/alarmes');
  bool _pronto = false;

  AndroidFlutterLocalNotificationsPlugin? get _android => _notificacoes
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  bool get suportado => true;

  @override
  Future<void> iniciar() async {
    if (_pronto) return;
    tz_data.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation(await _fusoDoAparelho()));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _canalId,
        'Alarmes de medicação',
        description: 'Avisa quando é hora de tomar uma medicação.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );
    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _canalAvisos,
        'Avisos ao cuidador',
        description: 'Tomas por confirmar, tomas feitas e receitas a acabar.',
        importance: Importance.high,
      ),
    );

    await _notificacoes.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (r) {
        if (r.actionId == _acaoAdiar) {
          final alarme = AlarmeToma.doPayload(r.payload);
          if (alarme != null) _agendarAdiado(_notificacoes, alarme);
          return;
        }
        final resposta = RespostaAlarme.de(r);
        if (resposta != null) _respostas.add(resposta);
      },
      onDidReceiveBackgroundNotificationResponse:
          aoResponderAlarmeEmSegundoPlano,
    );
    _pronto = true;
  }

  /// TODO: ler o fuso real do perfil/aparelho (ver `timezone` + `flutter_timezone` ou a `timezone`
  /// da receita vinda da API). Por agora assume Portugal, como o resto da app em desenvolvimento.
  Future<String> _fusoDoAparelho() async => 'Europe/Lisbon';

  @override
  Stream<RespostaAlarme> get respostas => _respostas.stream;

  @override
  Future<RespostaAlarme?> respostaDoArranque() async {
    await iniciar();
    final d = await _notificacoes.getNotificationAppLaunchDetails();
    final r = d?.notificationResponse;
    if (d == null || !d.didNotificationLaunchApp || r == null) return null;
    return RespostaAlarme.de(r);
  }

  @override
  Future<void> agendarParaTomas(String perfilId, List<Toma> tomas) async {
    await iniciar();
    for (final p in await _notificacoes.pendingNotificationRequests()) {
      final alarme = AlarmeToma.doPayload(p.payload);
      // Os alarmes sem payload reconhecível (do spike) também saem: seriam de um perfil qualquer.
      if (alarme == null || alarme.perfilId == perfilId) {
        await _notificacoes.cancel(id: p.id);
      }
    }
    final agora = DateTime.now();
    final pendentes =
        tomas
            .where(
              (t) =>
                  t.estado == EstadoToma.pendente && t.agendada.isAfter(agora),
            )
            .toList()
          ..sort((a, b) => a.agendada.compareTo(b.agendada));
    // Limite por segurança (ver docs/plano.md 3.3: ~64 pendentes no iOS); nesta integração inicial
    // só se agenda a partir das tomas já carregadas no ecrã "Hoje" (de um dia), por isso raramente se atinge.
    for (final t in pendentes.take(50)) {
      await _agendar(AlarmeToma.daToma(perfilId, t));
    }
  }

  Future<void> _agendar(AlarmeToma a) async {
    final quando = tz.TZDateTime.from(a.hora, tz.local);
    if (quando.isBefore(tz.TZDateTime.now(tz.local))) return;
    await _notificacoes.zonedSchedule(
      id: idNotificacaoDaToma(a.tomaId),
      title: 'Amparo — hora do ${a.medicamento}',
      body: a.dose,
      scheduledDate: quando,
      notificationDetails: _detalhesAlarme,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: a.paraPayload(),
    );
  }

  @override
  Future<void> cancelarTodos() async {
    await iniciar();
    await _notificacoes.cancelAll();
  }

  @override
  Future<DateTime> adiar(AlarmeToma alarme) async {
    await iniciar();
    return _agendarAdiado(_notificacoes, alarme);
  }

  @override
  Future<int> agendados() async {
    await iniciar();
    final pendentes = await _notificacoes.pendingNotificationRequests();
    return pendentes
        .where((p) => AlarmeToma.doPayload(p.payload) != null)
        .length;
  }

  @override
  Future<PermissoesAlarme> permissoes() async {
    await iniciar();
    final android = _android;
    final exatos = await android?.canScheduleExactNotifications() ?? true;
    final notificacoes = await android?.areNotificationsEnabled() ?? true;
    bool ecra;
    try {
      ecra = await _canalNativo.invokeMethod<bool>('podeEcraInteiro') ?? true;
    } on PlatformException {
      ecra = true;
    } on MissingPluginException {
      ecra = true;
    }
    return PermissoesAlarme(
      alarmesExatos: exatos && notificacoes,
      bateriaSemLimites: await Permission.ignoreBatteryOptimizations.isGranted,
      ecraBloqueado: ecra,
    );
  }

  @override
  Future<PermissoesAlarme> pedirPermissoes() async {
    var p = await permissoes();
    final android = _android;
    // Cada pedido abre o pedido do sistema (ou as definições) e só volta quando a pessoa regressa à app.
    if (!p.alarmesExatos) {
      await android?.requestNotificationsPermission();
      await android?.requestExactAlarmsPermission();
    }
    if (!p.bateriaSemLimites) {
      await Permission.ignoreBatteryOptimizations.request();
    }
    if (!p.ecraBloqueado) {
      await android?.requestFullScreenIntentPermission();
    }
    p = await permissoes();
    return p;
  }

  @override
  Future<void> mostrarAviso(String perfilId, String texto) async {
    await iniciar();
    await _notificacoes.show(
      id: perfilId.hashCode & 0x7fffffff,
      title: 'Amparo',
      body: texto,
      notificationDetails: _detalhesAviso,
      payload: jsonEncode({'aviso': perfilId}),
    );
  }

  @override
  Future<void> mostrarSobreBloqueio(bool sim) async {
    try {
      await _canalNativo.invokeMethod<void>('sobreBloqueio', sim);
    } on PlatformException {
      // sem efeito: o pior que acontece é o alarme pedir para desbloquear
    } on MissingPluginException {
      // idem
    }
  }
}

/// No Chrome (onde corre o dia a dia de desenvolvimento via `scripts/chrome.ps1`) e nos computadores os
/// alarmes locais não existem: a `ServicoAlarmesNulo` não faz nada e a app continua a funcionar. No
/// iPhone também, por agora: falta o teste do spike num iPhone real (docs/plano.md, ponto 1).
ServicoAlarmes criarServicoAlarmes() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
    ? ServicoAlarmesAndroid()
    : const ServicoAlarmesNulo();

// Alarmes locais das tomas (docs/plano.md secção 3.3): disparam no telemóvel independentemente
// da rede e do servidor, com "Adiar 10 minutos" a funcionar mesmo com a app fechada. Validado
// em dispositivo Android real (spike em lib/spike_alarme_main.dart) antes desta integração.
//
// Segue o padrão de `dados/google.dart` e `dados/push.dart`: uma interface, uma implementação real
// (Android/iOS) e uma nula (web e testes), escolhidas por `kIsWeb`.

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../dominio/modelos.dart';

const _canalId = 'amparo_alarmes_tomas';
const _acaoTomei = 'tomei';
const _acaoAdiar = 'adiar10';

/// Converte o `id` (string/uuid) da toma num `int` estável para o plugin de notificações.
int idNotificacaoDaToma(String tomaId) => tomaId.hashCode & 0x7fffffff;

abstract class ServicoAlarmes {
  /// Prepara o canal de notificações. Chamar uma vez, no arranque da app.
  Future<void> iniciar();

  /// Substitui todos os alarmes agendados pelos das tomas pendentes dadas (reagendar é sempre
  /// "tudo outra vez": mais simples e seguro do que comparar o que já estava agendado).
  Future<void> agendarParaTomas(List<Toma> tomas);

  /// Antes de sair da conta ou mudar de perfil: nenhum alarme de outra pessoa deve continuar agendado.
  Future<void> cancelarTodos();
}

class ServicoAlarmesNulo implements ServicoAlarmes {
  const ServicoAlarmesNulo();
  @override
  Future<void> iniciar() async {}
  @override
  Future<void> agendarParaTomas(List<Toma> tomas) async {}
  @override
  Future<void> cancelarTodos() async {}
}

/// Chamado pelo sistema quando se toca numa ação da notificação com a app fechada. Função de topo
/// com `@pragma('vm:entry-point')`: sem isto o Android não consegue invocar o isolate em segundo plano.
@pragma('vm:entry-point')
void aoResponderAlarmeEmSegundoPlano(NotificationResponse resposta) {
  _tratarResposta(resposta);
}

void _tratarResposta(NotificationResponse resposta) {
  if (resposta.actionId != _acaoAdiar) return;
  final payload = resposta.payload ?? '';
  final partes = payload.split('|'); // "<medicamento>|<dose>"
  final medicamento = partes.isNotEmpty ? partes[0] : 'Medicação';
  final dose = partes.length > 1 ? partes[1] : '';
  final notificacoes = FlutterLocalNotificationsPlugin();
  final quando = tz.TZDateTime.now(tz.local).add(const Duration(minutes: 10));
  notificacoes.zonedSchedule(
    id: resposta.id ?? 0,
    title: 'Amparo — alarme adiado',
    body: dose.isEmpty ? medicamento : '$medicamento · $dose',
    scheduledDate: quando,
    notificationDetails: _detalhesNotificacao(payload: payload),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
  );
}

NotificationDetails _detalhesNotificacao({required String payload}) =>
    const NotificationDetails(
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
          AndroidNotificationAction(_acaoTomei, 'Tomei', cancelNotification: true),
          AndroidNotificationAction(_acaoAdiar, 'Adiar 10 minutos', cancelNotification: true),
        ],
      ),
    );

class ServicoAlarmesAndroid implements ServicoAlarmes {
  ServicoAlarmesAndroid();

  final _notificacoes = FlutterLocalNotificationsPlugin();
  bool _pronto = false;

  @override
  Future<void> iniciar() async {
    if (_pronto) return;
    tz_data.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation(await _fusoDoAparelho()));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    const canal = AndroidNotificationChannel(
      _canalId,
      'Alarmes de medicação',
      description: 'Avisa quando é hora de tomar uma medicação.',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await _notificacoes
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(canal);

    await _notificacoes.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: _tratarResposta,
      onDidReceiveBackgroundNotificationResponse: aoResponderAlarmeEmSegundoPlano,
    );
    _pronto = true;
  }

  /// TODO: ler o fuso real do perfil/aparelho (ver `timezone` + `flutter_timezone` ou a `timezone`
  /// da receita vinda da API). Por agora assume Portugal, como o resto da app em desenvolvimento.
  Future<String> _fusoDoAparelho() async => 'Europe/Lisbon';

  @override
  Future<void> agendarParaTomas(List<Toma> tomas) async {
    await iniciar();
    await _notificacoes.cancelAll();
    final agora = DateTime.now();
    final pendentes =
        tomas
            .where((t) => t.estado == EstadoToma.pendente && t.agendada.isAfter(agora))
            .toList()
          ..sort((a, b) => a.agendada.compareTo(b.agendada));
    // Limite por segurança (ver docs/plano.md 3.3: ~64 pendentes no iOS); nesta integração inicial
    // só se agenda a partir das tomas já carregadas no ecrã "Hoje" (de um dia), por isso raramente se atinge.
    for (final t in pendentes.take(50)) {
      await _agendar(t);
    }
  }

  Future<void> _agendar(Toma t) async {
    final quando = tz.TZDateTime.from(t.agendada, tz.local);
    if (quando.isBefore(tz.TZDateTime.now(tz.local))) return;
    await _notificacoes.zonedSchedule(
      id: idNotificacaoDaToma(t.id),
      title: 'Amparo — hora do ${t.medicamento}',
      body: t.dose,
      scheduledDate: quando,
      notificationDetails: _detalhesNotificacao(payload: '${t.medicamento}|${t.dose}'),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: '${t.medicamento}|${t.dose}',
    );
  }

  @override
  Future<void> cancelarTodos() => _notificacoes.cancelAll();
}

/// `kIsWeb` escolhe a implementação, tal como em `dados/google.dart`. No Chrome (onde corre o
/// dia a dia de desenvolvimento via `scripts/chrome.ps1`) os alarmes locais não existem: a
/// `ServicoAlarmesNulo` não faz nada e a app continua a funcionar normalmente.
ServicoAlarmes criarServicoAlarmes() =>
    kIsWeb ? const ServicoAlarmesNulo() : ServicoAlarmesAndroid();

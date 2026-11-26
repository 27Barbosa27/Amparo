// SPIKE TÉCNICO (docs/plano.md secção 3.3 e 6, ponto 1): alarme exato com snooze em
// background, para decidir se o plano de alarmes locais é viável antes de construir
// o resto da app em cima dele. Ficheiro isolado, não entra no routing do produto nem
// é um ecrã desenhado — é só para correr no telemóvel e responder às perguntas:
//
//   1. Um alarme agendado dispara à hora exata, com o som a tocar, mesmo com a app
//      completamente fechada (forçada a parar, não só em segundo plano)?
//   2. O botão "Adiar 10 minutos" na notificação funciona sem abrir a app, e reagenda
//      o alarme para 10 minutos depois?
//   3. Isto sobrevive à otimização de bateria do Android (sem o utilizador ter de
//      desativar nada manualmente, e com ela desativada)?
//
// Correr com: flutter run -t lib/spike_alarme_main.dart -d <id-do-telemóvel>
// Apagar este ficheiro (e os plugins, se o resultado for negativo) depois do spike.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

const _canalId = 'amparo_spike_alarmes';
const _acaoAdiar = 'adiar10';
const _acaoTomei = 'tomei';

final _notificacoes = FlutterLocalNotificationsPlugin();

/// Chamado pelo sistema quando se toca numa ação da notificação (ex.: "Adiar 10 min")
/// com a app fechada. Tem de ser uma função de topo com este `@pragma`, senão o Android
/// não consegue invocar o isolate em segundo plano.
@pragma('vm:entry-point')
void aoResponderEmSegundoPlano(NotificationResponse resposta) {
  _tratarResposta(resposta);
}

void _tratarResposta(NotificationResponse resposta) {
  if (resposta.actionId == _acaoAdiar) {
    _agendarAlarme(
      id: resposta.id ?? 0,
      daquiA: const Duration(minutes: 10),
      titulo: 'Amparo — alarme adiado',
      corpo: 'Adiado 10 minutos a partir de ${DateTime.now()}',
    );
  }
}

Future<void> _iniciarNotificacoes() async {
  tz_data.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation(await _fusoDoAparelho()));

  const canal = AndroidNotificationChannel(
    _canalId,
    'Alarmes de medicação (spike)',
    description: 'Canal de teste para o spike técnico de alarmes.',
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
    onDidReceiveBackgroundNotificationResponse: aoResponderEmSegundoPlano,
  );
}

/// `timezone` precisa do nome IANA; no dispositivo real isto vem do sistema.
/// Para o spike basta um fuso fixo de Portugal — não é o que importa testar aqui.
Future<String> _fusoDoAparelho() async => 'Europe/Lisbon';

Future<void> _agendarAlarme({
  required int id,
  required Duration daquiA,
  required String titulo,
  required String corpo,
}) async {
  final quando = tz.TZDateTime.now(tz.local).add(daquiA);
  await _notificacoes.zonedSchedule(
    id: id,
    title: titulo,
    body: corpo,
    scheduledDate: quando,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        _canalId,
        'Alarmes de medicação (spike)',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        playSound: true,
        ongoing: false,
        actions: [
          AndroidNotificationAction(_acaoTomei, 'Tomei', cancelNotification: true),
          AndroidNotificationAction(_acaoAdiar, 'Adiar 10 minutos', cancelNotification: true),
        ],
      ),
    ),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _iniciarNotificacoes();
  runApp(const _AppSpike());
}

class _AppSpike extends StatefulWidget {
  const _AppSpike();
  @override
  State<_AppSpike> createState() => _EstadoAppSpike();
}

class _EstadoAppSpike extends State<_AppSpike> {
  String _estado = '';
  Timer? _relogio;

  @override
  void initState() {
    super.initState();
    _relogio = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _relogio?.cancel();
    super.dispose();
  }

  Future<void> _pedirPermissoes() async {
    final notificacao = await Permission.notification.request();
    final alarmeExato = await Permission.scheduleExactAlarm.request();
    setState(() {
      _estado =
          'Notificações: ${notificacao.name}\nAlarme exato: ${alarmeExato.name}';
    });
  }

  Future<void> _agendarTeste(Duration daquiA) async {
    final id = DateTime.now().millisecondsSinceEpoch.remainder(100000);
    await _agendarAlarme(
      id: id,
      daquiA: daquiA,
      titulo: 'Amparo — hora do Paracetamol',
      corpo: 'Agendado para ${DateTime.now().add(daquiA)}',
    );
    setState(() => _estado = 'Agendado #$id para dentro de $daquiA.\n'
        'Agora força-se a parar a app (Definições > Apps > Amparo > Forçar paragem) '
        'e espera-se para ver se o alarme toca.');
  }

  Future<void> _verPendentes() async {
    final pendentes = await _notificacoes.pendingNotificationRequests();
    setState(() {
      _estado = pendentes.isEmpty
          ? 'Sem alarmes pendentes.'
          : pendentes.map((p) => '#${p.id} ${p.title}').join('\n');
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Spike: alarmes Amparo')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Agora: ${DateTime.now()}'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _pedirPermissoes,
                child: const Text('1. Pedir permissões'),
              ),
              ElevatedButton(
                onPressed: () => openAppSettings(),
                child: const Text('Abrir definições da app (bateria/alarmes)'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _agendarTeste(const Duration(seconds: 20)),
                child: const Text('2. Agendar alarme em 20 segundos'),
              ),
              ElevatedButton(
                onPressed: () => _agendarTeste(const Duration(minutes: 2)),
                child: const Text('2b. Agendar alarme em 2 minutos (para forçar parar a app)'),
              ),
              ElevatedButton(
                onPressed: _verPendentes,
                child: const Text('3. Ver alarmes pendentes'),
              ),
              const SizedBox(height: 16),
              Text(_estado),
            ],
          ),
        ),
      ),
    );
  }
}

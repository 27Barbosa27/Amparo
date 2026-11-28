import 'dart:async';

import 'package:amparo/dados/alarmes.dart';
import 'package:amparo/dominio/modelos.dart';

/// Alarmes falsos, só para os testes: um telemóvel "com alarmes", com as permissões que o teste quiser.
class AlarmesMemoria implements ServicoAlarmes {
  AlarmesMemoria({this.estado = PermissoesAlarme.todas});

  /// O estado das permissões; [pedirPermissoes] passa-o a [depoisDePedir].
  PermissoesAlarme estado;
  PermissoesAlarme depoisDePedir = PermissoesAlarme.todas;
  int pedidos = 0;

  /// Os alarmes agendados, por perfil.
  final agendados_ = <String, List<String>>{};
  final adiados = <String>[];
  final avisos = <String>[];
  final sobreBloqueio = <bool>[];
  int cancelamentosTotais = 0;
  RespostaAlarme? arranque;
  final _respostas = StreamController<RespostaAlarme>.broadcast();

  /// Simula um toque numa notificação com a app aberta.
  void responder(RespostaAlarme r) => _respostas.add(r);

  @override
  bool get suportado => true;
  @override
  Future<void> iniciar() async {}

  @override
  Future<void> agendarParaTomas(String perfilId, List<Toma> tomas) async {
    agendados_[perfilId] = [
      for (final t in tomas)
        if (t.estado == EstadoToma.pendente) t.id,
    ];
  }

  @override
  Future<void> cancelarTodos() async {
    cancelamentosTotais++;
    agendados_.clear();
  }

  @override
  Stream<RespostaAlarme> get respostas => _respostas.stream;

  @override
  Future<RespostaAlarme?> respostaDoArranque() async => arranque;

  @override
  Future<DateTime> adiar(AlarmeToma alarme) async {
    adiados.add(alarme.tomaId);
    return alarme.hora.add(adiamento);
  }

  @override
  Future<int> agendados() async =>
      agendados_.values.fold<int>(0, (n, l) => n + l.length);

  @override
  Future<PermissoesAlarme> permissoes() async => estado;

  @override
  Future<PermissoesAlarme> pedirPermissoes() async {
    pedidos++;
    estado = depoisDePedir;
    return estado;
  }

  @override
  Future<void> mostrarAviso(String perfilId, String texto) async =>
      avisos.add(texto);

  @override
  Future<void> mostrarSobreBloqueio(bool sim) async => sobreBloqueio.add(sim);
}

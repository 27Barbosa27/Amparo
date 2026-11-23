import 'dart:math';

import '../dominio/modelos.dart';
import 'api.dart';
import 'repositorio.dart';

/// O repositório que fala com o backend. Os códigos de erro da API passam a [RegistoNaoPermitido]
/// quando são recusas de negócio (já registada, passou o minuto, hora inválida).
class RepositorioApi implements Repositorio {
  RepositorioApi(this._api);
  final ClienteApi _api;
  final _aleatorio = Random.secure();

  static const _recusas = {
    'toma_ja_registada',
    'desfazer_expirado',
    'hora_invalida',
    'toma_nao_encontrada',
  };

  String _chave() => List.generate(
    16,
    (_) => _aleatorio.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  Future<T> _traduzir<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on ErroApi catch (e) {
      if (_recusas.contains(e.codigo)) throw RegistoNaoPermitido(e.codigo);
      rethrow;
    }
  }

  DateTime _data(Object? v) => DateTime.parse(v as String).toLocal();

  Toma _toma(Map<String, dynamic> j) {
    final estado = EstadoToma.values.byName(j['estado'] as String);
    final registada =
        estado == EstadoToma.tomada || estado == EstadoToma.saltada;
    return Toma(
      id: j['id'] as String,
      medicamento: (j['medicamento'] as Map)['nome'] as String,
      dose: j['dose'] as String,
      agendada: _data(j['agendadaUtc']),
      estado: estado,
      tomadaEm: j['tomadaEmUtc'] == null ? null : _data(j['tomadaEmUtc']),
      registadaPor: j['registadaPor'] as String?,
      // O servidor devolve a hora da última alteração: serve para a janela do "desfazer 1 min".
      registadaEm: registada ? _data(j['atualizadoEm']) : null,
    );
  }

  @override
  Future<List<Perfil>> perfis() async {
    final j = await _api.pedir('GET', '/profiles');
    return [
      for (final p in (j!['perfis'] as List))
        Perfil(id: p['id'] as String, nome: p['pseudonimo'] as String),
    ];
  }

  Future<List<Toma>> _entre(String perfilId, DateTime de, DateTime ate) async {
    final j = await _api.pedir(
      'GET',
      '/tomas',
      perfilId: perfilId,
      query: {
        'de': de.toUtc().toIso8601String(),
        'ate': ate.toUtc().toIso8601String(),
      },
    );
    return [
      for (final t in (j!['tomas'] as List)) _toma(t as Map<String, dynamic>),
    ];
  }

  @override
  Future<List<Toma>> tomasDeHoje(String perfilId, DateTime agora) {
    final inicio = DateTime(agora.year, agora.month, agora.day);
    return _entre(
      perfilId,
      inicio,
      DateTime(agora.year, agora.month, agora.day + 1),
    );
  }

  @override
  Future<Toma> marcarTomada(
    String perfilId,
    String tomaId,
    DateTime agora, {
    DateTime? hora,
    String? porCuidador,
  }) => _traduzir(() async {
    final j = await _api.pedir(
      'POST',
      '/tomas/$tomaId/registo',
      perfilId: perfilId,
      corpo: {
        if (hora != null) 'tomadaEmUtc': hora.toUtc().toIso8601String(),
        'idempotencyKey': _chave(),
      },
    );
    return _recarregar(perfilId, tomaId, j);
  });

  @override
  Future<Toma> saltar(
    String perfilId,
    String tomaId,
    DateTime agora, {
    String? porCuidador,
  }) => _traduzir(() async {
    final j = await _api.pedir(
      'POST',
      '/tomas/$tomaId/saltar',
      perfilId: perfilId,
      corpo: {'idempotencyKey': _chave()},
    );
    return _recarregar(perfilId, tomaId, j);
  });

  @override
  Future<Toma> desfazer(String perfilId, String tomaId, DateTime agora) =>
      _traduzir(() async {
        final j = await _api.pedir(
          'POST',
          '/tomas/$tomaId/desfazer',
          perfilId: perfilId,
        );
        return _recarregar(perfilId, tomaId, j);
      });

  /// As ações devolvem só o estado novo; para ter a toma completa (hora, quem registou) volta a lê-la.
  Future<Toma> _recarregar(
    String perfilId,
    String tomaId,
    Map<String, dynamic>? _,
  ) async {
    final j = await _api.pedir('GET', '/tomas/$tomaId', perfilId: perfilId);
    return _toma(j!['toma'] as Map<String, dynamic>);
  }

  @override
  Future<List<DiaAdesao>> ultimos7Dias(String perfilId, DateTime agora) async {
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final inicio = hoje.subtract(const Duration(days: 6));
    final tomas = await _entre(
      perfilId,
      inicio,
      DateTime(hoje.year, hoje.month, hoje.day + 1),
    );
    return [
      for (var i = 0; i < 7; i++)
        () {
          final dia = DateTime(inicio.year, inicio.month, inicio.day + i);
          if (dia == hoje) {
            return DiaAdesao(dia: dia, resultado: ResultadoDia.emCurso);
          }
          final doDia = tomas.where(
            (t) =>
                t.agendada.year == dia.year &&
                t.agendada.month == dia.month &&
                t.agendada.day == dia.day,
          );
          // Um dia só conta como "tudo tomado" se nenhuma toma ficou por fazer (pendente já passada, ou falhada).
          final esquecida = doDia.any(
            (t) =>
                t.estado == EstadoToma.falhada ||
                t.estado == EstadoToma.pendente,
          );
          return DiaAdesao(
            dia: dia,
            resultado: esquecida
                ? ResultadoDia.esquecida
                : ResultadoDia.tudoTomado,
          );
        }(),
    ];
  }

  @override
  Future<String?> nomeDoCuidador(String perfilId) async {
    try {
      final j = await _api.pedir('GET', '/contacto', perfilId: perfilId);
      final contactos = j?['contactos'] as List?;
      return contactos == null || contactos.isEmpty
          ? null
          : (contactos.first as Map)['nome'] as String?;
    } on ErroApi {
      return null; // um contacto em falta nunca impede de ver as tomas
    }
  }
}

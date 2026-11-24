import 'dart:math';

import '../dominio/modelos.dart';
import 'api.dart';
import 'corpo_receita.dart';
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
        Perfil(
          id: p['id'] as String,
          nome: p['pseudonimo'] as String,
          tamanhoTexto: TamanhoTexto.daApi(p['tamanhoTexto']),
        ),
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
  Future<List<Toma>> historico(String perfilId, DateTime de, DateTime ate) =>
      _entre(perfilId, de, ate);

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
          // Sem tomas nesse dia (a conta ou a receita ainda não existiam): não há nada a avaliar.
          if (doDia.isEmpty) {
            return DiaAdesao(dia: dia, resultado: ResultadoDia.semDados);
          }
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
  Future<CodigoLigacao> criarCodigoLigacao(String perfilId) async {
    final j = await _api.pedir('POST', '/profiles/$perfilId/pairing-codes');
    return CodigoLigacao(
      id: j!['id'] as String,
      codigo: j['codigo'] as String,
      expiraEm: _data(j['expiraEm']),
    );
  }

  @override
  Future<EstadoCodigo> estadoCodigo(String perfilId, String codigoId) async {
    final j = await _api.pedir(
      'GET',
      '/profiles/$perfilId/pairing-codes/$codigoId',
    );
    return switch (j!['estado']) {
      'ligado' => EstadoCodigo.ligado,
      'expirado' => EstadoCodigo.expirado,
      _ => EstadoCodigo.aEspera,
    };
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

  @override
  Future<Perfil> criarPessoa(NovaPessoa pessoa) async {
    final j = await _api.pedir(
      'POST',
      '/profiles',
      corpo: {
        'pseudonimo': pessoa.nome.trim(),
        'tamanhoTexto': switch (pessoa.tamanhoTexto) {
          TamanhoTexto.normal => 'normal',
          TamanhoTexto.grande => 'grande',
          TamanhoTexto.muitoGrande => 'muito_grande',
        },
        'alarmesEm': pessoa.alarmesEm == AlarmesEm.pessoa
            ? 'dispositivo_da_pessoa'
            : 'dispositivo_do_cuidador',
        // O cuidador declara que tem a autorização da pessoa ou do seu representante
        // (o ecrã obriga a marcar a caixa antes de criar).
        'autorizacaoDeclarada': true,
      },
    );
    final p = j!['perfil'] as Map<String, dynamic>;
    return Perfil(
      id: p['id'] as String,
      nome: p['pseudonimo'] as String,
      tamanhoTexto: pessoa.tamanhoTexto,
    );
  }

  String _numero(Object? v) =>
      v is num && v == v.roundToDouble() ? v.toInt().toString() : '$v';

  String _horario(Map<String, dynamic> h) => h['tipo'] == 'intervalo'
      ? 'De ${_numero(h['intervaloHoras'])} em ${_numero(h['intervaloHoras'])} horas'
      : (h['horasLocais'] as List).join(', ');

  @override
  Future<List<Receita>> receitas(String perfilId) async {
    final meds = await _api.pedir('GET', '/medicamentos', perfilId: perfilId);
    final nomes = {
      for (final m in (meds!['medicamentos'] as List))
        m['id'] as String: m['nome'] as String,
    };
    final j = await _api.pedir('GET', '/receitas', perfilId: perfilId);
    final agora = DateTime.now();
    return [
      for (final r in (j!['receitas'] as List))
        () {
          final h = r['horario'] as Map<String, dynamic>;
          final stock = r['stock'] as Map?;
          final inicio = r['inicio'] == null ? agora : _data(r['inicio']);
          final fim = r['fim'] == null ? null : _data(r['fim']);
          // A validade e os dias que restam vêm do stock; sem unidades, do fim da receita.
          final validade = r['validaAte'] != null
              ? DateTime.parse(r['validaAte'] as String)
              : (fim == null ? null : DateTime(fim.year, fim.month, fim.day));
          var dias = stock?['diasRestantes'] as int?;
          double? fracaoTempo;
          if (fim != null) {
            dias ??= (fim.difference(agora).inMinutes / 1440).ceil().clamp(
              0,
              100000,
            );
            final total = fim.difference(inicio).inMinutes;
            if (total > 0) {
              fracaoTempo = (fim.difference(agora).inMinutes / total).clamp(
                0.0,
                1.0,
              );
            }
          }
          return Receita(
            id: r['id'] as String,
            medicamentoId: r['medicamentoId'] as String,
            medicamento: nomes[r['medicamentoId']] ?? 'Medicamento',
            dose: r['dose'] as String,
            horario: _horario(h),
            intervaloHoras: h['tipo'] == 'intervalo'
                ? (h['intervaloHoras'] as num).toDouble()
                : null,
            horasFixas: h['tipo'] == 'intervalo'
                ? const []
                : [for (final x in (h['horasLocais'] as List)) x as String],
            ativa: r['ativa'] as bool,
            validaAte: validade,
            unidadesIniciais: r['unidadesIniciais'] as int?,
            unidadesRestantes: (stock?['unidadesRestantes'] as num?)?.round(),
            diasRestantes: dias,
            fracaoTempo: fracaoTempo,
          );
        }(),
    ];
  }

  @override
  Future<void> alterarReceita(
    String perfilId,
    Receita antiga,
    NovaReceita nova,
  ) async {
    final nome = nova.medicamento.trim();
    if (nome != antiga.medicamento && antiga.medicamentoId.isNotEmpty) {
      await _api.pedir(
        'PATCH',
        '/medicamentos/${antiga.medicamentoId}',
        perfilId: perfilId,
        corpo: {'nome': nome},
      );
    }
    await _api.pedir(
      'PATCH',
      '/receitas/${antiga.id}',
      perfilId: perfilId,
      corpo: {'dose': nova.dose.trim(), 'horario': horarioDaReceita(nova)},
    );
  }

  @override
  Future<void> apagarReceita(String perfilId, String receitaId) async {
    await _api.pedir('DELETE', '/receitas/$receitaId', perfilId: perfilId);
  }

  @override
  Future<Receita> criarReceita(
    String perfilId,
    NovaReceita receita,
    DateTime agora,
  ) async {
    final med = await _api.pedir(
      'POST',
      '/medicamentos',
      perfilId: perfilId,
      corpo: {'nome': receita.medicamento.trim()},
    );
    final medicamentoId = (med!['medicamento'] as Map)['id'] as String;
    // `assincrono`: o servidor responde já e gera as tomas em segundo plano; a app segue o estado.
    final j = await _api.pedir(
      'POST',
      '/receitas',
      perfilId: perfilId,
      query: {'assincrono': 'true'},
      corpo: corpoDaReceita(receita, medicamentoId, agora),
    );
    final r = j!['receita'] as Map<String, dynamic>;
    return Receita(
      id: r['id'] as String,
      medicamento: receita.medicamento.trim(),
      dose: r['dose'] as String,
      horario: _horario(r['horario'] as Map<String, dynamic>),
      ativa: r['ativa'] as bool,
    );
  }

  @override
  Future<EstadoGeracao> estadoGeracao(String perfilId, String receitaId) async {
    final j = await _api.pedir(
      'GET',
      '/receitas/$receitaId/geracao',
      perfilId: perfilId,
    );
    final fase = switch (j!['estado']) {
      'concluida' => FaseGeracao.concluida,
      'falhou' => FaseGeracao.falhou,
      _ => FaseGeracao.aGerar,
    };
    return EstadoGeracao(
      fase: fase,
      tomasGeradas: (j['tomasGeradas'] as num).toInt(),
    );
  }
}

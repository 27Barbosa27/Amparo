import 'package:amparo/dados/corpo_receita.dart';
import 'package:amparo/dados/repositorio.dart';
import 'package:amparo/dominio/modelos.dart';

/// Repositório falso, SÓ PARA OS TESTES (os dados de exemplo ficam aqui, nunca na app). As horas são relativas ao "agora" com que é criado, por isso o dia faz sempre sentido.
class RepositorioMemoria implements Repositorio {
  // `vazio` não pode ser `this._vazio`: um parâmetro nomeado não pode começar por "_".
  RepositorioMemoria({required DateTime agora, bool vazio = false})
    // ignore: prefer_initializing_formals
    : _vazio = vazio {
    final dia = DateTime(agora.year, agora.month, agora.day);
    DateTime h(int hora, [int min = 0]) =>
        DateTime(dia.year, dia.month, dia.day, hora, min);
    _tomas['maria'] = [
      Toma(
        id: 't1',
        medicamento: 'Metformina e Vitamina D',
        dose: '',
        agendada: h(8),
        estado: EstadoToma.tomada,
        tomadaEm: h(8, 12),
        registadaEm: h(8, 12),
      ),
      Toma(
        id: 't2',
        medicamento: 'Lisinopril',
        dose: '10 mg',
        nota: 'de manhã',
        agendada: h(9),
      ),
      Toma(
        id: 't3',
        medicamento: 'Metformina',
        dose: '500 mg',
        nota: 'com o almoço',
        agendada: h(13),
      ),
      Toma(
        id: 't4',
        medicamento: 'Atorvastatina',
        dose: '20 mg',
        agendada: h(21),
      ),
    ];
    _tomas['manuel'] = [
      Toma(id: 'm1', medicamento: 'Ramipril', dose: '5 mg', agendada: h(10)),
    ];
  }

  /// Sem nenhuma pessoa (uma conta nova), para testar o ecrã vazio.
  final bool _vazio;
  final Map<String, List<Toma>> _tomas = {};

  static const _perfis = [
    Perfil(id: 'maria', nome: 'Maria'),
    Perfil(id: 'manuel', nome: 'Manuel'),
  ];

  /// Alterações guardadas por [atualizarTamanhoTexto] (sobrepõem-se a [_perfis] e [_perfisExtra]).
  final Map<String, Perfil> _alteracoes = {};

  @override
  Future<List<Perfil>> perfis() async => [
    for (final p in [if (!_vazio) ..._perfis, ..._perfisExtra])
      _alteracoes[p.id] ?? p,
  ];

  @override
  Future<Perfil> atualizarTamanhoTexto(
    String perfilId,
    TamanhoTexto tamanhoTexto,
  ) async {
    final atual = (await perfis()).firstWhere((p) => p.id == perfilId);
    final novo = atual.copiarCom(tamanhoTexto: tamanhoTexto);
    _alteracoes[perfilId] = novo;
    return novo;
  }

  @override
  Future<List<Toma>> tomasDeHoje(String perfilId, DateTime agora) async =>
      List.unmodifiable(_tomas[perfilId] ?? const []);

  /// Tomas de dias passados, só para o histórico (quem não as pede nunca as vê).
  final Map<String, List<Toma>> historicoExtra = {};

  @override
  Future<List<Toma>> historico(
    String perfilId,
    DateTime de,
    DateTime ate,
  ) async {
    final todas = [...?historicoExtra[perfilId], ...?_tomas[perfilId]];
    return [
      for (final t in todas)
        if (!t.agendada.isBefore(de) && t.agendada.isBefore(ate)) t,
    ]..sort((a, b) => a.agendada.compareTo(b.agendada));
  }

  Toma _atualizar(String id, Toma Function(Toma) f) {
    for (final lista in _tomas.values) {
      final i = lista.indexWhere((t) => t.id == id);
      if (i >= 0) return lista[i] = f(lista[i]);
    }
    throw const RegistoNaoPermitido('toma_nao_encontrada');
  }

  Toma _procurar(String id) {
    for (final lista in _tomas.values) {
      for (final t in lista) {
        if (t.id == id) return t;
      }
    }
    throw const RegistoNaoPermitido('toma_nao_encontrada');
  }

  @override
  Future<Toma> marcarTomada(
    String perfilId,
    String tomaId,
    DateTime agora, {
    DateTime? hora,
    String? porCuidador,
  }) async {
    final atual = _procurar(tomaId);
    if (atual.estado == EstadoToma.tomada ||
        atual.estado == EstadoToma.saltada) {
      throw const RegistoNaoPermitido('toma_ja_registada');
    }
    final quando = hora ?? agora;
    if (quando.isAfter(agora.add(const Duration(minutes: 1)))) {
      throw const RegistoNaoPermitido('hora_invalida');
    }
    return _atualizar(
      tomaId,
      (t) => t.copiarCom(
        estado: EstadoToma.tomada,
        tomadaEm: quando,
        registadaPor: porCuidador,
        registadaEm: agora,
      ),
    );
  }

  @override
  Future<Toma> saltar(
    String perfilId,
    String tomaId,
    DateTime agora, {
    String? porCuidador,
  }) async {
    final atual = _procurar(tomaId);
    if (atual.estado == EstadoToma.tomada ||
        atual.estado == EstadoToma.saltada) {
      throw const RegistoNaoPermitido('toma_ja_registada');
    }
    return _atualizar(
      tomaId,
      (t) => t.copiarCom(
        estado: EstadoToma.saltada,
        registadaPor: porCuidador,
        registadaEm: agora,
      ),
    );
  }

  @override
  Future<Toma> desfazer(String perfilId, String tomaId, DateTime agora) async {
    final atual = _procurar(tomaId);
    if (atual.estado == EstadoToma.pendente) return atual;
    if (!atual.podeDesfazer(agora)) {
      throw const RegistoNaoPermitido('desfazer_expirado');
    }
    return _atualizar(
      tomaId,
      (t) => t.copiarCom(estado: EstadoToma.pendente, limparRegisto: true),
    );
  }

  @override
  Future<List<DiaAdesao>> ultimos7Dias(String perfilId, DateTime agora) async {
    // Os mesmos 7 dias do design: uma toma esquecida à quarta, hoje em curso.
    final hoje = DateTime(agora.year, agora.month, agora.day);
    const resultados = [
      ResultadoDia.tudoTomado,
      ResultadoDia.tudoTomado,
      ResultadoDia.tudoTomado,
      ResultadoDia.esquecida,
      ResultadoDia.tudoTomado,
      ResultadoDia.tudoTomado,
      ResultadoDia.emCurso,
    ];
    return [
      for (var i = 0; i < 7; i++)
        DiaAdesao(
          dia: hoje.subtract(Duration(days: 6 - i)),
          resultado: resultados[i],
        ),
    ];
  }

  int codigosCriados = 0;
  EstadoCodigo estadoDoCodigo = EstadoCodigo.aEspera;
  DateTime? _expiraEm;

  @override
  Future<CodigoLigacao> criarCodigoLigacao(String perfilId) async {
    codigosCriados++;
    estadoDoCodigo = EstadoCodigo.aEspera;
    _expiraEm = DateTime.now().add(const Duration(minutes: 15));
    return CodigoLigacao(
      id: 'cod$codigosCriados',
      codigo: '482915',
      expiraEm: _expiraEm!,
    );
  }

  @override
  Future<EstadoCodigo> estadoCodigo(String perfilId, String codigoId) async =>
      estadoDoCodigo;

  @override
  Future<String?> nomeDoCuidador(String perfilId) async => 'Ana';

  // ---- pessoas e receitas (dados falsos) ----
  final List<Perfil> _perfisExtra = [];
  final Map<String, List<Receita>> _receitas = {};
  final Map<String, int> _geradas = {};
  int _seq = 0;

  @override
  Future<Perfil> criarPessoa(NovaPessoa pessoa) async {
    final p = Perfil(
      id: 'novo${++_seq}',
      nome: pessoa.nome.trim(),
      tamanhoTexto: pessoa.tamanhoTexto,
    );
    _perfisExtra.add(p);
    _tomas[p.id] = [];
    return p;
  }

  @override
  Future<List<Receita>> receitas(String perfilId) async {
    final base = perfilId == 'maria'
        ? <Receita>[
            Receita(
              id: 'rc1',
              medicamento: 'Lisinopril 10 mg',
              dose: '1 comprimido',
              horario: '09:00',
              ativa: true,
              validaAte: DateTime(2027, 3, 15),
              unidadesIniciais: 30,
              unidadesRestantes: 4,
              diasRestantes: 4,
            ),
            Receita(
              id: 'rc2',
              medicamento: 'Metformina 500 mg',
              dose: '1 comprimido',
              horario: '08:00, 13:00',
              ativa: true,
              validaAte: DateTime(2027, 6, 2),
              unidadesIniciais: 60,
              unidadesRestantes: 35,
              diasRestantes: 23,
            ),
            Receita(
              id: 'rc3',
              medicamento: 'Atorvastatina 20 mg',
              dose: '1 comprimido',
              horario: '21:00',
              ativa: true,
              validaAte: DateTime(2027, 1, 30),
              unidadesIniciais: 50,
              unidadesRestantes: 41,
              diasRestantes: 41,
            ),
          ]
        : const <Receita>[];
    return [...base, ...?_receitas[perfilId]];
  }

  @override
  Future<Receita> criarReceita(
    String perfilId,
    NovaReceita receita,
    DateTime agora,
  ) async {
    final r = Receita(
      id: 'rc${++_seq}',
      medicamento: receita.medicamento.trim(),
      dose: receita.dose,
      horario: receita.frequencia == Frequencia.cadaOitoHoras
          ? 'De 8 em 8 horas'
          : receita.primeiraTomaTexto,
      ativa: true,
    );
    (_receitas[perfilId] ??= []).add(r);
    // As tomas de hoje, nos horários da receita.
    final dia = DateTime(agora.year, agora.month, agora.day);
    final horario =
        corpoDaReceita(receita, r.id, agora)['horario'] as Map<String, Object?>;
    final horas = horario['tipo'] == 'intervalo'
        ? [
            for (var h = receita.hora; h < 24; h += 8)
              DateTime(dia.year, dia.month, dia.day, h, receita.minuto),
          ]
        : [
            for (final x in horario['horasLocais'] as List)
              DateTime(
                dia.year,
                dia.month,
                dia.day,
                int.parse((x as String).substring(0, 2)),
                int.parse(x.substring(3)),
              ),
          ];
    final lista = (_tomas[perfilId] ??= []);
    for (final h in horas) {
      lista.add(
        Toma(
          id: 'g${++_seq}',
          medicamento: r.medicamento,
          dose: r.dose,
          agendada: h,
        ),
      );
    }
    _geradas[r.id] = horas.length;
    return r;
  }

  @override
  Future<void> alterarReceita(
    String perfilId,
    Receita antiga,
    NovaReceita nova,
  ) async {
    final lista = _receitas[perfilId] ??= [];
    final i = lista.indexWhere((r) => r.id == antiga.id);
    if (i < 0) return;
    lista[i] = Receita(
      id: antiga.id,
      medicamento: nova.medicamento.trim(),
      dose: nova.dose,
      horario: nova.primeiraTomaTexto,
      ativa: true,
      horasFixas: nova.frequencia == Frequencia.cadaOitoHoras
          ? const []
          : [nova.primeiraTomaTexto],
      intervaloHoras: nova.frequencia == Frequencia.cadaOitoHoras ? 8 : null,
    );
  }

  @override
  Future<void> apagarReceita(String perfilId, String receitaId) async {
    _receitas[perfilId]?.removeWhere((r) => r.id == receitaId);
  }

  @override
  Future<EstadoGeracao> estadoGeracao(
    String perfilId,
    String receitaId,
  ) async => EstadoGeracao(
    fase: FaseGeracao.concluida,
    tomasGeradas: _geradas[receitaId] ?? 0,
  );
}

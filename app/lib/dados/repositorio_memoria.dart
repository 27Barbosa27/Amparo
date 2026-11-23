import '../dominio/modelos.dart';
import 'repositorio.dart';

/// Dados falsos, tirados do design (Maria, Lisinopril, Metformina...), para desenvolver e testar os ecrãs
/// sem servidor. As horas são relativas ao "agora" com que é criado, por isso o dia faz sempre sentido.
class RepositorioMemoria implements Repositorio {
  RepositorioMemoria({required DateTime agora}) {
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

  final Map<String, List<Toma>> _tomas = {};

  static const _perfis = [
    Perfil(id: 'maria', nome: 'Maria'),
    Perfil(id: 'manuel', nome: 'Manuel'),
  ];

  @override
  Future<List<Perfil>> perfis() async => _perfis;

  @override
  Future<List<Toma>> tomasDeHoje(String perfilId, DateTime agora) async =>
      List.unmodifiable(_tomas[perfilId] ?? const []);

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

  @override
  Future<String?> nomeDoCuidador(String perfilId) async => 'Ana';
}

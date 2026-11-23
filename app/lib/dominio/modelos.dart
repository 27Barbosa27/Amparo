/// Os estados que o servidor guarda. "Atrasada" NÃO é um estado: deriva-se (ver [Toma.atrasada]).
enum EstadoToma { pendente, tomada, saltada, falhada }

/// Tolerância depois da hora prevista antes de uma toma pendente contar como atrasada (igual à do servidor).
const toleranciaAtraso = Duration(minutes: 15);

/// Durante este tempo um registo pode ser desfeito.
const janelaDesfazer = Duration(minutes: 1);

class Perfil {
  const Perfil({required this.id, required this.nome});

  final String id;

  /// Pseudónimo ("Avó Rosa"). Nunca se pede o nome verdadeiro.
  final String nome;

  String get inicial => nome.isEmpty ? '?' : nome.substring(0, 1).toUpperCase();
}

class Toma {
  const Toma({
    required this.id,
    required this.medicamento,
    required this.dose,
    required this.agendada,
    this.nota,
    this.estado = EstadoToma.pendente,
    this.tomadaEm,
    this.registadaPor,
    this.registadaEm,
  });

  final String id;
  final String medicamento;
  final String dose;
  final String? nota;
  final DateTime agendada;
  final EstadoToma estado;
  final DateTime? tomadaEm;

  /// Nome de quem registou, quando foi um cuidador ("Marcada pela Ana"). Nulo se foi a própria pessoa.
  final String? registadaPor;

  /// Quando o registo foi feito (para o "desfazer 1 min").
  final DateTime? registadaEm;

  bool atrasada(DateTime agora) =>
      estado == EstadoToma.pendente &&
      agendada.add(toleranciaAtraso).isBefore(agora);

  bool podeDesfazer(DateTime agora) =>
      (estado == EstadoToma.tomada || estado == EstadoToma.saltada) &&
      registadaEm != null &&
      agora.difference(registadaEm!) <= janelaDesfazer;

  Toma copiarCom({
    EstadoToma? estado,
    DateTime? tomadaEm,
    String? registadaPor,
    DateTime? registadaEm,
    bool limparRegisto = false,
  }) => Toma(
    id: id,
    medicamento: medicamento,
    dose: dose,
    nota: nota,
    agendada: agendada,
    estado: estado ?? this.estado,
    tomadaEm: limparRegisto ? null : (tomadaEm ?? this.tomadaEm),
    registadaPor: limparRegisto ? null : (registadaPor ?? this.registadaPor),
    registadaEm: limparRegisto ? null : (registadaEm ?? this.registadaEm),
  );
}

/// Resumo do dia para o cartão do cuidador. O total conta TODAS as tomas do dia (saltadas e falhadas também).
class ResumoDia {
  const ResumoDia({
    required this.tomadas,
    required this.porConfirmar,
    required this.porTomar,
    this.outras = 0,
  });

  factory ResumoDia.de(List<Toma> tomas, DateTime agora) {
    var tomadas = 0, porConfirmar = 0, porTomar = 0, outras = 0;
    for (final t in tomas) {
      switch (t.estado) {
        case EstadoToma.tomada:
          tomadas++;
        case EstadoToma.pendente:
          t.atrasada(agora) ? porConfirmar++ : porTomar++;
        case EstadoToma.saltada || EstadoToma.falhada:
          outras++;
      }
    }
    return ResumoDia(
      tomadas: tomadas,
      porConfirmar: porConfirmar,
      porTomar: porTomar,
      outras: outras,
    );
  }

  final int tomadas;
  final int porConfirmar;
  final int porTomar;

  /// Saltadas e falhadas.
  final int outras;

  int get total => tomadas + porConfirmar + porTomar + outras;
}

/// Como correu um dia: tudo tomado, alguma toma esquecida, ou ainda em curso (hoje).
enum ResultadoDia { tudoTomado, esquecida, emCurso }

class DiaAdesao {
  const DiaAdesao({required this.dia, required this.resultado});
  final DateTime dia;
  final ResultadoDia resultado;
}

/// Percentagem de adesão dos dias já terminados (tudo tomado / dias terminados).
int percentagemAdesao(List<DiaAdesao> dias) {
  final fechados = dias
      .where((d) => d.resultado != ResultadoDia.emCurso)
      .toList();
  if (fechados.isEmpty) return 100;
  final bons = fechados
      .where((d) => d.resultado == ResultadoDia.tudoTomado)
      .length;
  return (bons * 100 / fechados.length).round();
}

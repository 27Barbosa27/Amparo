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

// ---------- Pessoas e receitas novas ----------

/// Quem recebe os alarmes: a própria pessoa (liga o telemóvel com um código) ou o cuidador.
enum AlarmesEm { pessoa, cuidador }

enum TamanhoTexto { normal, grande, muitoGrande }

class NovaPessoa {
  const NovaPessoa({
    required this.nome,
    required this.alarmesEm,
    required this.tamanhoTexto,
  });
  final String nome;
  final AlarmesEm alarmesEm;
  final TamanhoTexto tamanhoTexto;
}

/// "Com que frequência?" do formulário (ver o mapa no plano, secção 3.1).
enum Frequencia { cadaOitoHoras, duasVezesDia, umaVezDia, outra }

/// "Durante quanto tempo?" (no máximo 3 meses por geração, depois renova).
enum Duracao { seteDias, umMes, tresMeses }

extension DuracaoDias on Duracao {
  int get dias => switch (this) {
    Duracao.seteDias => 7,
    Duracao.umMes => 30,
    Duracao.tresMeses => 90,
  };
  String get texto => switch (this) {
    Duracao.seteDias => '7 dias',
    Duracao.umMes => '1 mês',
    Duracao.tresMeses => '3 meses',
  };
}

extension FrequenciaTexto on Frequencia {
  String get texto => switch (this) {
    Frequencia.cadaOitoHoras => 'De 8 em 8 horas',
    Frequencia.duasVezesDia => '2 vezes ao dia',
    Frequencia.umaVezDia => '1 vez ao dia',
    Frequencia.outra => 'Outra',
  };
}

class NovaReceita {
  const NovaReceita({
    required this.medicamento,
    required this.dose,
    required this.frequencia,
    required this.hora,
    required this.minuto,
    required this.duracao,
    this.horasOutra = const [],
  });

  final String medicamento;
  final String dose;
  final Frequencia frequencia;

  /// Hora da primeira toma (relógio local).
  final int hora;
  final int minuto;
  final Duracao duracao;

  /// Só para `Frequencia.outra`: as horas escolhidas ("08:00", "14:00"...).
  final List<String> horasOutra;

  String get primeiraTomaTexto =>
      '${hora.toString().padLeft(2, '0')}:${minuto.toString().padLeft(2, '0')}';

  /// "De 8 em 8 horas · 3 meses".
  String get resumo => '${frequencia.texto} · ${duracao.texto}';

  /// A primeira toma real: hoje se a hora ainda não passou, senão amanhã (só para "De 8 em 8 horas",
  /// que conta a partir da primeira toma; nas outras, as tomas de hoje que ainda faltam também contam).
  DateTime primeiraToma(DateTime agora) {
    final hoje = DateTime(agora.year, agora.month, agora.day, hora, minuto);
    return hoje.isAfter(agora) ? hoje : hoje.add(const Duration(days: 1));
  }

  /// "Hoje, às 08:00" ou "Amanhã, às 08:00".
  String primeiraTomaPorExtenso(DateTime agora) {
    final t = primeiraToma(agora);
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final quando = DateTime(t.year, t.month, t.day) == hoje ? 'Hoje' : 'Amanhã';
    return '$quando, às $primeiraTomaTexto';
  }
}

class Receita {
  const Receita({
    required this.id,
    required this.medicamento,
    required this.dose,
    required this.horario,
    required this.ativa,
    this.validaAte,
    this.unidadesIniciais,
    this.unidadesRestantes,
    this.diasRestantes,
  });

  final String id;
  final String medicamento;
  final String dose;

  /// "De 8 em 8 horas" ou "08:00, 20:00".
  final String horario;
  final bool ativa;
  final DateTime? validaAte;
  final int? unidadesIniciais;
  final int? unidadesRestantes;
  final int? diasRestantes;

  /// Fração do stock que resta (0 a 1), para a barra. Nula se não há unidades iniciais.
  double? get fracaoRestante {
    final i = unidadesIniciais;
    final r = unidadesRestantes;
    if (i == null || r == null || i <= 0) return null;
    return (r / i).clamp(0.0, 1.0);
  }

  /// "Acaba em N dias": quando os dias que restam chegam ao limite do aviso (por omissão 4).
  bool aAcabar([int limite = 4]) =>
      diasRestantes != null && diasRestantes! <= limite;
}

enum FaseGeracao { aGerar, concluida, falhou }

class EstadoGeracao {
  const EstadoGeracao({required this.fase, required this.tomasGeradas});
  final FaseGeracao fase;
  final int tomasGeradas;
}

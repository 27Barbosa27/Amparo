/// Os estados que o servidor guarda. "Atrasada" NÃO é um estado: deriva-se (ver [Toma.atrasada]).
enum EstadoToma { pendente, tomada, saltada, falhada }

/// Tolerância depois da hora prevista antes de uma toma pendente contar como atrasada (igual à do servidor).
const toleranciaAtraso = Duration(minutes: 15);

/// Durante este tempo um registo pode ser desfeito.
const janelaDesfazer = Duration(minutes: 1);

class Perfil {
  const Perfil({
    required this.id,
    required this.nome,
    this.tamanhoTexto = TamanhoTexto.normal,
  });

  final String id;

  /// A definição de texto escolhida para a pessoa (o modo simples aplica-a).
  final TamanhoTexto tamanhoTexto;

  /// Pseudónimo ("Avó Rosa"). Nunca se pede o nome verdadeiro.
  final String nome;

  String get inicial => nome.isEmpty ? '?' : nome.substring(0, 1).toUpperCase();
}

/// O cuidador também pode tomar medicação: o perfil dele tem o mesmo nome que a conta.
bool eProprioCuidador(Perfil perfil, String? cuidador) =>
    cuidador != null &&
    cuidador.trim().isNotEmpty &&
    perfil.nome.trim().toLowerCase() == cuidador.trim().toLowerCase();

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

/// Como acabou uma toma, para o histórico: derivado do estado e da hora ([Toma.atrasada]).
enum ResultadoToma { tomada, saltada, esquecida, porConfirmar, porTomar }

extension HistoricoDaToma on Toma {
  ResultadoToma resultado(DateTime agora) => switch (estado) {
    EstadoToma.tomada => ResultadoToma.tomada,
    EstadoToma.saltada => ResultadoToma.saltada,
    EstadoToma.falhada => ResultadoToma.esquecida,
    // Pendente: ainda por tomar, por confirmar (já passou a tolerância) ou, de um dia que acabou, esquecida.
    EstadoToma.pendente =>
      agendada.isBefore(DateTime(agora.year, agora.month, agora.day))
          ? ResultadoToma.esquecida
          : (atrasada(agora)
                ? ResultadoToma.porConfirmar
                : ResultadoToma.porTomar),
  };
}

/// Os números de um período do histórico. A adesão conta as tomas que já tinham de estar feitas
/// (tomadas, saltadas e esquecidas); o que ainda vem a caminho (por confirmar, por tomar) não entra.
class ResumoHistorico {
  const ResumoHistorico({
    required this.tomadas,
    required this.saltadas,
    required this.esquecidas,
    required this.porConfirmar,
    required this.porTomar,
  });

  factory ResumoHistorico.de(List<Toma> tomas, DateTime agora) {
    var tomadas = 0,
        saltadas = 0,
        esquecidas = 0,
        porConfirmar = 0,
        porTomar = 0;
    for (final t in tomas) {
      switch (t.resultado(agora)) {
        case ResultadoToma.tomada:
          tomadas++;
        case ResultadoToma.saltada:
          saltadas++;
        case ResultadoToma.esquecida:
          esquecidas++;
        case ResultadoToma.porConfirmar:
          porConfirmar++;
        case ResultadoToma.porTomar:
          porTomar++;
      }
    }
    return ResumoHistorico(
      tomadas: tomadas,
      saltadas: saltadas,
      esquecidas: esquecidas,
      porConfirmar: porConfirmar,
      porTomar: porTomar,
    );
  }

  final int tomadas;
  final int saltadas;
  final int esquecidas;
  final int porConfirmar;
  final int porTomar;

  int get total => tomadas + saltadas + esquecidas + porConfirmar + porTomar;

  /// Percentagem de adesão, ou nulo quando ainda não há nenhuma toma a avaliar (nunca se inventa uma).
  int? get adesao {
    final avaliadas = tomadas + saltadas + esquecidas;
    return avaliadas == 0 ? null : (tomadas * 100 / avaliadas).round();
  }
}

/// Como correu um dia: tudo tomado, alguma toma esquecida, ainda em curso (hoje) ou sem dados
/// (não havia nenhuma toma: por exemplo, antes de a conta ou a receita existirem).
enum ResultadoDia { tudoTomado, esquecida, emCurso, semDados }

class DiaAdesao {
  const DiaAdesao({required this.dia, required this.resultado});
  final DateTime dia;
  final ResultadoDia resultado;
}

/// Percentagem de adesão dos dias já terminados que TIVERAM tomas. Nula quando ainda não há nenhum
/// (conta nova): nunca se inventa uma percentagem.
int? percentagemAdesao(List<DiaAdesao> dias) {
  final comDados = dias
      .where(
        (d) =>
            d.resultado == ResultadoDia.tudoTomado ||
            d.resultado == ResultadoDia.esquecida,
      )
      .toList();
  if (comDados.isEmpty) return null;
  final bons = comDados
      .where((d) => d.resultado == ResultadoDia.tudoTomado)
      .length;
  return (bons * 100 / comDados.length).round();
}

// ---------- Pessoas e receitas novas ----------

/// Quem recebe os alarmes: a própria pessoa (liga o telemóvel com um código) ou o cuidador.
enum AlarmesEm { pessoa, cuidador }

enum TamanhoTexto {
  normal(1),
  grande(1.15),
  muitoGrande(1.3);

  const TamanhoTexto(this.escala);

  /// Quanto o texto cresce em relação ao tamanho do design.
  final double escala;

  /// O valor que a API usa (`normal`, `grande`, `muito_grande`).
  static TamanhoTexto daApi(Object? v) => switch (v) {
    'grande' => TamanhoTexto.grande,
    'muito_grande' => TamanhoTexto.muitoGrande,
    _ => TamanhoTexto.normal,
  };
}

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

/// O que se toma: não é só comprimidos. A dose começa na unidade do tipo ("1 comprimido", "5 ml"...).
enum TipoMedicacao {
  comprimido('Comprimido', '1 comprimido', ['comprimid']),
  capsula('Cápsula', '1 cápsula', ['cápsula', 'capsula']),
  liquido('Xarope ou líquido', '5 ml', [' ml', 'colher', 'xarope']),
  gotas('Gotas', '5 gotas', ['gota']),
  injecao('Injeção', '1 injeção', ['injeç', 'injec', 'caneta']),
  pomada('Pomada ou creme', '1 aplicação', ['aplica', 'pomada', 'creme']),
  inalador('Inalador', '2 inalações', ['inala', 'puff']),
  outro('Outro', '1 unidade', []);

  const TipoMedicacao(this.texto, this.doseInicial, this._palavras);
  final String texto;
  final String doseInicial;
  final List<String> _palavras;

  /// O tipo que a dose sugere (a API só guarda a dose): serve para voltar a abrir uma receita.
  static TipoMedicacao daDose(String dose) {
    final d = ' ${dose.toLowerCase()}';
    for (final t in values) {
      if (t._palavras.any(d.contains)) return t;
    }
    return TipoMedicacao.outro;
  }
}

/// "Com que frequência?" do formulário (ver o mapa no plano, secção 3.1).
enum Frequencia { cadaOitoHoras, duasVezesDia, umaVezDia, outra }

/// "Durante quanto tempo?": um número de meses (o servidor gera as tomas por janelas e renova).
class Duracao {
  const Duracao(this.meses);
  final int meses;

  static const umMes = Duracao(1);
  static const tresMeses = Duracao(3);

  /// O máximo que o formulário aceita.
  static const maximoMeses = 24;

  /// "1 mês" ou "6 meses".
  String get texto => meses == 1 ? '1 mês' : '$meses meses';

  /// O fim: o mesmo dia, `meses` meses depois (31 de janeiro + 1 mês = 28 ou 29 de fevereiro).
  DateTime fimDe(DateTime inicio) {
    final total = inicio.year * 12 + (inicio.month - 1) + meses;
    final ano = total ~/ 12;
    final mes = total % 12 + 1;
    final diasDoMes = DateTime(ano, mes + 1, 0).day;
    final dia = inicio.day > diasDoMes ? diasDoMes : inicio.day;
    return DateTime(
      ano,
      mes,
      dia,
      inicio.hour,
      inicio.minute,
      inicio.second,
      inicio.millisecond,
    );
  }

  @override
  bool operator ==(Object other) => other is Duracao && other.meses == meses;

  @override
  int get hashCode => meses.hashCode;
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
    this.tipo = TipoMedicacao.comprimido,
    this.unidades,
  });

  final String medicamento;
  final TipoMedicacao tipo;
  final String dose;
  final Frequencia frequencia;

  /// Hora da primeira toma (relógio local).
  final int hora;
  final int minuto;
  final Duracao duracao;

  /// Quantas unidades (comprimidos, gotas...) a pessoa tem agora. Obrigatório ao criar; nulo ao editar.
  final int? unidades;

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
    this.emFalta,
    this.medicamentoId = '',
    this.intervaloHoras,
    this.horasFixas = const [],
    this.fracaoTempo,
  });

  final String id;

  /// O medicamento a que a receita pertence (para editar o nome).
  final String medicamentoId;

  /// "De N em N horas": o N. Nulo nas receitas com horas fixas.
  final double? intervaloHoras;

  /// "08:00", "20:00"... nas receitas com horas fixas.
  final List<String> horasFixas;

  /// Quanto do tempo da receita ainda falta (0 a 1), para a barra quando não há unidades.
  final double? fracaoTempo;
  final String medicamento;
  final String dose;

  /// "De 8 em 8 horas" ou "08:00, 20:00".
  final String horario;
  final bool ativa;
  final DateTime? validaAte;
  final int? unidadesIniciais;
  final int? unidadesRestantes;
  final int? diasRestantes;

  /// Unidades que faltam para chegar ao fim da receita (0 se o stock chega). Nulo sem stock.
  final int? emFalta;

  /// O stock não chega até ao fim da receita.
  bool get naoChega => (emFalta ?? 0) > 0;

  /// Fração do stock que resta (0 a 1), para a barra. Nula se não há unidades iniciais.
  double? get fracaoRestante {
    final i = unidadesIniciais;
    final r = unidadesRestantes;
    if (i == null || r == null || i <= 0) return fracaoTempo;
    return (r / i).clamp(0.0, 1.0);
  }

  /// "Acaba em N dias": quando os dias que restam chegam ao limite do aviso (por omissão 4).
  bool aAcabar([int limite = 4]) =>
      diasRestantes != null && diasRestantes! <= limite;
}

extension ReceitaParaEditar on Receita {
  /// A receita como o formulário a mostra (para editar): a frequência volta a descobrir-se das horas.
  NovaReceita comoNova() {
    final horas = horasFixas;
    final Frequencia f;
    var hora = 8, minuto = 0;
    if (intervaloHoras != null) {
      f = intervaloHoras == 8 ? Frequencia.cadaOitoHoras : Frequencia.outra;
    } else if (horas.length == 1) {
      f = Frequencia.umaVezDia;
    } else if (horas.length == 2 &&
        (int.parse(horas[0].substring(0, 2)) + 12) % 24 ==
            int.parse(horas[1].substring(0, 2)) &&
        horas[0].substring(3) == horas[1].substring(3)) {
      f = Frequencia.duasVezesDia;
    } else {
      f = Frequencia.outra;
    }
    if (horas.isNotEmpty) {
      hora = int.parse(horas.first.substring(0, 2));
      minuto = int.parse(horas.first.substring(3));
    }
    return NovaReceita(
      medicamento: medicamento,
      dose: dose,
      frequencia: f,
      hora: hora,
      minuto: minuto,
      duracao: Duracao.tresMeses,
      horasOutra: f == Frequencia.outra ? horas : const [],
      tipo: TipoMedicacao.daDose(dose),
    );
  }
}

/// O código de 6 dígitos que o cuidador mostra para ligar o telemóvel da pessoa.
class CodigoLigacao {
  const CodigoLigacao({
    required this.id,
    required this.codigo,
    required this.expiraEm,
  });
  final String id;
  final String codigo;
  final DateTime expiraEm;
}

enum EstadoCodigo { aEspera, ligado, expirado }

enum FaseGeracao { aGerar, concluida, falhou }

class EstadoGeracao {
  const EstadoGeracao({required this.fase, required this.tomasGeradas});
  final FaseGeracao fase;
  final int tomasGeradas;
}

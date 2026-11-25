import '../dominio/modelos.dart';

String _hhmm(int h, int m) =>
    '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

/// Traduz o formulário "Adicionar receita" para o que a API espera (plano, secção 3.1):
///  - "de 8 em 8 horas"  → `intervalo=8`, a contar da primeira toma;
///  - "2 vezes ao dia"   → `horas_fixas` na primeira toma e 12 horas depois;
///  - "1 vez ao dia"     → `horas_fixas` na primeira toma;
///  - "Outra"            → `horas_fixas` com as horas escolhidas.
/// A duração (7 dias, 1 mês, 3 meses) vira o fim. Função pura, fácil de testar.
Map<String, Object?> corpoDaReceita(
  NovaReceita r,
  String medicamentoId,
  DateTime agora,
) {
  final horario = horarioDaReceita(r);
  final inicio = r.frequencia == Frequencia.cadaOitoHoras
      ? r.primeiraToma(agora)
      : agora;
  return {
    'medicamentoId': medicamentoId,
    'dose': r.dose,
    'horario': horario,
    'inicio': inicio.toUtc().toIso8601String(),
    'fim': r.duracao.fimDe(inicio).toUtc().toIso8601String(),
    if (r.unidades != null) 'unidadesIniciais': r.unidades,
  };
}

/// O horário que a API espera (ver [corpoDaReceita]). Também serve para editar uma receita.
Map<String, Object?> horarioDaReceita(NovaReceita r) => switch (r.frequencia) {
  Frequencia.cadaOitoHoras => {'tipo': 'intervalo', 'intervaloHoras': 8},
  Frequencia.duasVezesDia => {
    'tipo': 'horas_fixas',
    'horasLocais': [r.primeiraTomaTexto, _hhmm((r.hora + 12) % 24, r.minuto)]
      ..sort(),
  },
  Frequencia.umaVezDia => {
    'tipo': 'horas_fixas',
    'horasLocais': [r.primeiraTomaTexto],
  },
  Frequencia.outra => {
    'tipo': 'horas_fixas',
    'horasLocais': r.horasOutra.toSet().toList()..sort(),
  },
};

/// Lê "08:00, 14:00 21:00" para uma lista de horas válidas.
/// Devolve nulo se alguma não for uma hora (HH:mm) ou se não houver nenhuma.
List<String>? lerHoras(String texto) {
  final partes = texto
      .split(RegExp(r'[,;\s]+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (partes.isEmpty) return null;
  final resultado = <String>[];
  for (final p in partes) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(p);
    if (m == null) return null;
    final h = int.parse(m[1]!), min = int.parse(m[2]!);
    if (h > 23 || min > 59) return null;
    resultado.add(_hhmm(h, min));
  }
  return resultado;
}

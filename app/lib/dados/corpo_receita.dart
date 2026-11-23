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
  final Map<String, Object?> horario;
  final DateTime inicio;
  switch (r.frequencia) {
    case Frequencia.cadaOitoHoras:
      horario = {'tipo': 'intervalo', 'intervaloHoras': 8};
      inicio = r.primeiraToma(agora);
    case Frequencia.duasVezesDia:
      final segunda = _hhmm((r.hora + 12) % 24, r.minuto);
      horario = {
        'tipo': 'horas_fixas',
        'horasLocais': [r.primeiraTomaTexto, segunda]..sort(),
      };
      inicio = agora;
    case Frequencia.umaVezDia:
      horario = {
        'tipo': 'horas_fixas',
        'horasLocais': [r.primeiraTomaTexto],
      };
      inicio = agora;
    case Frequencia.outra:
      horario = {
        'tipo': 'horas_fixas',
        'horasLocais': r.horasOutra.toSet().toList()..sort(),
      };
      inicio = agora;
  }
  return {
    'medicamentoId': medicamentoId,
    'dose': r.dose,
    'horario': horario,
    'inicio': inicio.toUtc().toIso8601String(),
    'fim': inicio.add(Duration(days: r.duracao.dias)).toUtc().toIso8601String(),
  };
}

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

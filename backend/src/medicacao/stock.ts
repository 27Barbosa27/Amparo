import type { Horario } from './servico.js';

/** Unidades por toma, lidas do início da dose ("2 comprimidos" → 2, "1/2 comprimido" → 0.5). Sem número: 1. */
export function unidadesPorToma(dose: string): number {
  const fracao = /^\s*(\d+)\s*\/\s*(\d+)/.exec(dose);
  if (fracao) {
    const [num, den] = [Number(fracao[1]), Number(fracao[2])];
    if (den > 0 && num > 0) return num / den;
  }
  const n = /^\s*(\d+(?:[.,]\d+)?)/.exec(dose);
  const valor = n ? Number(n[1]!.replace(',', '.')) : 1;
  return valor > 0 ? valor : 1;
}

export interface Stock {
  unidadesRestantes: number;
  /** Dias que ainda chegam ao ritmo da receita. É um indicador, não stock completo. */
  diasRestantes: number | null;
}

/** "Restam N dias" = unidades restantes / consumo diário (unidades iniciais menos as tomas tomadas). */
export function calcularStock(dose: string, horario: Horario, unidadesIniciais: number | null, tomadas: number): Stock | null {
  if (unidadesIniciais === null) return null;
  const porToma = unidadesPorToma(dose);
  const unidadesRestantes = Math.max(0, unidadesIniciais - tomadas * porToma);
  const tomasPorDia = horario.tipo === 'horas_fixas' ? horario.horasLocais.length : 24 / horario.intervaloHoras;
  const consumoDia = tomasPorDia * porToma;
  return { unidadesRestantes, diasRestantes: consumoDia > 0 ? Math.floor(unidadesRestantes / consumoDia) : null };
}

import type { Horario } from './servico.js';

/** Concentrações e volumes ("10 mg", "5 ml", "1000 UI"): descrevem o medicamento, não quantas unidades se tomam. */
const CONCENTRACAO = /^\s*\d+(?:[.,]\d+)?\s*(?:mg|mcg|µg|ug|g|kg|ml|l|ui|iu|%)(?![a-zçãõé])/i;

/**
 * Unidades por toma, lidas do início da dose ("2 comprimidos" → 2, "1/2 comprimido" → 0.5).
 * Uma concentração ("10 mg") NÃO conta como quantidade: nesse caso, e quando não há número, é 1 unidade.
 */
export function unidadesPorToma(dose: string): number {
  if (CONCENTRACAO.test(dose)) return 1;
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
  /** Unidades que faltam para chegar ao fim da receita. 0 quando o stock chega; nulo sem fim ou sem consumo. */
  emFalta: number | null;
}

/**
 * "Restam N dias" = unidades restantes / consumo diário (unidades iniciais menos as tomas tomadas).
 * Com o `fim` da receita, diz também quantas unidades faltam para lá chegar.
 */
export function calcularStock(
  dose: string,
  horario: Horario,
  unidadesIniciais: number | null,
  tomadas: number,
  fim: Date | null = null,
  agora: Date = new Date(),
): Stock | null {
  if (unidadesIniciais === null) return null;
  const porToma = unidadesPorToma(dose);
  const unidadesRestantes = Math.max(0, unidadesIniciais - tomadas * porToma);
  const tomasPorDia = horario.tipo === 'horas_fixas' ? horario.horasLocais.length : 24 / horario.intervaloHoras;
  const consumoDia = tomasPorDia * porToma;
  const diasAteFim = fim ? Math.max(0, (fim.getTime() - agora.getTime()) / 86_400_000) : null;
  return {
    unidadesRestantes,
    diasRestantes: consumoDia > 0 ? Math.floor(unidadesRestantes / consumoDia) : null,
    emFalta: consumoDia > 0 && diasAteFim !== null ? Math.max(0, Math.ceil(consumoDia * diasAteFim - unidadesRestantes)) : null,
  };
}

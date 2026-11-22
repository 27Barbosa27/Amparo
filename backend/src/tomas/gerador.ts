import { DateTime } from 'luxon';

/**
 * Geração das datas das tomas a partir da INTENÇÃO de uma receita.
 * Função pura (sem base de dados), para se poder testar a fundo.
 *
 * - `intervalo` ("de 8 em 8 horas"): intervalo ABSOLUTO em UTC; a mudança de hora não o afeta.
 * - `horas_fixas` ("às 08:00 e às 20:00"): HORA LOCAL na timezone da receita; em UTC a toma
 *   desloca-se uma hora quando muda a hora de verão, para a pessoa continuar a tomar à mesma hora do relógio.
 *   - Hora que não existe (relógio adianta): passa para a seguinte válida (01:30 -> 02:30).
 *   - Hora ambígua (relógio atrasa): usa a PRIMEIRA ocorrência, para manter o ritmo de 24 h.
 *
 * Devolve todas as datas t com: max(início da receita, de) <= t < min(fim da receita, até), por ordem.
 */

export type AgendaReceita =
  | { tipo: 'intervalo'; intervaloHoras: number; inicioUtc: Date; fimUtc: Date | null }
  | { tipo: 'horas_fixas'; horasLocais: string[]; timezone: string; inicioUtc: Date; fimUtc: Date | null };

/** Máximo de tomas numa só chamada (proteção contra janelas ou intervalos absurdos). */
export const MAX_TOMAS_POR_CHAMADA = 20_000;
const UM_MINUTO_MS = 60_000;
const UMA_HORA_MS = 3_600_000;

export function gerarAgendamentos(receita: AgendaReceita, de: Date, ate: Date): Date[] {
  const inicio = Math.max(receita.inicioUtc.getTime(), de.getTime());
  const limite = Math.min(ate.getTime(), receita.fimUtc ? receita.fimUtc.getTime() : Infinity);

  // Valida a receita mesmo que a janela fique vazia.
  const gerar =
    receita.tipo === 'intervalo' ? prepararIntervalo(receita) : prepararHorasFixas(receita);

  if (!(inicio < limite)) return [];
  const resultado = gerar(inicio, limite);
  if (resultado.length > MAX_TOMAS_POR_CHAMADA) {
    throw new Error(`Demasiadas tomas numa só janela (${resultado.length}); reduza a janela`);
  }
  return resultado.map((ms) => new Date(ms));
}

type Gerador = (inicio: number, limite: number) => number[];

function prepararIntervalo(r: Extract<AgendaReceita, { tipo: 'intervalo' }>): Gerador {
  const passo = Math.round(r.intervaloHoras * UMA_HORA_MS);
  if (!Number.isFinite(passo) || passo < UM_MINUTO_MS) {
    throw new Error('Intervalo inválido: tem de ser de pelo menos 1 minuto');
  }
  const origem = r.inicioUtc.getTime();
  return (inicio, limite) => {
    const total = Math.ceil((limite - Math.max(origem, inicio)) / passo) + 1;
    if (total > MAX_TOMAS_POR_CHAMADA + 1) {
      throw new Error('Demasiadas tomas numa só janela; reduza a janela');
    }
    const k0 = Math.max(0, Math.ceil((inicio - origem) / passo));
    const out: number[] = [];
    for (let t = origem + k0 * passo; t < limite; t += passo) out.push(t);
    return out;
  };
}

function prepararHorasFixas(r: Extract<AgendaReceita, { tipo: 'horas_fixas' }>): Gerador {
  if (!DateTime.now().setZone(r.timezone).isValid) {
    throw new Error(`Fuso horário inválido: ${r.timezone}`);
  }
  if (r.horasLocais.length === 0) throw new Error('Indique pelo menos uma hora');
  const horas = [...new Set(r.horasLocais.map(lerHora))].sort((a, b) => a.minutosDoDia - b.minutosDoDia);

  return (inicio, limite) => {
    const out = new Set<number>();
    // Um dia de folga para cada lado cobre qualquer diferença de fuso.
    let dia = DateTime.fromMillis(inicio, { zone: r.timezone }).startOf('day').minus({ days: 1 });
    const fim = DateTime.fromMillis(limite, { zone: r.timezone }).plus({ days: 1 });
    let guarda = 0;
    while (dia <= fim) {
      for (const h of horas) {
        const t = instanteLocal(dia, h.hora, h.minuto, r.timezone);
        if (t >= inicio && t < limite) out.add(t);
      }
      dia = dia.plus({ days: 1 });
      if (++guarda > 40_000) throw new Error('Demasiadas tomas numa só janela; reduza a janela');
    }
    return [...out].sort((a, b) => a - b);
  };
}

function lerHora(texto: string): { hora: number; minuto: number; minutosDoDia: number } {
  const m = /^(\d{2}):(\d{2})(?::\d{2})?$/.exec(texto);
  if (!m) throw new Error(`Hora inválida: "${texto}" (use HH:mm)`);
  const hora = Number(m[1]);
  const minuto = Number(m[2]);
  if (hora > 23 || minuto > 59) throw new Error(`Hora inválida: "${texto}"`);
  return { hora, minuto, minutosDoDia: hora * 60 + minuto };
}

/** Instante UTC (ms) de "hora:minuto" locais num dado dia, com as regras de mudança de hora acima. */
function instanteLocal(dia: DateTime, hora: number, minuto: number, zone: string): number {
  const dt = DateTime.fromObject(
    { year: dia.year, month: dia.month, day: dia.day, hour: hora, minute: minuto },
    { zone },
  );
  const t = dt.toMillis();
  // Hora ambígua: se uma hora antes o relógio marcava a mesma hora, usa-se a primeira ocorrência.
  const antes = DateTime.fromMillis(t - UMA_HORA_MS, { zone });
  if (antes.hour === dt.hour && antes.minute === dt.minute && antes.day === dt.day) {
    return t - UMA_HORA_MS;
  }
  return t;
}

import type { Db } from '../db.js';
import { trabalhosDiarios, trabalhosDoMinuto, type Contexto } from './trabalhos.js';

/**
 * Corre `f` só se mais nenhuma instância a estiver a correr (trinco consultivo do PostgreSQL).
 * Assim, duas instâncias do servidor (por exemplo durante uma atualização) nunca avisam duas vezes.
 */
export async function comTrinco<T>(db: Db, chave: number, f: () => Promise<T>): Promise<T | null> {
  const cliente = await db.connect();
  try {
    const { rows } = await cliente.query<{ ok: boolean }>('select pg_try_advisory_lock($1) as ok', [chave]);
    if (!rows[0]?.ok) return null;
    try {
      return await f();
    } finally {
      await cliente.query('select pg_advisory_unlock($1)', [chave]);
    }
  } finally {
    cliente.release();
  }
}

const TRINCO_MINUTO = 7_301;
const TRINCO_DIARIO = 7_302;

export interface OpcoesAgendador {
  intervaloMinutoMs?: number;
  intervaloDiarioMs?: number;
  /** Espera antes do primeiro trabalho diário (dá tempo ao servidor para arrancar). */
  atrasoInicialMs?: number;
}

/** Arranca os trabalhos periódicos. Devolve uma função que os pára. Um trabalho nunca se sobrepõe a si próprio. */
export function iniciarAgendador(c: Contexto, o: OpcoesAgendador = {}): () => void {
  const correr = (nome: string, chave: number, f: () => Promise<unknown>) => {
    let emCurso = false;
    return async () => {
      if (emCurso) return;
      emCurso = true;
      try {
        await comTrinco(c.db, chave, f);
      } catch (e) {
        console.error(`Trabalho "${nome}" falhou:`, e instanceof Error ? e.message : 'desconhecido');
      } finally {
        emCurso = false;
      }
    };
  };
  const minuto = correr('minuto', TRINCO_MINUTO, () => trabalhosDoMinuto(c));
  const diario = correr('diário', TRINCO_DIARIO, () => trabalhosDiarios(c));

  const t1 = setInterval(minuto, o.intervaloMinutoMs ?? 60_000);
  const t2 = setInterval(diario, o.intervaloDiarioMs ?? 24 * 3_600_000);
  const t3 = setTimeout(() => void diario(), o.atrasoInicialMs ?? 15_000);
  return () => {
    clearInterval(t1);
    clearInterval(t2);
    clearTimeout(t3);
  };
}

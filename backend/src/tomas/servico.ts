import type { Db } from '../db.js';
import { gerarAgendamentos, type AgendaReceita } from './gerador.js';

/** Quantos dias à frente se mantêm tomas geradas (janela rolante). */
export const JANELA_DIAS = 90;
const DIA_MS = 86_400_000;

type Cliente = Pick<Db, 'query'>;

interface LinhaReceita {
  id: string;
  profile_id: string;
  tipo: 'intervalo' | 'horas_fixas';
  intervalo_horas: string | null;
  horas_locais: string[] | null;
  timezone: string;
  inicio_utc: Date;
  fim_utc: Date | null;
  ativa: boolean;
}

async function lerReceita(db: Cliente, receitaId: string): Promise<LinhaReceita | null> {
  const { rows } = await db.query<LinhaReceita>(
    `select id, profile_id, tipo, intervalo_horas::text as intervalo_horas,
            horas_locais::text[] as horas_locais, timezone, inicio_utc, fim_utc, ativa
       from receitas where id = $1`,
    [receitaId],
  );
  return rows[0] ?? null;
}

function paraAgenda(r: LinhaReceita): AgendaReceita {
  if (r.tipo === 'intervalo') {
    return { tipo: 'intervalo', intervaloHoras: Number(r.intervalo_horas), inicioUtc: r.inicio_utc, fimUtc: r.fim_utc };
  }
  return { tipo: 'horas_fixas', horasLocais: r.horas_locais ?? [], timezone: r.timezone, inicioUtc: r.inicio_utc, fimUtc: r.fim_utc };
}

/**
 * Gera as tomas de uma receita entre `de` e `ate`. Idempotente: uma toma que já existe
 * (mesma receita e mesma hora) nunca é duplicada nem alterada. Devolve quantas criou.
 */
export async function gerarTomas(db: Cliente, receitaId: string, de: Date, ate: Date): Promise<number> {
  const receita = await lerReceita(db, receitaId);
  if (!receita || !receita.ativa) return 0;
  const datas = gerarAgendamentos(paraAgenda(receita), de, ate);
  if (datas.length === 0) return 0;
  const res = await db.query(
    `insert into tomas (receita_id, profile_id, agendada_utc)
     select $1, $2, d from unnest($3::timestamptz[]) as d
     on conflict (receita_id, agendada_utc) do nothing`,
    [receita.id, receita.profile_id, datas],
  );
  return res.rowCount ?? 0;
}

/** Primeira geração de uma receita nova: do início da receita até ao fim da janela rolante. */
export async function gerarTomasIniciais(db: Cliente, receitaId: string, agora: Date): Promise<number> {
  const receita = await lerReceita(db, receitaId);
  if (!receita) return 0;
  return gerarTomas(db, receitaId, receita.inicio_utc, new Date(agora.getTime() + JANELA_DIAS * DIA_MS));
}

/**
 * Edição de uma receita: apaga só as tomas FUTURAS, ainda pendentes e que ninguém editou à mão,
 * e gera-as de novo com a receita atual. Tomas já registadas (tomadas, saltadas, falhadas),
 * passadas ou editadas manualmente nunca são tocadas.
 */
export async function regenerarTomasFuturas(db: Db, receitaId: string, agora: Date): Promise<number> {
  const cliente = await db.connect();
  try {
    await cliente.query('begin');
    await cliente.query(
      `delete from tomas
        where receita_id = $1 and agendada_utc > $2
          and estado = 'pendente' and editada_manualmente = false`,
      [receitaId, agora],
    );
    const criadas = await gerarTomas(cliente, receitaId, agora, new Date(agora.getTime() + JANELA_DIAS * DIA_MS));
    await cliente.query('commit');
    return criadas;
  } catch (e) {
    await cliente.query('rollback');
    throw e;
  } finally {
    cliente.release();
  }
}

/**
 * Trabalho diário: garante tomas geradas para os próximos JANELA_DIAS dias em todas as
 * receitas ativas. Só olha para o futuro, para nunca criar tomas "atrasadas" que nunca existiram.
 */
export async function manterJanela(db: Db, agora: Date): Promise<{ receitas: number; criadas: number }> {
  const { rows } = await db.query<{ id: string }>(
    `select id from receitas
      where ativa and (fim_utc is null or fim_utc > $1)`,
    [agora],
  );
  let criadas = 0;
  const ate = new Date(agora.getTime() + JANELA_DIAS * DIA_MS);
  for (const { id } of rows) {
    criadas += await gerarTomas(db, id, agora, ate);
  }
  return { receitas: rows.length, criadas };
}

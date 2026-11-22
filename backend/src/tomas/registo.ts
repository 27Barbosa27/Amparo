import { createHash } from 'node:crypto';
import { decifrar } from '../auth/cifra.js';
import { ErroAuth } from '../auth/erros.js';
import type { Db } from '../db.js';
import { chaveDoPerfil } from '../medicacao/servico.js';

/** Uma toma pendente só é "atrasada" depois desta tolerância (atrasada não é estado: é derivada). */
export const TOLERANCIA_ATRASO_MIN = 15;
/** Durante este tempo o registo pode ser revertido. */
export const DESFAZER_MS = 60_000;
/** Folga para relógios de telemóveis ligeiramente adiantados. */
const FOLGA_RELOGIO_MS = 60_000;
const HORA_ANTES_PREVISTA_MS = 24 * 3_600_000;

export type EstadoToma = 'pendente' | 'tomada' | 'saltada' | 'falhada';

/** Quem faz o registo: um cuidador (com conta) ou o telemóvel de uma pessoa. */
export type Autor = { userId: string } | { dispositivoId: string };

export interface TomaVista {
  id: string;
  receitaId: string;
  medicamento: { nome: string };
  dose: string;
  agendadaUtc: Date;
  estado: EstadoToma;
  atrasada: boolean;
  tomadaEmUtc: Date | null;
  origem: 'dispositivo' | 'cuidador' | null;
  /** Nome de quem registou, quando foi um cuidador ("Marcada pela Ana"). Nulo se foi a própria pessoa. */
  registadaPor: string | null;
  editadaManualmente: boolean;
  atualizadoEm: Date;
}

const SELECT_VISTA = `t.id, t.receita_id, t.agendada_utc, t.estado, t.tomada_em_utc, t.origem, t.editada_manualmente,
  t.atualizado_em, u.nome_exibicao as por_nome, m.nome_cifrado, r.dose_cifrada
  from tomas t join receitas r on r.id = t.receita_id join medicamentos m on m.id = r.medicamento_id
  left join users u on u.id = t.registada_por_user_id`;

type Linha = Record<string, any>;

export function paraVista(l: Linha, chave: Buffer, agora: Date): TomaVista {
  const agendada: Date = l.agendada_utc;
  return {
    id: l.id,
    receitaId: l.receita_id,
    medicamento: { nome: decifrar(l.nome_cifrado, chave) },
    dose: decifrar(l.dose_cifrada, chave),
    agendadaUtc: agendada,
    estado: l.estado,
    atrasada: l.estado === 'pendente' && agendada.getTime() + TOLERANCIA_ATRASO_MIN * 60_000 < agora.getTime(),
    tomadaEmUtc: l.tomada_em_utc,
    origem: l.origem,
    registadaPor: l.origem === 'cuidador' ? l.por_nome : null,
    editadaManualmente: l.editada_manualmente,
    atualizadoEm: l.atualizado_em,
  };
}

export interface Filtro {
  desde?: Date;
  de?: Date;
  ate?: Date;
}

/**
 * Tomas de um perfil. Com `desde` devolve só o que mudou depois dessa hora (sincronização delta) e
 * as tomas apagadas entretanto. Sem `desde` nem intervalo, devolve de ontem a daqui a 7 dias.
 */
export async function listarTomasVista(db: Db, mestra: Buffer, profileId: string, f: Filtro) {
  const agora = new Date();
  const chave = await chaveDoPerfil(db, profileId, mestra);
  const params: unknown[] = [profileId];
  const cond = ['t.profile_id = $1'];
  if (f.desde) cond.push(`t.atualizado_em > $${params.push(f.desde)}`);
  if (f.de || f.ate || !f.desde) {
    const de = f.de ?? new Date(agora.getTime() - 86_400_000);
    const ate = f.ate ?? new Date(agora.getTime() + 7 * 86_400_000);
    cond.push(`t.agendada_utc >= $${params.push(de)} and t.agendada_utc < $${params.push(ate)}`);
  }
  const { rows } = await db.query(`select ${SELECT_VISTA} where ${cond.join(' and ')} order by t.agendada_utc, t.id limit 5000`, params);
  let removidas: string[] = [];
  if (f.desde) {
    const r = await db.query('select toma_id from tomas_removidas where profile_id = $1 and removida_em > $2', [profileId, f.desde]);
    removidas = r.rows.map((x) => x.toma_id as string);
  }
  return {
    tomas: rows.map((l) => paraVista(l, chave, agora)),
    removidas,
    servidorAgora: agora,
    // Pequena sobreposição: um registo confirmado mesmo agora nunca fica de fora do próximo pedido.
    proximoDesde: new Date(agora.getTime() - 5_000),
  };
}

/** Uma toma com o histórico dos 7 dias anteriores da mesma receita. */
export async function detalheToma(db: Db, mestra: Buffer, profileId: string, tomaId: string) {
  const agora = new Date();
  const chave = await chaveDoPerfil(db, profileId, mestra);
  const { rows } = await db.query(`select ${SELECT_VISTA} where t.id = $1 and t.profile_id = $2`, [tomaId, profileId]);
  if (!rows[0]) return null;
  const toma = paraVista(rows[0], chave, agora);
  const h = await db.query(
    `select ${SELECT_VISTA} where t.receita_id = $1 and t.profile_id = $2 and t.id <> $3
       and t.agendada_utc >= $4::timestamptz - interval '7 days' and t.agendada_utc < $4 order by t.agendada_utc`,
    [toma.receitaId, profileId, tomaId, toma.agendadaUtc],
  );
  return { toma, historico7dias: h.rows.map((l) => paraVista(l, chave, agora)) };
}

const chaveIdempotencia = (profileId: string, tomaId: string, chave: string) =>
  createHash('sha256').update(`${profileId}:${tomaId}:${chave}`).digest('hex');

interface Registo {
  tomaId: string;
  profileId: string;
  autor: Autor;
  ip?: string;
  idempotencyKey?: string;
  /** Quando o utilizador tocou (relevante para a fila offline). Por omissão, agora. */
  eventoEm?: Date;
  /** Hora real da toma: Agora / Há 1 hora / À hora prevista / Outra hora. */
  tomadaEmUtc?: Date;
}

async function auditar(db: Pick<Db, 'query'>, acao: string, tomaId: string, profileId: string, autor: Autor, ip?: string) {
  await db.query('insert into audit_logs (acao, entidade, entidade_id, user_id, profile_id, ip) values ($1, $2, $3, $4, $5, $6)', [
    acao, 'toma', tomaId, 'userId' in autor ? autor.userId : null, profileId, ip ?? null,
  ]);
}

/** Aplica uma mudança de estado a uma toma, tudo ou nada, com idempotência e resolução de conflitos. */
async function mudarEstado(db: Db, r: Registo, estado: 'tomada' | 'saltada'): Promise<{ estado: EstadoToma; repetido: boolean }> {
  const cliente = await db.connect();
  try {
    await cliente.query('begin');
    const { rows } = await cliente.query(
      'select estado, agendada_utc, registado_em, idempotency_key from tomas where id = $1 and profile_id = $2 for update',
      [r.tomaId, r.profileId],
    );
    const t = rows[0];
    if (!t) throw new ErroAuth('toma_nao_encontrada', 404);

    const agora = new Date();
    const chave = r.idempotencyKey ? chaveIdempotencia(r.profileId, r.tomaId, r.idempotencyKey) : null;
    // Reenvio do mesmo pedido (fila offline): devolve o resultado sem fazer nada.
    if (chave && t.idempotency_key === chave) {
      await cliente.query('rollback');
      return { estado: t.estado, repetido: true };
    }

    // O evento nunca é do futuro (relógio do telemóvel adiantado): fica limitado a agora.
    const evento = r.eventoEm ? new Date(Math.min(r.eventoEm.getTime(), agora.getTime())) : agora;
    if (t.estado === 'tomada' || t.estado === 'saltada') {
      // Conflito: ganha o evento mais recente.
      const maisRecente = r.eventoEm && t.registado_em && evento.getTime() > t.registado_em.getTime();
      if (!maisRecente) throw new ErroAuth('toma_ja_registada', 409);
    }

    let tomadaEm: Date | null = null;
    if (estado === 'tomada') {
      tomadaEm = r.tomadaEmUtc ?? evento;
      const minimo = t.agendada_utc.getTime() - HORA_ANTES_PREVISTA_MS;
      if (tomadaEm.getTime() > agora.getTime() + FOLGA_RELOGIO_MS || tomadaEm.getTime() < minimo) throw new ErroAuth('hora_invalida', 400);
    }

    await cliente.query(
      `update tomas set estado = $2, tomada_em_utc = $3, registado_em = $4, registada_por_user_id = $5,
              origem = $6, idempotency_key = $7
        where id = $1`,
      [r.tomaId, estado, tomadaEm, evento, 'userId' in r.autor ? r.autor.userId : null, 'userId' in r.autor ? 'cuidador' : 'dispositivo', chave],
    );
    await auditar(cliente, estado === 'tomada' ? 'toma.registar' : 'toma.saltar', r.tomaId, r.profileId, r.autor, r.ip);
    await cliente.query('commit');
    return { estado, repetido: false };
  } catch (e) {
    await cliente.query('rollback').catch(() => undefined);
    throw e;
  } finally {
    cliente.release();
  }
}

export const marcarTomada = (db: Db, r: Registo) => mudarEstado(db, r, 'tomada');
export const saltarToma = (db: Db, r: Registo) => mudarEstado(db, r, 'saltada');

/** Reverte um registo feito há menos de 1 minuto: a toma volta a `pendente`. Depois disso, só por edição explícita. */
export async function desfazerRegisto(db: Db, r: Pick<Registo, 'tomaId' | 'profileId' | 'autor' | 'ip'>): Promise<EstadoToma> {
  const cliente = await db.connect();
  try {
    await cliente.query('begin');
    const { rows } = await cliente.query('select estado, registado_em from tomas where id = $1 and profile_id = $2 for update', [r.tomaId, r.profileId]);
    const t = rows[0];
    if (!t) throw new ErroAuth('toma_nao_encontrada', 404);
    if (t.estado === 'pendente') {
      await cliente.query('rollback');
      return 'pendente'; // já está desfeito: o reenvio não faz mal
    }
    if (t.estado === 'falhada' || !t.registado_em || Date.now() - t.registado_em.getTime() > DESFAZER_MS) {
      throw new ErroAuth('desfazer_expirado', 409);
    }
    await cliente.query(
      `update tomas set estado = 'pendente', tomada_em_utc = null, registado_em = null,
              registada_por_user_id = null, origem = null, idempotency_key = null where id = $1`,
      [r.tomaId],
    );
    await auditar(cliente, 'toma.desfazer', r.tomaId, r.profileId, r.autor, r.ip);
    await cliente.query('commit');
    return 'pendente';
  } catch (e) {
    await cliente.query('rollback').catch(() => undefined);
    throw e;
  } finally {
    cliente.release();
  }
}

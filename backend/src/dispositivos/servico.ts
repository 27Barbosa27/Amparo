import { createHmac, randomBytes, randomInt } from 'node:crypto';
import { ErroAuth } from '../auth/erros.js';
import { PREFIXO_DISPOSITIVO } from '../auth/principal.js';
import { hashRefreshToken } from '../auth/tokens.js';
import type { Db } from '../db.js';

export const CODIGO_VALIDADE_MIN = 15;

type Cliente = Pick<Db, 'query'>;

async function auditar(db: Cliente, acao: string, entidade: string, entidadeId: string, userId: string | null, profileId: string, ip?: string) {
  await db.query('insert into audit_logs (acao, entidade, entidade_id, user_id, profile_id, ip) values ($1, $2, $3, $4, $5, $6)', [
    acao, entidade, entidadeId, userId, profileId, ip ?? null,
  ]);
}

/** Só o hash do código fica guardado (6 dígitos têm pouca entropia: o segredo impede pré-cálculo). */
const hashCodigo = (codigo: string, pepper: string) => createHmac('sha256', pepper).update(`ligacao:${codigo}`).digest();

/** Gera um código de ligação de 6 dígitos, válido 15 minutos e de uso único. Um código novo anula os anteriores do perfil. */
export async function criarCodigo(db: Db, pepper: string, userId: string, profileId: string, ip?: string) {
  const cliente = await db.connect();
  try {
    await cliente.query('begin');
    await cliente.query('update pairing_codes set expira_em = now() where profile_id = $1 and usado_em is null and expira_em > now()', [profileId]);
    let codigo = '';
    let hash = Buffer.alloc(0);
    for (let i = 0; i < 20; i++) {
      codigo = String(randomInt(0, 1_000_000)).padStart(6, '0');
      hash = hashCodigo(codigo, pepper);
      // Nunca dois códigos ativos iguais (senão não se saberia a que perfil pertence).
      const colisao = await cliente.query('select 1 from pairing_codes where codigo_hash = $1 and usado_em is null and expira_em > now()', [hash]);
      if (!colisao.rowCount) break;
      if (i === 19) throw new Error('sem códigos livres');
    }
    const { rows } = await cliente.query<{ id: string; expira_em: Date }>(
      `insert into pairing_codes (profile_id, criado_por_user_id, codigo_hash, expira_em)
       values ($1, $2, $3, now() + make_interval(mins => $4)) returning id, expira_em`,
      [profileId, userId, hash, CODIGO_VALIDADE_MIN],
    );
    await auditar(cliente, 'dispositivo.codigo_criar', 'pairing_code', rows[0]!.id, userId, profileId, ip);
    await cliente.query('commit');
    return { id: rows[0]!.id, codigo, expiraEm: rows[0]!.expira_em };
  } catch (e) {
    await cliente.query('rollback').catch(() => undefined);
    throw e;
  } finally {
    cliente.release();
  }
}

/** "À espera que a Rosa introduza o código…": o cuidador consulta o estado. */
export async function estadoCodigo(db: Db, profileId: string, id: string) {
  const { rows } = await db.query<{ usado_em: Date | null; expira_em: Date }>(
    'select usado_em, expira_em from pairing_codes where id = $1 and profile_id = $2',
    [id, profileId],
  );
  const c = rows[0];
  if (!c) return null;
  if (c.usado_em) return 'ligado' as const;
  return c.expira_em.getTime() > Date.now() ? ('a_espera' as const) : ('expirado' as const);
}

/**
 * A pessoa introduz o código no telemóvel dela. Código errado, expirado ou já usado dão a MESMA
 * resposta (para não revelar quais códigos existem). Devolve o token de dispositivo, só desta vez.
 */
export async function resgatarCodigo(db: Db, pepper: string, codigo: string, nome: string | null, ip?: string) {
  const cliente = await db.connect();
  try {
    await cliente.query('begin');
    const { rows } = await cliente.query<{ id: string; profile_id: string; criado_por_user_id: string }>(
      `select id, profile_id, criado_por_user_id from pairing_codes
        where codigo_hash = $1 and usado_em is null and expira_em > now() for update`,
      [hashCodigo(codigo, pepper)],
    );
    const c = rows[0];
    if (!c) {
      await cliente.query('rollback');
      throw new ErroAuth('codigo_invalido', 400);
    }
    await cliente.query('update pairing_codes set usado_em = now() where id = $1', [c.id]);
    const token = PREFIXO_DISPOSITIVO + randomBytes(32).toString('base64url');
    const d = await cliente.query<{ id: string }>(
      'insert into profile_devices (profile_id, token_hash, nome, ultimo_uso_em) values ($1, $2, $3, now()) returning id',
      [c.profile_id, hashRefreshToken(token), nome],
    );
    await auditar(cliente, 'dispositivo.ligar', 'profile_device', d.rows[0]!.id, c.criado_por_user_id, c.profile_id, ip);
    await cliente.query('commit');
    const p = await db.query(
      'select id, pseudonimo, timezone, tamanho_texto, alarmes_em from profiles where id = $1',
      [c.profile_id],
    );
    const l = p.rows[0];
    return {
      token,
      dispositivoId: d.rows[0]!.id,
      perfil: { id: l.id, pseudonimo: l.pseudonimo, timezone: l.timezone, tamanhoTexto: l.tamanho_texto, alarmesEm: l.alarmes_em },
    };
  } catch (e) {
    await cliente.query('rollback').catch(() => undefined);
    throw e;
  } finally {
    cliente.release();
  }
}

export async function listarDispositivos(db: Db, profileId: string) {
  const { rows } = await db.query(
    `select id, nome, criado_em, ultimo_uso_em, alarmes_agendados, permissoes_alarme
       from profile_devices where profile_id = $1 and revogado_em is null order by criado_em, id`,
    [profileId],
  );
  return rows.map((r) => ({
    id: r.id as string,
    nome: r.nome as string | null,
    ligadoDesde: r.criado_em as Date,
    ultimaLigacao: r.ultimo_uso_em as Date | null,
    alarmesAgendados: r.alarmes_agendados as number | null,
    permissoes: r.permissoes_alarme as Record<string, boolean> | null,
  }));
}

/** Revoga o dispositivo: o telemóvel perdido deixa de funcionar de imediato (e deixa de receber push). */
export async function revogarDispositivo(db: Db, userId: string, profileId: string, deviceId: string, ip?: string): Promise<boolean> {
  const res = await db.query('update profile_devices set revogado_em = now() where id = $1 and profile_id = $2 and revogado_em is null', [deviceId, profileId]);
  if (!res.rowCount) return false;
  await db.query('update push_tokens set revogado_em = now() where device_id = $1 and revogado_em is null', [deviceId]);
  await auditar(db, 'dispositivo.revogar', 'profile_device', deviceId, userId, profileId, ip);
  return true;
}

export interface EstadoTelemovel {
  alarmesAgendados: number;
  permissoes: { alarmesExatos: boolean; bateriaSemLimites: boolean; ecraBloqueado: boolean };
}

/** O telemóvel da pessoa reporta quantos alarmes tem agendados e o estado das permissões. */
export async function registarHeartbeat(db: Db, deviceId: string, e: EstadoTelemovel): Promise<void> {
  await db.query(
    'update profile_devices set alarmes_agendados = $2, permissoes_alarme = $3, ultimo_uso_em = now() where id = $1',
    [deviceId, e.alarmesAgendados, JSON.stringify(e.permissoes)],
  );
}

import { createHash } from 'node:crypto';
import { cifrar, decifrar } from '../auth/cifra.js';
import type { Db } from '../db.js';
import { dispararSemFalhar, type Eventos, type ResultadoLembrete } from '../eventos.js';
import type { EnviadorPush, MensagemPush } from './enviador.js';

export type Dono = { userId: string } | { dispositivoId: string };
export type Plataforma = 'android' | 'ios';

const hashToken = (token: string) => createHash('sha256').update(token).digest();

/**
 * Regista o token FCM de um telemóvel (do cuidador ou da pessoa). O hash encontra-o; o token em claro só
 * existe cifrado, para o conseguir usar no envio. Registar outra vez o mesmo token reativa-o e muda-lhe o dono.
 */
export async function registarToken(db: Db, chaveCampos: Buffer, dono: Dono, plataforma: Plataforma, token: string): Promise<void> {
  await db.query(
    `insert into push_tokens (user_id, device_id, plataforma, fcm_token_hash, fcm_token_cifrado, ultimo_uso_em)
     values ($1, $2, $3, $4, $5, now())
     on conflict (fcm_token_hash) do update set user_id = $1, device_id = $2, plataforma = $3,
       fcm_token_cifrado = $5, ultimo_uso_em = now(), revogado_em = null`,
    [
      'userId' in dono ? dono.userId : null,
      'dispositivoId' in dono ? dono.dispositivoId : null,
      plataforma,
      hashToken(token),
      cifrar(token, chaveCampos),
    ],
  );
}

/** Só apaga um token que seja do próprio (ninguém revoga os tokens de outro). */
export async function removerToken(db: Db, dono: Dono, token: string): Promise<boolean> {
  const res = await db.query(
    `update push_tokens set revogado_em = now()
      where fcm_token_hash = $1 and revogado_em is null and user_id is not distinct from $2 and device_id is not distinct from $3`,
    [hashToken(token), 'userId' in dono ? dono.userId : null, 'dispositivoId' in dono ? dono.dispositivoId : null],
  );
  return (res.rowCount ?? 0) > 0;
}

async function tokensAtivos(db: Db, chaveCampos: Buffer, filtro: { userIds?: string[]; profileId?: string }): Promise<string[]> {
  const { rows } = await db.query<{ fcm_token_cifrado: Buffer }>(
    `select p.fcm_token_cifrado from push_tokens p
      where p.revogado_em is null and p.fcm_token_cifrado is not null
        and ((p.user_id = any($1::uuid[]))
          or (p.device_id in (select id from profile_devices where profile_id = $2 and revogado_em is null)))`,
    [filtro.userIds ?? [], filtro.profileId ?? null],
  );
  return rows.map((r) => decifrar(r.fcm_token_cifrado, chaveCampos));
}

/** Envia e apaga os tokens que o FCM rejeitou. Nunca lança: o push é um extra, nunca a garantia de um alarme. */
async function enviarERevogar(db: Db, enviador: EnviadorPush, tokens: string[], m: MensagemPush): Promise<void> {
  if (tokens.length === 0) return;
  const { invalidos } = await enviador.enviar(tokens, m);
  if (invalidos.length) {
    await db.query('update push_tokens set revogado_em = now() where fcm_token_hash = any($1::bytea[])', [invalidos.map(hashToken)]);
  }
}

/** Alerta aos telemóveis de cuidadores concretos. */
export async function alertarUtilizadores(db: Db, enviador: EnviadorPush, chaveCampos: Buffer, userIds: string[], m: MensagemPush): Promise<void> {
  if (userIds.length === 0) return;
  await enviarERevogar(db, enviador, await tokensAtivos(db, chaveCampos, { userIds }), m);
}

/** Pede aos telemóveis ligados ao perfil que vão buscar as mudanças. */
export async function sincronizarDispositivos(db: Db, enviador: EnviadorPush, chaveCampos: Buffer, profileId: string): Promise<void> {
  await enviarERevogar(db, enviador, await tokensAtivos(db, chaveCampos, { profileId }), { tipo: 'sync', perfil: profileId });
}

/** Um lembrete por cuidador e por toma em cada janela de 5 minutos. */
const JANELA_LEMBRETE_MS = 5 * 60_000;

/** "Lembrar": volta a mostrar o alarme da toma nos telemóveis ligados ao perfil. */
export async function lembrarToma(
  db: Db,
  enviador: EnviadorPush,
  chaveCampos: Buffer,
  profileId: string,
  tomaId: string,
  porUserId: string,
  agora = Date.now(),
): Promise<ResultadoLembrete> {
  const { rows } = await db.query<{ fcm_token_cifrado: Buffer }>(
    `select p.fcm_token_cifrado from push_tokens p join profile_devices d on d.id = p.device_id
      where d.profile_id = $1 and d.revogado_em is null and p.revogado_em is null and p.fcm_token_cifrado is not null`,
    [profileId],
  );
  if (rows.length === 0) return 'sem_telemovel';
  if (!(await marcarAlertaEnviado(db, porUserId, 'lembrete', `${tomaId}:${Math.floor(agora / JANELA_LEMBRETE_MS)}`))) return 'recente';
  const tokens = rows.map((r) => decifrar(r.fcm_token_cifrado, chaveCampos));
  await enviarERevogar(db, enviador, tokens, { tipo: 'lembrete', perfil: profileId, toma: tomaId });
  return 'enviado';
}

/** Regista um alerta como enviado. Devolve falso se já tinha sido (para nunca avisar duas vezes). */
export async function marcarAlertaEnviado(db: Db, userId: string, tipo: string, chave: string): Promise<boolean> {
  const r = await db.query('insert into alertas_enviados (user_id, tipo, chave) values ($1, $2, $3) on conflict do nothing', [userId, tipo, chave]);
  return (r.rowCount ?? 0) > 0;
}

/** Os ganchos que ligam o resto do backend ao push. */
export function criarEventosPush(db: Db, enviador: EnviadorPush, chaveCampos: Buffer): Eventos {
  return {
    async tomaRegistada(profileId, tomaId, porUserId) {
      // Quem quer ser avisado de "toma feita" (menos quem a marcou) e ainda tem acesso ao perfil.
      const { rows } = await db.query<{ user_id: string }>(
        `select a.user_id from alert_prefs a join profile_access pa on pa.user_id = a.user_id and pa.profile_id = a.profile_id
          where a.profile_id = $1 and a.toma_feita and pa.revogado_em is null and ($2::uuid is null or a.user_id <> $2)`,
        [profileId, porUserId],
      );
      const novos: string[] = [];
      for (const { user_id } of rows) if (await marcarAlertaEnviado(db, user_id, 'toma_feita', tomaId)) novos.push(user_id);
      await alertarUtilizadores(db, enviador, chaveCampos, novos, { tipo: 'alerta', perfil: profileId, subtipo: 'toma_feita' });
    },
    async sincronizar(profileId) {
      await sincronizarDispositivos(db, enviador, chaveCampos, profileId);
    },
    lembrar(profileId, tomaId, porUserId) {
      return lembrarToma(db, enviador, chaveCampos, profileId, tomaId, porUserId);
    },
  };
}

export { dispararSemFalhar };

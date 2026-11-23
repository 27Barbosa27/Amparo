import { randomBytes } from 'node:crypto';
import type { Db } from '../db.js';
import type { EnviadorEmail } from '../email/enviador.js';
import { decifrar } from './cifra.js';
import { hashEmail } from './email.js';
import { ErroAuth } from './erros.js';
import { auditar, type SegredosAuth } from './servico.js';
import { hashSenha } from './senha.js';
import { hashRefreshToken } from './tokens.js';

export const VALIDADE_MIN = 30;
/** No máximo este número de pedidos por conta e por hora (impede inundar a caixa de entrada de alguém). */
const MAX_PEDIDOS_HORA = 3;

export interface OpcoesRecuperacao {
  enviador: EnviadorEmail;
  /** Endereço base do link que abre a app (link direto), por exemplo `https://amparo.pt/repor`. */
  linkBase: string;
}

/**
 * Pede a recuperação. A resposta ao cliente é SEMPRE a mesma, exista a conta ou não, para não revelar contas.
 * O email só se envia a contas com palavra-passe e só depois de a resposta sair (o tempo não denuncia nada).
 * O token em claro só existe no email; na base de dados fica o hash.
 */
export async function pedirRecuperacao(db: Db, email: string, segredos: SegredosAuth, o: OpcoesRecuperacao, ip?: string): Promise<void> {
  const { rows } = await db.query<{ id: string; email_cifrado: Buffer | null }>(
    'select id, email_cifrado from users where email_hash = $1 and password_hash is not null',
    [hashEmail(email, segredos.emailPepper)],
  );
  const u = rows[0];
  if (!u?.email_cifrado) return;
  const recentes = await db.query<{ n: number }>("select count(*)::int n from password_resets where user_id = $1 and criado_em > now() - interval '1 hour'", [u.id]);
  if (recentes.rows[0]!.n >= MAX_PEDIDOS_HORA) return;

  const token = randomBytes(32).toString('base64url');
  // Um pedido novo invalida os anteriores.
  await db.query('update password_resets set expira_em = now() where user_id = $1 and usado_em is null and expira_em > now()', [u.id]);
  await db.query('insert into password_resets (user_id, token_hash, expira_em) values ($1, $2, now() + make_interval(mins => $3))', [u.id, hashRefreshToken(token), VALIDADE_MIN]);
  await auditar(db, 'auth.recuperacao_pedida', u.id, ip);

  const link = `${o.linkBase}?token=${token}`;
  const para = decifrar(u.email_cifrado, segredos.emailChave);
  // Sem await: a resposta não espera pelo servidor de email. Um erro de envio nunca chega ao cliente (nem a um log com o endereço).
  void o.enviador
    .enviar({
      para,
      assunto: 'Amparo: definir uma nova palavra-passe',
      texto:
        `Pediu para definir uma nova palavra-passe no Amparo.\n\nAbra esta ligação (vale ${VALIDADE_MIN} minutos e só pode ser usada uma vez):\n${link}\n\n` +
        'Se não foi você, ignore este email: a sua palavra-passe não muda.',
    })
    .catch((e) => console.error('Recuperação: falha ao enviar o email:', e instanceof Error ? e.message : 'desconhecido'));
}

/**
 * Define a nova palavra-passe com o token do email. Token errado, expirado ou já usado dão a mesma resposta.
 * Depois de mudar, TODAS as sessões ficam revogadas e o bloqueio por falhas é limpo.
 */
export async function reporSenha(db: Db, token: string, novaSenha: string, ip?: string): Promise<void> {
  const senhaHash = await hashSenha(novaSenha);
  const c = await db.connect();
  try {
    await c.query('begin');
    const { rows } = await c.query<{ id: string; user_id: string }>(
      'select id, user_id from password_resets where token_hash = $1 and usado_em is null and expira_em > now() for update',
      [hashRefreshToken(token)],
    );
    const r = rows[0];
    if (!r) {
      await c.query('rollback');
      throw new ErroAuth('token_invalido', 400);
    }
    await c.query('update password_resets set usado_em = now() where id = $1', [r.id]);
    await c.query('update users set password_hash = $2, falhas_login = 0, bloqueado_ate = null where id = $1', [r.user_id, senhaHash]);
    await c.query('update refresh_tokens set revogado_em = now() where user_id = $1 and revogado_em is null', [r.user_id]);
    await auditar(c, 'auth.senha_reposta', r.user_id, ip);
    await c.query('commit');
  } catch (e) {
    await c.query('rollback').catch(() => undefined);
    throw e;
  } finally {
    c.release();
  }
}

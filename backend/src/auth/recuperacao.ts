import { createHmac, randomInt, timingSafeEqual } from 'node:crypto';
import type { Db } from '../db.js';
import type { EnviadorEmail } from '../email/enviador.js';
import { decifrar } from './cifra.js';
import { hashEmail } from './email.js';
import { ErroAuth } from './erros.js';
import { auditar, type SegredosAuth } from './servico.js';
import { hashSenha } from './senha.js';

export const VALIDADE_MIN = 5;
/** No máximo este número de pedidos por conta e por hora (impede inundar a caixa de entrada de alguém). */
const MAX_PEDIDOS_HORA = 15;
/** Depois deste número de códigos errados, o código deixa de valer (6 dígitos só são seguros com este limite). */
export const MAX_TENTATIVAS = 5;

export interface OpcoesRecuperacao {
  enviador: EnviadorEmail;
}

/** O que se guarda do código: um HMAC que depende da conta, por isso dois utilizadores nunca partilham o hash. */
const hashCodigo = (userId: string, codigo: string, pepper: string) =>
  createHmac('sha256', pepper).update(`recuperacao:${userId}:${codigo}`).digest();

/**
 * Pede a recuperação. A resposta ao cliente é SEMPRE a mesma, exista a conta ou não, para não revelar contas.
 * O email só se envia a contas com palavra-passe e só depois de a resposta sair (o tempo não denuncia nada).
 * O código de 6 dígitos só existe no email; na base de dados fica o hash.
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

  const codigo = String(randomInt(0, 1_000_000)).padStart(6, '0');
  // Um pedido novo invalida os anteriores.
  await db.query('update password_resets set expira_em = now() where user_id = $1 and usado_em is null and expira_em > now()', [u.id]);
  await db.query('insert into password_resets (user_id, token_hash, expira_em) values ($1, $2, now() + make_interval(mins => $3))', [
    u.id,
    hashCodigo(u.id, codigo, segredos.emailPepper),
    VALIDADE_MIN,
  ]);
  await auditar(db, 'auth.recuperacao_pedida', u.id, ip);

  const para = decifrar(u.email_cifrado, segredos.emailChave);
  // Sem await: a resposta não espera pelo servidor de email. Um erro de envio nunca chega ao cliente (nem a um log com o endereço).
  void o.enviador
    .enviar({
      para,
      assunto: 'Amparo: o seu código para definir uma nova palavra-passe',
      texto:
        `Pediu para definir uma nova palavra-passe no Amparo.

Escreva este código na app:

${codigo.slice(0, 3)} ${codigo.slice(3)}

` +
        `Vale ${VALIDADE_MIN} minutos e só pode ser usado uma vez.

` +
        'Se não foi você, ignore este email: a sua palavra-passe não muda.',
    })
    .catch((e) => console.error('Recuperação: falha ao enviar o email:', e instanceof Error ? e.message : 'desconhecido'));
}

/**
 * Confirma o código SEM o gastar: serve para a app só deixar escolher a palavra-passe depois de o código estar
 * certo. Conta as tentativas erradas exatamente como a reposição (5 erros e o código deixa de valer).
 */
export async function verificarCodigo(db: Db, email: string, codigo: string, segredos: SegredosAuth, ip?: string): Promise<void> {
  const c = await db.connect();
  try {
    await c.query('begin');
    const u = await c.query<{ id: string }>('select id from users where email_hash = $1', [hashEmail(email, segredos.emailPepper)]);
    const userId = u.rows[0]?.id;
    const { rows } = userId
      ? await c.query<{ id: string; token_hash: Buffer }>(
          `select id, token_hash from password_resets
            where user_id = $1 and usado_em is null and expira_em > now() and tentativas < $2
            order by criado_em desc limit 1 for update`,
          [userId, MAX_TENTATIVAS],
        )
      : { rows: [] };
    const r = rows[0];
    if (!userId || !r) {
      await c.query('rollback');
      throw new ErroAuth('token_invalido', 400);
    }
    if (!timingSafeEqual(r.token_hash, hashCodigo(userId, codigo, segredos.emailPepper))) {
      await c.query('update password_resets set tentativas = tentativas + 1 where id = $1', [r.id]);
      await auditar(c, 'auth.recuperacao_codigo_errado', userId, ip);
      await c.query('commit');
      throw new ErroAuth('token_invalido', 400);
    }
    await c.query('commit');
  } catch (e) {
    await c.query('rollback').catch(() => undefined);
    throw e;
  } finally {
    c.release();
  }
}

/**
 * Define a nova palavra-passe com o código do email. Email desconhecido, código errado, expirado, já usado ou
 * esgotado (5 erros) dão todos a mesma resposta. Cada código errado conta; ao 5.º o código deixa de valer.
 * Depois de mudar, TODAS as sessões ficam revogadas e o bloqueio por falhas é limpo.
 */
export async function reporSenha(db: Db, email: string, codigo: string, novaSenha: string, segredos: SegredosAuth, ip?: string): Promise<void> {
  // O hash da palavra-passe gasta tempo em todos os casos, para a resposta não revelar se a conta existe.
  const senhaHash = await hashSenha(novaSenha);
  const c = await db.connect();
  try {
    await c.query('begin');
    const u = await c.query<{ id: string }>('select id from users where email_hash = $1', [hashEmail(email, segredos.emailPepper)]);
    const userId = u.rows[0]?.id;
    const { rows } = userId
      ? await c.query<{ id: string; token_hash: Buffer }>(
          `select id, token_hash from password_resets
            where user_id = $1 and usado_em is null and expira_em > now() and tentativas < $2
            order by criado_em desc limit 1 for update`,
          [userId, MAX_TENTATIVAS],
        )
      : { rows: [] };
    const r = rows[0];
    if (!userId || !r) {
      await c.query('rollback');
      throw new ErroAuth('token_invalido', 400);
    }
    const certo = timingSafeEqual(r.token_hash, hashCodigo(userId, codigo, segredos.emailPepper));
    if (!certo) {
      // Conta a tentativa (e grava-a: não se desfaz) antes de recusar.
      await c.query('update password_resets set tentativas = tentativas + 1 where id = $1', [r.id]);
      await auditar(c, 'auth.recuperacao_codigo_errado', userId, ip);
      await c.query('commit');
      throw new ErroAuth('token_invalido', 400);
    }
    await c.query('update password_resets set usado_em = now() where id = $1', [r.id]);
    await c.query('update users set password_hash = $2, falhas_login = 0, bloqueado_ate = null where id = $1', [userId, senhaHash]);
    await c.query('update refresh_tokens set revogado_em = now() where user_id = $1 and revogado_em is null', [userId]);
    await auditar(c, 'auth.senha_reposta', userId, ip);
    await c.query('commit');
  } catch (e) {
    await c.query('rollback').catch(() => undefined);
    throw e;
  } finally {
    c.release();
  }
}

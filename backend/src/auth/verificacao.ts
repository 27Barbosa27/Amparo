import { createHmac, randomInt, timingSafeEqual } from 'node:crypto';
import type { Db } from '../db.js';
import type { EnviadorEmail } from '../email/enviador.js';
import { decifrar } from './cifra.js';
import { hashEmail } from './email.js';
import { ErroAuth } from './erros.js';
import { abrirSessao, auditar, type SegredosAuth, type Sessao } from './servico.js';

export const VALIDADE_VERIFICACAO_MIN = 10;
/** No máximo este número de códigos por conta e por hora (impede inundar a caixa de entrada de alguém). */
const MAX_PEDIDOS_HORA = 10;
/** Depois deste número de códigos errados, o código deixa de valer (6 dígitos só são seguros com este limite). */
export const MAX_TENTATIVAS_VERIFICACAO = 5;

/** O que se guarda do código: um HMAC que depende da conta, por isso dois utilizadores nunca partilham o hash. */
const hashCodigo = (userId: string, codigo: string, pepper: string) =>
  createHmac('sha256', pepper).update(`verificacao:${userId}:${codigo}`).digest();

/**
 * Cria um código novo (os anteriores deixam de valer) e envia-o para o email da conta. Sem `await` no envio: a
 * resposta não espera pelo servidor de email, e uma falha de envio nunca chega ao cliente.
 */
export async function enviarCodigoVerificacao(
  db: Db,
  userId: string,
  email: string,
  segredos: SegredosAuth,
  enviador: EnviadorEmail,
  ip?: string,
): Promise<void> {
  const recentes = await db.query<{ n: number }>(
    "select count(*)::int n from email_verificacoes where user_id = $1 and criado_em > now() - interval '1 hour'",
    [userId],
  );
  if (recentes.rows[0]!.n >= MAX_PEDIDOS_HORA) return;

  const codigo = String(randomInt(0, 1_000_000)).padStart(6, '0');
  await db.query('update email_verificacoes set expira_em = now() where user_id = $1 and usado_em is null and expira_em > now()', [userId]);
  await db.query('insert into email_verificacoes (user_id, codigo_hash, expira_em) values ($1, $2, now() + make_interval(mins => $3))', [
    userId,
    hashCodigo(userId, codigo, segredos.emailPepper),
    VALIDADE_VERIFICACAO_MIN,
  ]);
  await auditar(db, 'auth.verificacao_enviada', userId, ip);

  void enviador
    .enviar({
      para: email,
      assunto: 'Amparo: o seu código de verificação',
      texto:
        `Para confirmar o seu email no Amparo, escreva este código na app:\n\n${codigo.slice(0, 3)} ${codigo.slice(3)}\n\n` +
        `Vale ${VALIDADE_VERIFICACAO_MIN} minutos e só pode ser usado uma vez.\n\n` +
        'Se não criou uma conta no Amparo, ignore este email.',
    })
    .catch((e) => console.error('Verificação: falha ao enviar o email:', e instanceof Error ? e.message : 'desconhecido'));
}

/**
 * Pede outro código a quem ainda não verificou o email. A resposta ao cliente é sempre a mesma (exista a conta ou
 * não, esteja verificada ou não): só se envia a contas com palavra-passe e por verificar.
 */
export async function reenviarCodigoVerificacao(db: Db, email: string, segredos: SegredosAuth, enviador: EnviadorEmail, ip?: string): Promise<void> {
  const { rows } = await db.query<{ id: string; email_cifrado: Buffer | null }>(
    'select id, email_cifrado from users where email_hash = $1 and password_hash is not null and email_verificado_em is null',
    [hashEmail(email, segredos.emailPepper)],
  );
  const u = rows[0];
  if (!u?.email_cifrado) return;
  await enviarCodigoVerificacao(db, u.id, decifrar(u.email_cifrado, segredos.emailChave), segredos, enviador, ip);
}

/**
 * Confirma o email com o código. Email desconhecido, já verificado, código errado, expirado, usado ou esgotado
 * (5 erros) dão todos a mesma resposta. Se estiver certo, marca o email como verificado e abre a sessão.
 */
export async function confirmarEmail(
  db: Db,
  email: string,
  codigo: string,
  segredos: SegredosAuth,
  ip?: string,
): Promise<{ userId: string; nome: string | null; sessao: Sessao }> {
  const c = await db.connect();
  let userId: string;
  let nome: string | null;
  try {
    await c.query('begin');
    const u = await c.query<{ id: string; nome_exibicao: string | null }>(
      'select id, nome_exibicao from users where email_hash = $1 and email_verificado_em is null',
      [hashEmail(email, segredos.emailPepper)],
    );
    const user = u.rows[0];
    const { rows } = user
      ? await c.query<{ id: string; codigo_hash: Buffer }>(
          `select id, codigo_hash from email_verificacoes
            where user_id = $1 and usado_em is null and expira_em > now() and tentativas < $2
            order by criado_em desc limit 1 for update`,
          [user.id, MAX_TENTATIVAS_VERIFICACAO],
        )
      : { rows: [] };
    const r = rows[0];
    if (!user || !r) {
      await c.query('rollback');
      throw new ErroAuth('codigo_invalido', 400);
    }
    if (!timingSafeEqual(r.codigo_hash, hashCodigo(user.id, codigo, segredos.emailPepper))) {
      // Conta a tentativa (e grava-a: não se desfaz) antes de recusar.
      await c.query('update email_verificacoes set tentativas = tentativas + 1 where id = $1', [r.id]);
      await auditar(c, 'auth.verificacao_codigo_errado', user.id, ip);
      await c.query('commit');
      throw new ErroAuth('codigo_invalido', 400);
    }
    await c.query('update email_verificacoes set usado_em = now() where id = $1', [r.id]);
    await c.query('update users set email_verificado_em = now() where id = $1', [user.id]);
    await auditar(c, 'auth.email_verificado', user.id, ip);
    await c.query('commit');
    userId = user.id;
    nome = user.nome_exibicao;
  } catch (e) {
    await c.query('rollback').catch(() => undefined);
    throw e;
  } finally {
    c.release();
  }
  return { userId, nome, sessao: await abrirSessao(db, userId, segredos) };
}

import type { Db } from '../db.js';
import { cifrar, decifrar } from './cifra.js';
import { hashEmail, normalizarEmail } from './email.js';
import { ErroAuth } from './erros.js';
import { hashSenha, verificarContraHashFalso, verificarSenha } from './senha.js';
import {
  ACCESS_TTL_SEGUNDOS,
  REFRESH_TTL_MS,
  criarAccessToken,
  hashRefreshToken,
  novoRefreshToken,
} from './tokens.js';

export interface SegredosAuth {
  jwtSecret: string;
  emailPepper: string;
  /** Chave AES-256 (32 bytes) para cifrar o email. */
  emailChave: Buffer;
}

export interface Sessao {
  accessToken: string;
  refreshToken: string;
  expiraEmSegundos: number;
}

/** Depois de 5 falhas seguidas a conta fica bloqueada: 1, 2, 4, 8... minutos, no máximo 15. */
const FALHAS_ATE_BLOQUEIO = 5;
const BLOQUEIO_MAX_MIN = 15;

type Cliente = Pick<Db, 'query'>;

/** Registo de auditoria: só ids e o tipo de ação. Nunca emails, palavras-passe nem dados de saúde. */
export async function auditar(db: Cliente, acao: string, userId: string | null, ip: string | undefined): Promise<void> {
  await db.query('insert into audit_logs (acao, entidade, entidade_id, user_id, ip) values ($1, $2, $3, $3, $4)', [
    acao,
    userId ? 'user' : null,
    userId,
    ip ?? null,
  ]);
}

export async function abrirSessao(db: Cliente, userId: string, segredos: SegredosAuth, familiaId?: string): Promise<Sessao> {
  const { token, hash } = novoRefreshToken();
  const expira = new Date(Date.now() + REFRESH_TTL_MS);
  if (familiaId) {
    await db.query('insert into refresh_tokens (user_id, hash, expira_em, familia_id) values ($1, $2, $3, $4)', [
      userId, hash, expira, familiaId,
    ]);
  } else {
    await db.query('insert into refresh_tokens (user_id, hash, expira_em) values ($1, $2, $3)', [userId, hash, expira]);
  }
  return {
    accessToken: await criarAccessToken(userId, segredos.jwtSecret),
    refreshToken: token,
    expiraEmSegundos: ACCESS_TTL_SEGUNDOS,
  };
}

export interface DadosRegisto {
  email: string;
  senha: string;
  nome: string;
  consentimentoVersao: string;
}

export async function registar(
  db: Db,
  dados: DadosRegisto,
  segredos: SegredosAuth,
  ip?: string,
): Promise<{ userId: string; sessao: Sessao }> {
  const userId = await criarConta(db, dados, segredos, true, ip);
  return { userId, sessao: await abrirSessao(db, userId, segredos) };
}

/**
 * Cria a conta. Com `verificado` falso (o normal) o email fica por verificar e não se abre sessão. Se o email já
 * existe MAS nunca foi verificado, quem o registou antes nunca provou que era dele: a conta passa para quem
 * se regista agora (nova palavra-passe, novo nome), e o código vai para o email.
 */
export async function criarConta(db: Db, dados: DadosRegisto, segredos: SegredosAuth, verificado: boolean, ip?: string): Promise<string> {
  const senhaHash = await hashSenha(dados.senha);
  const { rows } = await db.query<{ id: string }>(
    `insert into users (email_hash, email_cifrado, password_hash, nome_exibicao, consentimento_versao, consentimento_em, email_verificado_em)
     values ($1, $2, $3, $4, $5, now(), case when $6 then now() end)
     on conflict (email_hash) do update
       set password_hash = excluded.password_hash, nome_exibicao = excluded.nome_exibicao,
           consentimento_versao = excluded.consentimento_versao, consentimento_em = now(), falhas_login = 0, bloqueado_ate = null
       where users.email_verificado_em is null and users.password_hash is not null
     returning id`,
    [
      hashEmail(dados.email, segredos.emailPepper),
      cifrar(normalizarEmail(dados.email), segredos.emailChave),
      senhaHash,
      dados.nome.trim(),
      dados.consentimentoVersao,
      verificado,
    ],
  );
  const userId = rows[0]?.id;
  if (!userId) throw new ErroAuth('email_ja_existe', 409);
  await auditar(db, 'auth.registo', userId, ip);
  return userId;
}

interface LinhaUser {
  id: string;
  password_hash: string | null;
  falhas_login: number;
  bloqueado_ate: Date | null;
  email_verificado_em: Date | null;
}

export async function entrar(
  db: Db,
  email: string,
  senha: string,
  segredos: SegredosAuth,
  ip?: string,
): Promise<{ userId: string; sessao: Sessao }> {
  const { rows } = await db.query<LinhaUser>(
    'select id, password_hash, falhas_login, bloqueado_ate, email_verificado_em from users where email_hash = $1',
    [hashEmail(email, segredos.emailPepper)],
  );
  const user = rows[0];

  if (!user) {
    await verificarContraHashFalso(senha); // mesmo tempo que uma conta real
    await auditar(db, 'auth.login_falhou', null, ip);
    throw new ErroAuth('credenciais_invalidas', 401);
  }

  if (user.bloqueado_ate && user.bloqueado_ate.getTime() > Date.now()) {
    await auditar(db, 'auth.login_bloqueado', user.id, ip);
    throw new ErroAuth('demasiadas_tentativas', 429);
  }

  const ok = user.password_hash ? await verificarSenha(user.password_hash, senha) : false;
  if (!ok) {
    const falhas = user.falhas_login + 1;
    const bloquear = falhas >= FALHAS_ATE_BLOQUEIO;
    const minutos = bloquear ? Math.min(2 ** (falhas - FALHAS_ATE_BLOQUEIO), BLOQUEIO_MAX_MIN) : 0;
    await db.query(
      'update users set falhas_login = $2, bloqueado_ate = case when $3 then now() + make_interval(mins => $4) else bloqueado_ate end where id = $1',
      [user.id, falhas, bloquear, minutos],
    );
    await auditar(db, 'auth.login_falhou', user.id, ip);
    throw new ErroAuth('credenciais_invalidas', 401);
  }

  await db.query('update users set falhas_login = 0, bloqueado_ate = null where id = $1', [user.id]);
  // A palavra-passe está certa, mas o email nunca foi confirmado: não se abre sessão (o servidor reenvia o código).
  if (!user.email_verificado_em) {
    await auditar(db, 'auth.login_sem_verificacao', user.id, ip);
    throw new ErroAuth('email_nao_verificado', 403);
  }
  await auditar(db, 'auth.login', user.id, ip);
  return { userId: user.id, sessao: await abrirSessao(db, user.id, segredos) };
}

interface LinhaRefresh {
  id: string;
  user_id: string;
  familia_id: string;
  expira_em: Date;
  revogado_em: Date | null;
}

/**
 * Troca um refresh token por um par novo (rotação). Um refresh token só pode ser usado uma vez:
 * se um já usado for apresentado outra vez (sinal de roubo), toda a família é revogada.
 */
export async function renovar(db: Db, refreshToken: string, segredos: SegredosAuth, ip?: string): Promise<Sessao> {
  const cliente = await db.connect();
  try {
    await cliente.query('begin');
    const { rows } = await cliente.query<LinhaRefresh>(
      'select id, user_id, familia_id, expira_em, revogado_em from refresh_tokens where hash = $1 for update',
      [hashRefreshToken(refreshToken)],
    );
    const t = rows[0];
    if (!t) {
      await cliente.query('rollback');
      throw new ErroAuth('refresh_invalido', 401);
    }
    if (t.revogado_em) {
      await cliente.query('update refresh_tokens set revogado_em = now() where familia_id = $1 and revogado_em is null', [t.familia_id]);
      await auditar(cliente, 'auth.refresh_reutilizado', t.user_id, ip);
      await cliente.query('commit'); // a revogação da família tem de ficar gravada
      throw new ErroAuth('refresh_invalido', 401);
    }
    if (t.expira_em.getTime() <= Date.now()) {
      await cliente.query('rollback');
      throw new ErroAuth('refresh_invalido', 401);
    }
    await cliente.query('update refresh_tokens set revogado_em = now() where id = $1', [t.id]);
    const sessao = await abrirSessao(cliente, t.user_id, segredos, t.familia_id);
    await cliente.query('commit');
    return sessao;
  } catch (e) {
    if (!(e instanceof ErroAuth)) await cliente.query('rollback').catch(() => undefined);
    throw e;
  } finally {
    cliente.release();
  }
}

/** Termina a sessão: revoga a família do refresh token. Não falha se o token for desconhecido. */
export async function sair(db: Db, refreshToken: string, ip?: string): Promise<void> {
  const { rows } = await db.query<{ user_id: string }>(
    `update refresh_tokens set revogado_em = now()
      where familia_id = (select familia_id from refresh_tokens where hash = $1) and revogado_em is null
      returning user_id`,
    [hashRefreshToken(refreshToken)],
  );
  if (rows[0]) await auditar(db, 'auth.logout', rows[0].user_id, ip);
}

export async function perfilDoUtilizador(
  db: Db,
  userId: string,
): Promise<{ id: string; nome: string | null; criadoEm: Date; temSenha: boolean } | null> {
  const { rows } = await db.query<{ id: string; nome_exibicao: string | null; criado_em: Date; tem_senha: boolean }>(
    'select id, nome_exibicao, criado_em, password_hash is not null as tem_senha from users where id = $1',
    [userId],
  );
  const r = rows[0];
  return r ? { id: r.id, nome: r.nome_exibicao, criadoEm: r.criado_em, temSenha: r.tem_senha } : null;
}

/**
 * Devolve o email em claro de um utilizador, para lhe enviar a recuperação de palavra-passe.
 * Só deve ser chamado por esse fluxo, e o resultado nunca deve ser registado nem devolvido à app.
 */
export async function emailParaEnvio(db: Db, userId: string, segredos: SegredosAuth): Promise<string | null> {
  const { rows } = await db.query<{ email_cifrado: Buffer | null }>('select email_cifrado from users where id = $1', [userId]);
  const dados = rows[0]?.email_cifrado;
  return dados ? decifrar(dados, segredos.emailChave) : null;
}

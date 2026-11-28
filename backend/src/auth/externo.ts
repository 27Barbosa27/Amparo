import { createHash } from 'node:crypto';
import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from 'jose';
import type { Db } from '../db.js';
import { cifrar } from './cifra.js';
import { hashEmail, normalizarEmail } from './email.js';
import { ErroAuth } from './erros.js';
import { abrirSessao, auditar, type SegredosAuth, type Sessao } from './servico.js';

export type Provedor = 'apple' | 'google';

export interface IdentidadeExterna {
  /** Identificador estável do utilizador no fornecedor. É a chave da associação (o email pode mudar ou ser um relay). */
  sub: string;
  email: string | null;
  emailVerificado: boolean;
}

export interface VerificadorExterno {
  /** Valida o ID token (assinatura, emissor, `aud`, `exp` e `nonce`). Lança `ErroAuth` se algo falhar. */
  verificar(provedor: Provedor, idToken: string, nonce: string): Promise<IdentidadeExterna>;
}

export interface ConfigExterna {
  appleClientIds?: string[];
  googleClientIds?: string[];
}

const EMISSORES: Record<Provedor, string[]> = {
  apple: ['https://appleid.apple.com'],
  google: ['https://accounts.google.com', 'accounts.google.com'],
};
const JWKS_URL: Record<Provedor, string> = {
  apple: 'https://appleid.apple.com/auth/keys',
  google: 'https://www.googleapis.com/oauth2/v3/certs',
};

/** Aceita o nonce em claro (Google) ou o seu SHA-256 em hexadecimal (a Apple costuma mandar o hash). */
function nonceConfere(noToken: unknown, nonce: string): boolean {
  if (typeof noToken !== 'string' || nonce.length < 8) return false;
  return noToken === nonce || noToken === createHash('sha256').update(nonce).digest('hex');
}

/**
 * Sem Firebase Authentication: o servidor valida ele próprio os ID tokens com as chaves públicas do fornecedor.
 * `chaves` permite injetar chaves locais nos testes.
 */
export function criarVerificadorExterno(cfg: ConfigExterna, chaves: Partial<Record<Provedor, JWTVerifyGetKey>> = {}): VerificadorExterno {
  const remotas: Partial<Record<Provedor, JWTVerifyGetKey>> = {};
  const chaveDe = (p: Provedor) => chaves[p] ?? (remotas[p] ??= createRemoteJWKSet(new URL(JWKS_URL[p])));
  return {
    async verificar(provedor, idToken, nonce) {
      const audiencias = provedor === 'apple' ? (cfg.appleClientIds ?? []) : (cfg.googleClientIds ?? []);
      if (audiencias.length === 0) throw new ErroAuth('provedor_nao_configurado', 501);
      try {
        const { payload } = await jwtVerify(idToken, chaveDe(provedor), {
          issuer: EMISSORES[provedor],
          audience: audiencias,
          algorithms: ['RS256'],
        });
        if (typeof payload.sub !== 'string' || payload.sub.length === 0) throw new Error('sem sub');
        if (!nonceConfere(payload.nonce, nonce)) throw new Error('nonce');
        const email = typeof payload.email === 'string' && payload.email.length <= 254 ? payload.email : null;
        const verificado = payload.email_verified === true || payload.email_verified === 'true';
        return { sub: payload.sub, email, emailVerificado: verificado };
      } catch (e) {
        if (e instanceof ErroAuth) throw e;
        throw new ErroAuth('provedor_invalido', 401);
      }
    },
  };
}

export interface ExtrasEntradaExterna {
  /** O nome só chega do fornecedor na primeira autorização (Apple): é a app que o envia. */
  nome?: string;
  aceitaTermos?: boolean;
  consentimentoVersao: string;
}

/**
 * Entra com Apple ou Google. Se o `sub` já está associado, entra. Se não, cria a conta (exige o consentimento explícito)
 * ou, quando o email verificado já pertence a uma conta, associa-lhe o fornecedor.
 * Só se associa por email verificado: um email não verificado nunca dá acesso a uma conta existente.
 */
export async function entrarComFornecedor(
  db: Db,
  provedor: Provedor,
  id: IdentidadeExterna,
  extras: ExtrasEntradaExterna,
  segredos: SegredosAuth,
  ip?: string,
): Promise<{ userId: string; nome: string | null; sessao: Sessao; novo: boolean }> {
  const existente = await db.query<{ user_id: string }>('select user_id from auth_providers where provedor = $1 and provider_sub = $2', [provedor, id.sub]);
  let userId = existente.rows[0]?.user_id;
  let novo = false;

  if (!userId) {
    const hash = id.email && id.emailVerificado ? hashEmail(id.email, segredos.emailPepper) : null;
    const porEmail = hash ? await db.query<{ id: string }>('select id from users where email_hash = $1', [hash]) : null;
    userId = porEmail?.rows[0]?.id;
    if (userId) {
      // O Google prova que o email é desta pessoa. Se a conta nunca foi verificada, quem a registou antes
      // não era o dono do email: confirma-se e anula-se a palavra-passe que essa pessoa pôs.
      await db.query(
        'update users set email_verificado_em = now(), password_hash = null where id = $1 and email_verificado_em is null',
        [userId],
      );
    }

    if (!userId) {
      if (extras.aceitaTermos !== true) throw new ErroAuth('consentimento_necessario', 400);
      const email = id.email && id.emailVerificado ? normalizarEmail(id.email) : null;
      const c = await db.query<{ id: string }>(
        `insert into users (email_hash, email_cifrado, nome_exibicao, consentimento_versao, consentimento_em, email_verificado_em)
         values ($1, $2, $3, $4, now(), case when $5 then now() end) returning id`,
        [hash, email ? cifrar(email, segredos.emailChave) : null, extras.nome?.trim() || null, extras.consentimentoVersao, email !== null],
      );
      userId = c.rows[0]!.id;
      novo = true;
    }
    const lig = await db.query('insert into auth_providers (user_id, provedor, provider_sub) values ($1, $2, $3) on conflict do nothing', [userId, provedor, id.sub]);
    if (!lig.rowCount) {
      // Outro pedido associou este `sub` entretanto: usa essa associação (e não deixa uma conta órfã).
      if (novo) await db.query('delete from users where id = $1', [userId]);
      const r = await db.query<{ user_id: string }>('select user_id from auth_providers where provedor = $1 and provider_sub = $2', [provedor, id.sub]);
      userId = r.rows[0]!.user_id;
      novo = false;
    }
  }

  await auditar(db, novo ? `auth.registo_${provedor}` : `auth.login_${provedor}`, userId, ip);
  const u = await db.query<{ nome_exibicao: string | null }>('select nome_exibicao from users where id = $1', [userId]);
  return { userId, nome: u.rows[0]?.nome_exibicao ?? null, sessao: await abrirSessao(db, userId, segredos), novo };
}

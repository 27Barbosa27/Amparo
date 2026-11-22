import { createHash, randomBytes } from 'node:crypto';
import { SignJWT, jwtVerify } from 'jose';

const EMISSOR = 'amparo';
const AUDIENCIA = 'amparo-app';
export const ACCESS_TTL_SEGUNDOS = 15 * 60;
export const REFRESH_TTL_MS = 30 * 24 * 60 * 60 * 1000;

const chave = (segredo: string) => new TextEncoder().encode(segredo);

export function criarAccessToken(userId: string, segredo: string): Promise<string> {
  return new SignJWT({ typ: 'access' })
    .setProtectedHeader({ alg: 'HS256' })
    .setSubject(userId)
    .setIssuer(EMISSOR)
    .setAudience(AUDIENCIA)
    .setIssuedAt()
    .setExpirationTime(`${ACCESS_TTL_SEGUNDOS}s`)
    .sign(chave(segredo));
}

/** Devolve o id do utilizador se o token for válido; senão lança. */
export async function verificarAccessToken(token: string, segredo: string): Promise<string> {
  const { payload } = await jwtVerify(token, chave(segredo), {
    issuer: EMISSOR,
    audience: AUDIENCIA,
    algorithms: ['HS256'],
  });
  if (payload.typ !== 'access' || typeof payload.sub !== 'string') throw new Error('token inválido');
  return payload.sub;
}

/** Token opaco aleatório (256 bits). Só o hash fica na base de dados. */
export function novoRefreshToken(): { token: string; hash: Buffer } {
  const token = randomBytes(32).toString('base64url');
  return { token, hash: hashRefreshToken(token) };
}

export function hashRefreshToken(token: string): Buffer {
  return createHash('sha256').update(token).digest();
}

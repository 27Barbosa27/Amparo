import { Algorithm, hash, verify } from '@node-rs/argon2';

// Argon2id com os parâmetros mínimos recomendados pela OWASP (19 MiB, 2 iterações, 1 fio).
const OPCOES = { algorithm: Algorithm.Argon2id, memoryCost: 19_456, timeCost: 2, parallelism: 1 } as const;

export function hashSenha(senha: string): Promise<string> {
  return hash(senha, OPCOES);
}

export async function verificarSenha(hashGuardado: string, senha: string): Promise<boolean> {
  try {
    return await verify(hashGuardado, senha);
  } catch {
    return false;
  }
}

let hashFalso: string | undefined;

/**
 * Gasta o mesmo tempo que uma verificação verdadeira. Usa-se quando o email não existe,
 * para a resposta não revelar (pelo tempo) se a conta existe.
 */
export async function verificarContraHashFalso(senha: string): Promise<void> {
  hashFalso ??= await hashSenha('hash-falso-para-igualar-o-tempo');
  await verificarSenha(hashFalso, senha);
}

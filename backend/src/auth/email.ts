import { createHmac } from 'node:crypto';

/** Normaliza para que "Ana@Exemplo.pt " e "ana@exemplo.pt" sejam a mesma conta. */
export function normalizarEmail(email: string): string {
  return email.normalize('NFKC').trim().toLowerCase();
}

/**
 * O email nunca é guardado em claro nesta tabela: guarda-se um HMAC com um segredo (pepper).
 * Serve para encontrar a conta e impedir duplicados, e não permite recuperar o email.
 */
export function hashEmail(email: string, pepper: string): Buffer {
  return createHmac('sha256', pepper).update(normalizarEmail(email)).digest();
}

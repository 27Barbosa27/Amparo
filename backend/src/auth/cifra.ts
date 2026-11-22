import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';

/**
 * Cifra de campos pessoais (por agora, o email, para o poder usar na recuperação de palavra-passe).
 * AES-256-GCM: confidencialidade e deteção de adulteração.
 * Formato guardado: [versão (1 byte)] [IV (12)] [etiqueta de autenticação (16)] [texto cifrado].
 * O byte de versão permite trocar de chave ou de algoritmo no futuro sem perder dados.
 */
const VERSAO = 1;
const IV_BYTES = 12;
const TAG_BYTES = 16;

/** A chave vem do ambiente em base64url e tem de ter exatamente 32 bytes. */
export function lerChave(chaveBase64Url: string): Buffer {
  const chave = Buffer.from(chaveBase64Url, 'base64url');
  if (chave.length !== 32) throw new Error('A chave de cifra tem de ter exatamente 32 bytes (base64url)');
  return chave;
}

export function cifrar(texto: string, chave: Buffer): Buffer {
  const iv = randomBytes(IV_BYTES);
  const cifra = createCipheriv('aes-256-gcm', chave, iv);
  const cifrado = Buffer.concat([cifra.update(texto, 'utf8'), cifra.final()]);
  return Buffer.concat([Buffer.from([VERSAO]), iv, cifra.getAuthTag(), cifrado]);
}

/** Lança se a chave estiver errada ou se os dados tiverem sido alterados. */
export function decifrar(dados: Buffer, chave: Buffer): string {
  if (dados.length < 1 + IV_BYTES + TAG_BYTES || dados[0] !== VERSAO) throw new Error('Dados cifrados inválidos');
  const iv = dados.subarray(1, 1 + IV_BYTES);
  const tag = dados.subarray(1 + IV_BYTES, 1 + IV_BYTES + TAG_BYTES);
  const cifrado = dados.subarray(1 + IV_BYTES + TAG_BYTES);
  const decifra = createDecipheriv('aes-256-gcm', chave, iv);
  decifra.setAuthTag(tag);
  return Buffer.concat([decifra.update(cifrado), decifra.final()]).toString('utf8');
}

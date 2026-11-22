import { randomBytes } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { cifrar, decifrar, lerChave } from '../src/auth/cifra.js';

const chave = randomBytes(32);

describe('Cifra AES-256-GCM', () => {
  it('cifra e decifra, incluindo acentos', () => {
    for (const texto of ['ana@exemplo.pt', 'joão.côrte@exemplo.pt', 'a'.repeat(254)]) {
      expect(decifrar(cifrar(texto, chave), chave)).toBe(texto);
    }
  });

  it('o resultado não contém o texto original', () => {
    const c = cifrar('ana@exemplo.pt', chave);
    expect(c.toString('utf8')).not.toContain('ana@exemplo.pt');
    expect(c.toString('hex')).not.toContain(Buffer.from('ana@exemplo.pt').toString('hex'));
  });

  it('cada cifra é diferente (IV aleatório), mesmo para o mesmo texto', () => {
    expect(cifrar('igual', chave).equals(cifrar('igual', chave))).toBe(false);
  });

  it('recusa uma chave errada', () => {
    const c = cifrar('segredo', chave);
    expect(() => decifrar(c, randomBytes(32))).toThrow();
  });

  it('deteta dados adulterados', () => {
    const c = Buffer.from(cifrar('segredo', chave));
    c[c.length - 1] = (c[c.length - 1] ?? 0) ^ 0xff;
    expect(() => decifrar(c, chave)).toThrow();
  });

  it('recusa dados truncados ou de uma versão desconhecida', () => {
    expect(() => decifrar(Buffer.from([1, 2, 3]), chave)).toThrow();
    const c = Buffer.from(cifrar('x', chave));
    c[0] = 99;
    expect(() => decifrar(c, chave)).toThrow();
  });

  it('só aceita chaves de 32 bytes', () => {
    expect(() => lerChave(randomBytes(16).toString('base64url'))).toThrow();
    expect(lerChave(randomBytes(32).toString('base64url'))).toHaveLength(32);
  });
});

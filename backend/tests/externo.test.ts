import { createHash } from 'node:crypto';
import { SignJWT, createLocalJWKSet, exportJWK, generateKeyPair, type JWK } from 'jose';
import request from 'supertest';
import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { criarVerificadorExterno } from '../src/auth/externo.js';
import { loadConfig } from '../src/config.js';
import { createPool } from '../src/db.js';

const config = loadConfig();
const db = createPool(config.DATABASE_URL);
const APPLE_AUD = 'pt.amparo.app';
const GOOGLE_AUDS = ['google-web.apps.googleusercontent.com', 'google-ios.apps.googleusercontent.com'];
const APPLE_ISS = 'https://appleid.apple.com';
const GOOGLE_ISS = 'https://accounts.google.com';

let chavePrivada: CryptoKey;
let outraChavePrivada: CryptoKey;
let app: ReturnType<typeof createApp>;
const subs: string[] = [];
const utilizadores: string[] = [];

beforeAll(async () => {
  const par = await generateKeyPair('RS256');
  const outro = await generateKeyPair('RS256');
  chavePrivada = par.privateKey;
  outraChavePrivada = outro.privateKey;
  const jwk: JWK = { ...(await exportJWK(par.publicKey)), kid: 'k1', alg: 'RS256', use: 'sig' };
  const chaves = createLocalJWKSet({ keys: [jwk] });
  const verificadorExterno = criarVerificadorExterno({ appleClientIds: [APPLE_AUD], googleClientIds: GOOGLE_AUDS }, { apple: chaves, google: chaves });
  app = createApp(db, config, { auth: { limitarPorIp: false, verificadorExterno } });
});

afterEach(async () => {
  if (subs.length) {
    const { rows } = await db.query('select user_id from auth_providers where provider_sub = any($1::text[])', [subs.splice(0)]);
    utilizadores.push(...rows.map((r) => r.user_id));
  }
  if (utilizadores.length) await db.query('delete from users where id = any($1::uuid[])', [utilizadores.splice(0)]);
});
afterAll(async () => {
  await db.end();
});

let n = 0;
const novoSub = () => {
  const s = `sub.${Date.now()}.${++n}`;
  subs.push(s);
  return s;
};
const NONCE = 'nonce-aleatorio-da-app-123';

interface Opcoes {
  iss?: string;
  aud?: string;
  sub?: string;
  nonce?: string | null;
  email?: string | null;
  email_verified?: boolean | string;
  exp?: string | number;
  chave?: CryptoKey;
}
async function token(provedor: 'apple' | 'google', o: Opcoes = {}) {
  const claims: Record<string, unknown> = {};
  if (o.nonce !== null) claims.nonce = o.nonce ?? NONCE;
  if (o.email !== null) claims.email = o.email ?? `ext.${Date.now()}.${n}@exemplo.pt`;
  claims.email_verified = o.email_verified ?? true;
  return new SignJWT(claims)
    .setProtectedHeader({ alg: 'RS256', kid: 'k1' })
    .setIssuer(o.iss ?? (provedor === 'apple' ? APPLE_ISS : GOOGLE_ISS))
    .setAudience(o.aud ?? (provedor === 'apple' ? APPLE_AUD : GOOGLE_AUDS[0]!))
    .setSubject(o.sub ?? novoSub())
    .setIssuedAt()
    .setExpirationTime(o.exp ?? '10m')
    .sign(o.chave ?? chavePrivada);
}
const entrar = (provedor: 'apple' | 'google', idToken: string, extra: object = {}) =>
  request(app).post(`/auth/${provedor}`).send({ idToken, nonce: NONCE, ...extra });

describe.each(['apple', 'google'] as const)('Entrar com %s', (p) => {
  it('conta nova exige o consentimento explícito e, sem ele, nada é criado', async () => {
    const sub = novoSub();
    const r = await entrar(p, await token(p, { sub }));
    expect(r.status).toBe(400);
    expect(r.body).toEqual({ erro: 'consentimento_necessario' });
    expect((await db.query('select 1 from auth_providers where provider_sub = $1', [sub])).rowCount).toBe(0);
  });

  it('cria a conta com consentimento, sem palavra-passe, e a sessão funciona', async () => {
    const sub = novoSub();
    const email = `novo.${Date.now()}.${++n}@exemplo.pt`;
    const r = await entrar(p, await token(p, { sub, email }), { nome: 'Rui', aceitaTermos: true });
    expect(r.status).toBe(201);
    expect(r.body.utilizador.nome).toBe('Rui');
    const me = await request(app).get('/auth/me').set('Authorization', `Bearer ${r.body.accessToken}`);
    expect(me.body.utilizador.nome).toBe('Rui');
    const { rows } = await db.query('select password_hash, email_hash, email_cifrado, consentimento_versao from users where id = $1', [r.body.utilizador.id]);
    expect(rows[0].password_hash).toBeNull();
    expect(rows[0].email_hash).not.toBeNull();
    expect(rows[0].email_cifrado.toString('utf8')).not.toContain('exemplo');
    expect(rows[0].consentimento_versao).toBeTruthy();
    const rf = await request(app).post('/auth/refresh').send({ refreshToken: r.body.refreshToken });
    expect(rf.status).toBe(200);
  });

  it('a entrada seguinte usa a mesma conta e não pede o consentimento nem o nome', async () => {
    const sub = novoSub();
    const primeiro = await entrar(p, await token(p, { sub }), { nome: 'Rui', aceitaTermos: true });
    const segundo = await entrar(p, await token(p, { sub, email: null }));
    expect(segundo.status).toBe(200);
    expect(segundo.body.utilizador).toEqual(primeiro.body.utilizador);
  });

  it('associa a uma conta existente só quando o email vem verificado', async () => {
    const email = `junta.${Date.now()}.${++n}@exemplo.pt`;
    const reg = await request(app).post('/auth/registo').send({ email, senha: 'uma-senha-segura-123', nome: 'Ana', aceitaTermos: true });
    utilizadores.push(reg.body.utilizador.id);

    const naoVerificado = await entrar(p, await token(p, { email, email_verified: false }), { nome: 'Intruso', aceitaTermos: true });
    expect(naoVerificado.status).toBe(201);
    expect(naoVerificado.body.utilizador.id).not.toBe(reg.body.utilizador.id); // conta separada, sem tocar na da Ana

    const verificado = await entrar(p, await token(p, { email }));
    expect(verificado.status).toBe(200);
    expect(verificado.body.utilizador.id).toBe(reg.body.utilizador.id);
    // a conta com palavra-passe continua a funcionar
    expect((await request(app).post('/auth/login').send({ email, senha: 'uma-senha-segura-123' })).status).toBe(200);
  });

  it('o email "verificado" como texto "true" (formato da Apple) também conta', async () => {
    const email = `texto.${Date.now()}.${++n}@exemplo.pt`;
    const reg = await request(app).post('/auth/registo').send({ email, senha: 'uma-senha-segura-123', nome: 'Ana', aceitaTermos: true });
    utilizadores.push(reg.body.utilizador.id);
    const r = await entrar(p, await token(p, { email, email_verified: 'true' }));
    expect(r.body.utilizador.id).toBe(reg.body.utilizador.id);
  });

  it.each([
    ['assinado com outra chave', { chave: 'outra' }],
    ['audiência errada', { aud: 'outra-app' }],
    ['emissor errado', { iss: 'https://evil.example' }],
    ['expirado', { exp: Math.floor(Date.now() / 1000) - 3600 }],
    ['sem nonce', { nonce: null }],
    ['nonce diferente', { nonce: 'outro-nonce-qualquer' }],
  ])('recusa um token %s', async (_nome, o) => {
    const sub = novoSub();
    const opcoes: Opcoes = { ...(o as Opcoes), sub };
    if ((o as { chave?: string }).chave === 'outra') opcoes.chave = outraChavePrivada;
    const r = await entrar(p, await token(p, opcoes), { nome: 'X', aceitaTermos: true });
    expect(r.status).toBe(401);
    expect(r.body).toEqual({ erro: 'provedor_invalido' });
    expect((await db.query('select 1 from auth_providers where provider_sub = $1', [sub])).rowCount).toBe(0);
  });

  it('recusa lixo, tokens sem assinatura e pedidos mal formados', async () => {
    const semAssinatura = `${Buffer.from('{"alg":"none"}').toString('base64url')}.${Buffer.from(JSON.stringify({ sub: 'x', iss: APPLE_ISS, aud: APPLE_AUD })).toString('base64url')}.`;
    for (const t of ['isto-nao-e-um-token-de-todo', semAssinatura]) {
      expect((await entrar(p, t, { aceitaTermos: true })).status).toBe(401);
    }
    expect((await request(app).post(`/auth/${p}`).send({})).status).toBe(400);
    expect((await request(app).post(`/auth/${p}`).send({ idToken: 'curto', nonce: NONCE })).status).toBe(400);
  });
});

describe('Particularidades', () => {
  it('a Apple costuma enviar o nonce em hash SHA-256: aceita-se', async () => {
    const hash = createHash('sha256').update(NONCE).digest('hex');
    const r = await entrar('apple', await token('apple', { nonce: hash }), { aceitaTermos: true });
    expect(r.status).toBe(201);
  });

  it('a Google aceita qualquer um dos clientes configurados (web, iOS)', async () => {
    for (const aud of GOOGLE_AUDS) {
      expect((await entrar('google', await token('google', { aud }), { aceitaTermos: true })).status).toBe(201);
    }
  });

  it('um token da Google não vale para a Apple e vice-versa', async () => {
    expect((await entrar('apple', await token('google'), { aceitaTermos: true })).status).toBe(401);
    expect((await entrar('google', await token('apple'), { aceitaTermos: true })).status).toBe(401);
  });

  it('o mesmo sub em fornecedores diferentes são contas diferentes', async () => {
    const sub = novoSub();
    const a = await entrar('apple', await token('apple', { sub, email: null }), { aceitaTermos: true });
    const g = await entrar('google', await token('google', { sub, email: null }), { aceitaTermos: true });
    expect(a.body.utilizador.id).not.toBe(g.body.utilizador.id);
  });

  it('um email relay da Apple (sem conta com esse email) cria conta nova, e uma conta só externa não entra por palavra-passe', async () => {
    const email = `relay.${Date.now()}@privaterelay.appleid.com`;
    const r = await entrar('apple', await token('apple', { email }), { aceitaTermos: true });
    expect(r.status).toBe(201);
    expect((await request(app).post('/auth/login').send({ email, senha: 'qualquer-coisa-123' })).status).toBe(401);
  });

  it('sem configuração do fornecedor responde 501 (não 500)', async () => {
    const semConfig = createApp(db, config, { auth: { limitarPorIp: false } });
    const r = await request(semConfig).post('/auth/apple').send({ idToken: 'x'.repeat(30), nonce: NONCE });
    expect(r.status).toBe(501);
    expect(r.body).toEqual({ erro: 'provedor_nao_configurado' });
  });

  it('a auditoria regista a entrada sem emails nem tokens', async () => {
    const r = await entrar('google', await token('google'), { aceitaTermos: true });
    const { rows } = await db.query("select acao, user_id from audit_logs where user_id = $1 and acao like 'auth.%'", [r.body.utilizador.id]);
    expect(rows.map((x) => x.acao)).toEqual(['auth.registo_google']);
  });
});

describe('Retorno da Apple no Android', () => {
  it('devolve o formulário da Apple à app por um intent, sem o guardar', async () => {
    const r = await request(app)
      .post('/auth/apple/callback')
      .type('form')
      .send({ code: 'c0d1g0', id_token: 'um.id.token', state: 'estado-1' });
    expect(r.status).toBe(303);
    expect(r.headers.location).toBe(
      'intent://callback?code=c0d1g0&id_token=um.id.token&state=estado-1#Intent;package=pt.amparo.amparo;scheme=signinwithapple;end',
    );
  });
});

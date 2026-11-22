import { createHmac } from 'node:crypto';
import { SignJWT } from 'jose';
import request from 'supertest';
import { afterAll, afterEach, describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { decifrar, lerChave } from '../src/auth/cifra.js';
import { emailParaEnvio } from '../src/auth/servico.js';
import { loadConfig } from '../src/config.js';
import { createPool } from '../src/db.js';

const config = loadConfig();
const db = createPool(config.DATABASE_URL);
const app = createApp(db, config, { auth: { limitarPorIp: false } });
const utilizadores: string[] = [];

afterEach(async () => {
  if (utilizadores.length) await db.query('delete from users where id = any($1::uuid[])', [utilizadores.splice(0)]);
});
afterAll(async () => {
  await db.end();
});

let contador = 0;
const novoEmail = () => `teste.${Date.now()}.${++contador}@exemplo.pt`;
const SENHA = 'uma-senha-segura-123';

async function criarConta(email = novoEmail(), senha = SENHA) {
  const res = await request(app).post('/auth/registo').send({ email, senha, nome: 'Ana', aceitaTermos: true });
  expect(res.status).toBe(201);
  utilizadores.push(res.body.utilizador.id);
  return { email, senha, ...res.body } as { email: string; senha: string; utilizador: { id: string }; accessToken: string; refreshToken: string };
}

describe('Registo', () => {
  it('cria a conta e devolve tokens', async () => {
    const c = await criarConta();
    expect(c.accessToken.split('.')).toHaveLength(3);
    expect(c.refreshToken.length).toBeGreaterThan(30);
  });

  it('guarda a palavra-passe em Argon2id e o email só como hash, nunca em claro', async () => {
    const c = await criarConta();
    const { rows } = await db.query('select * from users where id = $1', [c.utilizador.id]);
    const linha = JSON.stringify(rows[0]);
    expect(rows[0].password_hash).toMatch(/^\$argon2id\$/);
    expect(linha).not.toContain(c.senha);
    expect(linha.toLowerCase()).not.toContain(c.email.toLowerCase());
    const esperado = createHmac('sha256', config.EMAIL_PEPPER).update(c.email).digest('hex');
    expect(Buffer.from(rows[0].email_hash).toString('hex')).toBe(esperado);
    expect(rows[0].consentimento_versao).toBeTruthy();
  });

  it('guarda o email cifrado (para a recuperação de palavra-passe) e só o servidor o consegue ler', async () => {
    const c = await criarConta('Joao.Silva@Exemplo.pt');
    const { rows } = await db.query('select email_cifrado from users where id = $1', [c.utilizador.id]);
    const guardado = rows[0].email_cifrado as Buffer;
    expect(guardado.toString('utf8').toLowerCase()).not.toContain('joao');
    const chave = lerChave(config.EMAIL_ENC_KEY);
    expect(decifrar(guardado, chave)).toBe('joao.silva@exemplo.pt'); // normalizado
    const segredos = { jwtSecret: config.JWT_SECRET, emailPepper: config.EMAIL_PEPPER, emailChave: chave };
    expect(await emailParaEnvio(db, c.utilizador.id, segredos)).toBe('joao.silva@exemplo.pt');
  });

  it('o refresh token só é guardado como hash', async () => {
    const c = await criarConta();
    const { rows } = await db.query('select hash from refresh_tokens where user_id = $1', [c.utilizador.id]);
    expect(rows).toHaveLength(1);
    expect(Buffer.from(rows[0].hash).toString()).not.toContain(c.refreshToken);
  });

  it('recusa um email repetido, mesmo com maiúsculas e espaços', async () => {
    const c = await criarConta('Maria@Exemplo.PT');
    const res = await request(app)
      .post('/auth/registo')
      .send({ email: '  maria@exemplo.pt ', senha: SENHA, nome: 'Outra', aceitaTermos: true });
    expect(res.status).toBe(409);
    expect(res.body).toEqual({ erro: 'email_ja_existe' });
    const n = await db.query('select count(*)::int n from users where id = $1', [c.utilizador.id]);
    expect(n.rows[0].n).toBe(1);
    await db.query('delete from users where email_hash = $1', [createHmac('sha256', config.EMAIL_PEPPER).update('maria@exemplo.pt').digest()]);
  });

  it.each([
    ['palavra-passe curta', { senha: '1234567' }],
    ['email inválido', { email: 'isto-nao-e-email' }],
    ['sem aceitar os termos', { aceitaTermos: false }],
    ['sem nome', { nome: '   ' }],
    ['palavra-passe enorme', { senha: 'a'.repeat(129) }],
  ])('rejeita %s', async (_nome, alteracao) => {
    const corpo = { email: novoEmail(), senha: SENHA, nome: 'Ana', aceitaTermos: true, ...alteracao };
    const res = await request(app).post('/auth/registo').send(corpo);
    expect(res.status).toBe(400);
    expect(res.body.erro).toBe('pedido_invalido');
    // a resposta nunca repete valores enviados
    expect(JSON.stringify(res.body)).not.toContain(SENHA);
  });

  it('regista a ação na auditoria sem dados pessoais', async () => {
    const c = await criarConta();
    const { rows } = await db.query('select * from audit_logs where user_id = $1 and acao = $2', [c.utilizador.id, 'auth.registo']);
    expect(rows).toHaveLength(1);
    expect(JSON.stringify(rows[0]).toLowerCase()).not.toContain(c.email.toLowerCase());
  });
});

describe('Login', () => {
  it('entra com as credenciais certas', async () => {
    const c = await criarConta();
    const res = await request(app).post('/auth/login').send({ email: c.email.toUpperCase(), senha: c.senha });
    expect(res.status).toBe(200);
    expect(res.body.utilizador.id).toBe(c.utilizador.id);
    expect(res.body.accessToken).toBeTruthy();
    expect(res.body.expiraEmSegundos).toBe(900);
  });

  it('palavra-passe errada e email desconhecido dão exatamente a mesma resposta', async () => {
    const c = await criarConta();
    const errada = await request(app).post('/auth/login').send({ email: c.email, senha: 'errada-errada-1' });
    const desconhecido = await request(app).post('/auth/login').send({ email: novoEmail(), senha: 'errada-errada-1' });
    expect(errada.status).toBe(401);
    expect(desconhecido.status).toBe(401);
    expect(errada.body).toEqual({ erro: 'credenciais_invalidas' });
    expect(desconhecido.body).toEqual(errada.body);
  });

  it('bloqueia depois de 5 falhas, mesmo com a palavra-passe certa, e desbloqueia ao fim do prazo', async () => {
    const c = await criarConta();
    for (let i = 0; i < 5; i++) {
      const r = await request(app).post('/auth/login').send({ email: c.email, senha: 'errada-errada-1' });
      expect(r.status).toBe(401);
    }
    const bloqueado = await request(app).post('/auth/login').send({ email: c.email, senha: c.senha });
    expect(bloqueado.status).toBe(429);
    expect(bloqueado.body).toEqual({ erro: 'demasiadas_tentativas' });

    // passou o prazo de bloqueio
    await db.query("update users set bloqueado_ate = now() - interval '1 second' where id = $1", [c.utilizador.id]);
    const ok = await request(app).post('/auth/login').send({ email: c.email, senha: c.senha });
    expect(ok.status).toBe(200);
    const { rows } = await db.query('select falhas_login, bloqueado_ate from users where id = $1', [c.utilizador.id]);
    expect(rows[0].falhas_login).toBe(0);
    expect(rows[0].bloqueado_ate).toBeNull();
  });

  it('uma conta sem palavra-passe (entrada só com Apple/Google) não entra por aqui', async () => {
    const c = await criarConta();
    await db.query('update users set password_hash = null where id = $1', [c.utilizador.id]);
    const res = await request(app).post('/auth/login').send({ email: c.email, senha: c.senha });
    expect(res.status).toBe(401);
  });
});

describe('Token de acesso', () => {
  it('GET /auth/me funciona com um token válido', async () => {
    const c = await criarConta();
    const res = await request(app).get('/auth/me').set('Authorization', `Bearer ${c.accessToken}`);
    expect(res.status).toBe(200);
    expect(res.body.utilizador).toMatchObject({ id: c.utilizador.id, nome: 'Ana' });
  });

  it.each([
    ['sem cabeçalho', undefined],
    ['esquema errado', 'Basic abc'],
    ['lixo', 'Bearer isto-nao-e-um-jwt'],
  ])('recusa %s', async (_nome, cabecalho) => {
    const req = request(app).get('/auth/me');
    if (cabecalho) req.set('Authorization', cabecalho);
    const res = await req;
    expect(res.status).toBe(401);
    expect(res.body).toEqual({ erro: 'nao_autenticado' });
  });

  it('recusa um token assinado com outro segredo', async () => {
    const c = await criarConta();
    const falso = await new SignJWT({ typ: 'access' })
      .setProtectedHeader({ alg: 'HS256' }).setSubject(c.utilizador.id).setIssuer('amparo').setAudience('amparo-app')
      .setIssuedAt().setExpirationTime('15m').sign(new TextEncoder().encode('x'.repeat(40)));
    const res = await request(app).get('/auth/me').set('Authorization', `Bearer ${falso}`);
    expect(res.status).toBe(401);
  });

  it('recusa um token expirado', async () => {
    const c = await criarConta();
    const expirado = await new SignJWT({ typ: 'access' })
      .setProtectedHeader({ alg: 'HS256' }).setSubject(c.utilizador.id).setIssuer('amparo').setAudience('amparo-app')
      .setIssuedAt(Math.floor(Date.now() / 1000) - 3600).setExpirationTime(Math.floor(Date.now() / 1000) - 60)
      .sign(new TextEncoder().encode(config.JWT_SECRET));
    const res = await request(app).get('/auth/me').set('Authorization', `Bearer ${expirado}`);
    expect(res.status).toBe(401);
  });

  it('recusa um token sem assinatura (alg: none)', async () => {
    const c = await criarConta();
    const b64 = (o: object) => Buffer.from(JSON.stringify(o)).toString('base64url');
    const semAssinatura = `${b64({ alg: 'none', typ: 'JWT' })}.${b64({ sub: c.utilizador.id, typ: 'access', iss: 'amparo', aud: 'amparo-app', exp: Math.floor(Date.now() / 1000) + 600 })}.`;
    const res = await request(app).get('/auth/me').set('Authorization', `Bearer ${semAssinatura}`);
    expect(res.status).toBe(401);
  });

  it('um refresh token não serve como token de acesso', async () => {
    const c = await criarConta();
    const res = await request(app).get('/auth/me').set('Authorization', `Bearer ${c.refreshToken}`);
    expect(res.status).toBe(401);
  });
});

describe('Refresh tokens', () => {
  it('troca o token por um par novo e o antigo deixa de servir (rotação)', async () => {
    const c = await criarConta();
    const novo = await request(app).post('/auth/refresh').send({ refreshToken: c.refreshToken });
    expect(novo.status).toBe(200);
    expect(novo.body.refreshToken).not.toBe(c.refreshToken);
    const me = await request(app).get('/auth/me').set('Authorization', `Bearer ${novo.body.accessToken}`);
    expect(me.status).toBe(200);
  });

  it('se um token já usado aparecer outra vez, revoga a família inteira', async () => {
    const c = await criarConta();
    const novo = await request(app).post('/auth/refresh').send({ refreshToken: c.refreshToken });
    expect(novo.status).toBe(200);
    // alguém tenta usar o token antigo (roubado)
    const reuso = await request(app).post('/auth/refresh').send({ refreshToken: c.refreshToken });
    expect(reuso.status).toBe(401);
    // o token novo, que era legítimo, também foi revogado por precaução
    const legitimo = await request(app).post('/auth/refresh').send({ refreshToken: novo.body.refreshToken });
    expect(legitimo.status).toBe(401);
    const { rows } = await db.query("select count(*)::int n from audit_logs where user_id = $1 and acao = 'auth.refresh_reutilizado'", [c.utilizador.id]);
    expect(rows[0].n).toBeGreaterThanOrEqual(1); // cada reutilização fica registada
  });

  it('recusa um token desconhecido e um expirado', async () => {
    const c = await criarConta();
    const desconhecido = await request(app).post('/auth/refresh').send({ refreshToken: 'a'.repeat(43) });
    expect(desconhecido.status).toBe(401);
    expect(desconhecido.body).toEqual({ erro: 'refresh_invalido' });
    await db.query("update refresh_tokens set expira_em = now() - interval '1 minute' where user_id = $1", [c.utilizador.id]);
    const expirado = await request(app).post('/auth/refresh').send({ refreshToken: c.refreshToken });
    expect(expirado.status).toBe(401);
  });

  it('logout revoga a sessão; repetir o logout não dá erro', async () => {
    const c = await criarConta();
    const out = await request(app).post('/auth/logout').send({ refreshToken: c.refreshToken });
    expect(out.status).toBe(204);
    const depois = await request(app).post('/auth/refresh').send({ refreshToken: c.refreshToken });
    expect(depois.status).toBe(401);
    const outra = await request(app).post('/auth/logout').send({ refreshToken: c.refreshToken });
    expect(outra.status).toBe(204);
  });

  it('o logout de uma sessão não afeta outra sessão do mesmo utilizador', async () => {
    const c = await criarConta();
    const outra = await request(app).post('/auth/login').send({ email: c.email, senha: c.senha });
    await request(app).post('/auth/logout').send({ refreshToken: c.refreshToken });
    const ainda = await request(app).post('/auth/refresh').send({ refreshToken: outra.body.refreshToken });
    expect(ainda.status).toBe(200);
  });
});

describe('Limite de pedidos por IP', () => {
  it('devolve 429 depois de exceder o limite', async () => {
    const limitada = createApp(db, config, { auth: { limitarPorIp: { janelaMs: 60_000, maximo: 3 } } });
    const estados: number[] = [];
    for (let i = 0; i < 5; i++) {
      const r = await request(limitada).post('/auth/login').send({ email: novoEmail(), senha: 'qualquer-coisa-1' });
      estados.push(r.status);
    }
    expect(estados).toEqual([401, 401, 401, 429, 429]);
  });
});

describe('Pedidos malformados', () => {
  it('JSON inválido devolve 400 sem expor detalhes', async () => {
    const res = await request(app).post('/auth/login').set('Content-Type', 'application/json').send('{"email": ');
    expect(res.status).toBe(400);
    expect(res.body.erro).toBe('pedido_invalido');
  });
});

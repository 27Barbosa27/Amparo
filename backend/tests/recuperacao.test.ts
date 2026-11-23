import request from 'supertest';
import { afterAll, afterEach, describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { createPool } from '../src/db.js';
import type { Email, EnviadorEmail } from '../src/email/enviador.js';

const config = loadConfig();
const db = createPool(config.DATABASE_URL);
const enviados: Email[] = [];
let falha = false;
const enviadorEmail: EnviadorEmail = {
  async enviar(e) {
    if (falha) throw new Error('smtp em baixo');
    enviados.push(e);
  },
};
const app = createApp(db, config, { auth: { limitarPorIp: false, enviadorEmail }, registar: false });
const utilizadores: string[] = [];

afterEach(async () => {
  enviados.length = 0;
  falha = false;
  if (utilizadores.length) await db.query('delete from users where id = any($1::uuid[])', [utilizadores.splice(0)]);
});
afterAll(async () => {
  await db.end();
});

let n = 0;
async function conta() {
  const email = `rec.${Date.now()}.${++n}@exemplo.pt`;
  const r = await request(app).post('/auth/registo').send({ email, senha: 'palavra-passe-antiga-1', nome: 'Ana', aceitaTermos: true });
  utilizadores.push(r.body.utilizador.id);
  return { id: r.body.utilizador.id as string, email, refresh: r.body.refreshToken as string, token: r.body.accessToken as string };
}
const esperarEmail = async () => {
  for (let i = 0; i < 100 && enviados.length === 0; i++) await new Promise((r) => setTimeout(r, 10));
  return enviados[0];
};
const tokenDoEmail = (e: Email) => /token=([\w-]+)/.exec(e.texto)![1]!;
async function pedir(email: string) {
  const r = await request(app).post('/auth/recuperar').send({ email });
  expect(r.status).toBe(202);
  return r;
}

describe('Pedir a recuperação', () => {
  it('envia o email ao endereço da conta, com um link de uso único, e guarda só o hash do token', async () => {
    const c = await conta();
    await pedir(c.email);
    const e = (await esperarEmail())!;
    expect(e.para).toBe(c.email);
    expect(e.texto).toContain(`${config.APP_LINK_BASE}?token=`);
    const token = tokenDoEmail(e);
    const { rows } = await db.query('select token_hash, expira_em from password_resets where user_id = $1', [c.id]);
    expect(rows).toHaveLength(1);
    expect(rows[0].token_hash.toString('utf8')).not.toContain(token);
    const min = (rows[0].expira_em.getTime() - Date.now()) / 60_000;
    expect(min).toBeGreaterThan(29);
    expect(min).toBeLessThanOrEqual(30);
  });

  it('a resposta é igual para conta existente, inexistente e email inválido, e só a existente recebe email', async () => {
    const c = await conta();
    const a = await pedir(c.email);
    const b = await pedir('nao.existe@exemplo.pt');
    const m = await request(app).post('/auth/recuperar').send({ email: 'isto-nao-e-email' });
    expect(m.status).toBe(202);
    expect(b.body).toEqual(a.body);
    expect(m.body).toEqual(a.body);
    await esperarEmail();
    await new Promise((r) => setTimeout(r, 50));
    expect(enviados).toHaveLength(1);
  });

  it('não envia a contas só com Apple/Google (não têm palavra-passe)', async () => {
    const email = `ext.${Date.now()}@exemplo.pt`;
    const { hashEmail } = await import('../src/auth/email.js');
    const { cifrar } = await import('../src/auth/cifra.js');
    const { lerChave } = await import('../src/auth/cifra.js');
    const r = await db.query(
      "insert into users (email_hash, email_cifrado, consentimento_versao, consentimento_em) values ($1, $2, 'x', now()) returning id",
      [hashEmail(email, config.EMAIL_PEPPER), cifrar(email, lerChave(config.EMAIL_ENC_KEY))],
    );
    utilizadores.push(r.rows[0].id);
    await pedir(email);
    await new Promise((x) => setTimeout(x, 50));
    expect(enviados).toEqual([]);
  });

  it('um pedido novo invalida o link anterior', async () => {
    const c = await conta();
    await pedir(c.email);
    const primeiro = tokenDoEmail((await esperarEmail())!);
    enviados.length = 0;
    await pedir(c.email);
    const segundo = tokenDoEmail((await esperarEmail())!);
    expect(segundo).not.toBe(primeiro);
    expect((await request(app).post('/auth/repor').send({ token: primeiro, senha: 'nova-palavra-passe-2' })).status).toBe(400);
    expect((await request(app).post('/auth/repor').send({ token: segundo, senha: 'nova-palavra-passe-2' })).status).toBe(204);
  });

  it('limita os pedidos por conta (3 por hora) sem o revelar', async () => {
    const c = await conta();
    for (let i = 0; i < 5; i++) expect((await pedir(c.email)).status).toBe(202);
    await new Promise((r) => setTimeout(r, 100));
    expect(enviados).toHaveLength(3);
  });

  it('uma falha do servidor de email não chega ao cliente', async () => {
    const c = await conta();
    falha = true;
    const silencio = console.error;
    console.error = () => undefined;
    try {
      expect((await pedir(c.email)).status).toBe(202);
      await new Promise((r) => setTimeout(r, 50));
    } finally {
      console.error = silencio;
    }
  });

  it('o limite de pedidos por IP também se aplica', async () => {
    const limitada = createApp(db, config, { auth: { limitarPorIp: { janelaMs: 60_000, maximo: 2 }, enviadorEmail }, registar: false });
    const estados: number[] = [];
    for (let i = 0; i < 4; i++) estados.push((await request(limitada).post('/auth/recuperar').send({ email: 'x@exemplo.pt' })).status);
    expect(estados).toEqual([202, 202, 429, 429]);
  });
});

describe('Repor a palavra-passe', () => {
  async function comToken() {
    const c = await conta();
    await pedir(c.email);
    return { c, token: tokenDoEmail((await esperarEmail())!) };
  }

  it('muda a palavra-passe: a nova entra, a antiga deixa de entrar', async () => {
    const { c, token } = await comToken();
    expect((await request(app).post('/auth/repor').send({ token, senha: 'nova-palavra-passe-2' })).status).toBe(204);
    expect((await request(app).post('/auth/login').send({ email: c.email, senha: 'nova-palavra-passe-2' })).status).toBe(200);
    expect((await request(app).post('/auth/login').send({ email: c.email, senha: 'palavra-passe-antiga-1' })).status).toBe(401);
  });

  it('é de uso único', async () => {
    const { token } = await comToken();
    expect((await request(app).post('/auth/repor').send({ token, senha: 'nova-palavra-passe-2' })).status).toBe(204);
    const r = await request(app).post('/auth/repor').send({ token, senha: 'outra-palavra-passe-3' });
    expect(r.status).toBe(400);
    expect(r.body).toEqual({ erro: 'token_invalido' });
  });

  it('expira ao fim de 30 minutos e dá a mesma resposta que um token inventado', async () => {
    const { c, token } = await comToken();
    await db.query("update password_resets set expira_em = now() - interval '1 second' where user_id = $1", [c.id]);
    const expirado = await request(app).post('/auth/repor').send({ token, senha: 'nova-palavra-passe-2' });
    const inventado = await request(app).post('/auth/repor').send({ token: 'x'.repeat(43), senha: 'nova-palavra-passe-2' });
    expect(expirado.status).toBe(400);
    expect(expirado.body).toEqual(inventado.body);
  });

  it('revoga TODAS as sessões e limpa o bloqueio por falhas', async () => {
    const { c, token } = await comToken();
    for (let i = 0; i < 5; i++) await request(app).post('/auth/login').send({ email: c.email, senha: 'errada-errada-1' });
    expect((await request(app).post('/auth/login').send({ email: c.email, senha: 'palavra-passe-antiga-1' })).status).toBe(429);
    await request(app).post('/auth/repor').send({ token, senha: 'nova-palavra-passe-2' });
    expect((await request(app).post('/auth/refresh').send({ refreshToken: c.refresh })).status).toBe(401);
    expect((await request(app).post('/auth/login').send({ email: c.email, senha: 'nova-palavra-passe-2' })).status).toBe(200);
  });

  it('valida a nova palavra-passe e não repõe nada se for inválida', async () => {
    const { c, token } = await comToken();
    expect((await request(app).post('/auth/repor').send({ token, senha: 'curta' })).status).toBe(400);
    expect((await request(app).post('/auth/repor').send({ token })).status).toBe(400);
    expect((await request(app).post('/auth/login').send({ email: c.email, senha: 'palavra-passe-antiga-1' })).status).toBe(200);
    expect((await request(app).post('/auth/repor').send({ token, senha: 'nova-palavra-passe-2' })).status).toBe(204); // o token continua bom
  });

  it('a auditoria regista o pedido e a reposição sem emails nem tokens', async () => {
    const { c, token } = await comToken();
    await request(app).post('/auth/repor').send({ token, senha: 'nova-palavra-passe-2' });
    const { rows } = await db.query("select acao from audit_logs where user_id = $1 and acao like 'auth.%' and acao in ('auth.recuperacao_pedida','auth.senha_reposta') order by id", [c.id]);
    expect(rows.map((r) => r.acao)).toEqual(['auth.recuperacao_pedida', 'auth.senha_reposta']);
    const todos = JSON.stringify((await db.query('select * from audit_logs where user_id = $1', [c.id])).rows);
    expect(todos).not.toContain(token);
    expect(todos).not.toContain(c.email);
  });
});

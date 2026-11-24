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
const tokenDoEmail = (e: Email) => /(\d{3}) (\d{3})/.exec(e.texto)!.slice(1, 3).join('');
const repor = (email: string, codigo: string, senha?: string) => request(app).post('/auth/repor').send({ email, codigo, ...(senha === undefined ? {} : { senha }) });
async function pedir(email: string) {
  const r = await request(app).post('/auth/recuperar').send({ email });
  expect(r.status).toBe(202);
  return r;
}

describe('Pedir a recuperação', () => {
  it('envia o email ao endereço da conta, com um código de 6 dígitos, e guarda só o hash', async () => {
    const c = await conta();
    await pedir(c.email);
    const e = (await esperarEmail())!;
    expect(e.para).toBe(c.email);
    expect(e.texto).toMatch(/\d{3} \d{3}/);
    expect(e.texto).not.toContain('http');
    const token = tokenDoEmail(e);
    const { rows } = await db.query('select token_hash, expira_em from password_resets where user_id = $1', [c.id]);
    expect(rows).toHaveLength(1);
    expect(rows[0].token_hash.toString('utf8')).not.toContain(token);
    expect(token).toMatch(/^\d{6}$/);
    const min = (rows[0].expira_em.getTime() - Date.now()) / 60_000;
    expect(min).toBeGreaterThan(4);
    expect(min).toBeLessThanOrEqual(5);
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
    expect((await repor(c.email, primeiro, 'nova-palavra-passe-2')).status).toBe(400);
    expect((await repor(c.email, segundo, 'nova-palavra-passe-2')).status).toBe(204);
  });

  it('limita os pedidos por conta (15 por hora) sem o revelar', async () => {
    const c = await conta();
    for (let i = 0; i < 17; i++) expect((await pedir(c.email)).status).toBe(202);
    await new Promise((r) => setTimeout(r, 200));
    expect(enviados).toHaveLength(15);
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
    expect((await repor(c.email, token, 'nova-palavra-passe-2')).status).toBe(204);
    expect((await request(app).post('/auth/login').send({ email: c.email, senha: 'nova-palavra-passe-2' })).status).toBe(200);
    expect((await request(app).post('/auth/login').send({ email: c.email, senha: 'palavra-passe-antiga-1' })).status).toBe(401);
  });

  it('é de uso único', async () => {
    const { c, token } = await comToken();
    expect((await repor(c.email, token, 'nova-palavra-passe-2')).status).toBe(204);
    const r = await repor(c.email, token, 'outra-palavra-passe-3');
    expect(r.status).toBe(400);
    expect(r.body).toEqual({ erro: 'token_invalido' });
  });

  it('expira ao fim de 5 minutos e dá a mesma resposta que um código inventado', async () => {
    const { c, token } = await comToken();
    await db.query("update password_resets set expira_em = now() - interval '1 second' where user_id = $1", [c.id]);
    const expirado = await repor(c.email, token, 'nova-palavra-passe-2');
    const inventado = await repor(c.email, '000000', 'nova-palavra-passe-2');
    expect(expirado.status).toBe(400);
    expect(expirado.body).toEqual(inventado.body);
  });

  it('revoga TODAS as sessões e limpa o bloqueio por falhas', async () => {
    const { c, token } = await comToken();
    for (let i = 0; i < 5; i++) await request(app).post('/auth/login').send({ email: c.email, senha: 'errada-errada-1' });
    expect((await request(app).post('/auth/login').send({ email: c.email, senha: 'palavra-passe-antiga-1' })).status).toBe(429);
    await repor(c.email, token, 'nova-palavra-passe-2');
    expect((await request(app).post('/auth/refresh').send({ refreshToken: c.refresh })).status).toBe(401);
    expect((await request(app).post('/auth/login').send({ email: c.email, senha: 'nova-palavra-passe-2' })).status).toBe(200);
  });

  it('valida a nova palavra-passe e não repõe nada se for inválida', async () => {
    const { c, token } = await comToken();
    expect((await repor(c.email, token, 'curta')).status).toBe(400);
    expect((await repor(c.email, token)).status).toBe(400);
    expect((await request(app).post('/auth/login').send({ email: c.email, senha: 'palavra-passe-antiga-1' })).status).toBe(200);
    expect((await repor(c.email, token, 'nova-palavra-passe-2')).status).toBe(204); // o token continua bom
  });

  it('5 códigos errados esgotam o código: nem o certo volta a valer', async () => {
    const { c, token } = await comToken();
    const errado = token === '000000' ? '111111' : '000000';
    for (let i = 0; i < 5; i++) expect((await repor(c.email, errado, 'nova-palavra-passe-2')).status).toBe(400);
    const r = await repor(c.email, token, 'nova-palavra-passe-2');
    expect(r.status).toBe(400);
    expect(r.body).toEqual({ erro: 'token_invalido' });
    expect((await request(app).post('/auth/login').send({ email: c.email, senha: 'palavra-passe-antiga-1' })).status).toBe(200);
  });

  it('um código errado não gasta o certo (até ao limite)', async () => {
    const { c, token } = await comToken();
    const errado = token === '000000' ? '111111' : '000000';
    await repor(c.email, errado, 'nova-palavra-passe-2');
    expect((await repor(c.email, token, 'nova-palavra-passe-2')).status).toBe(204);
  });

  it('o código de uma conta não serve noutra, e email desconhecido responde igual', async () => {
    const a = await comToken();
    const b = await conta();
    const alheio = await repor(b.email, a.token, 'nova-palavra-passe-2');
    const desconhecido = await repor('nao.existe@exemplo.pt', a.token, 'nova-palavra-passe-2');
    expect(alheio.status).toBe(400);
    expect(desconhecido.status).toBe(400);
    expect(desconhecido.body).toEqual(alheio.body);
  });

  it('o código tem de ter 6 dígitos', async () => {
    const { c } = await comToken();
    expect((await repor(c.email, '12345', 'nova-palavra-passe-2')).status).toBe(400);
    expect((await repor(c.email, 'abcdef', 'nova-palavra-passe-2')).status).toBe(400);
  });

  it('verificar confirma o código sem o gastar, e conta as tentativas erradas', async () => {
    const { c, token } = await comToken();
    const verificar = (codigo: string) => request(app).post('/auth/recuperar/verificar').send({ email: c.email, codigo });
    const errado = token === '000000' ? '111111' : '000000';
    expect((await verificar(errado)).status).toBe(400);
    expect((await verificar(token)).status).toBe(204);
    expect((await verificar(token)).status).toBe(204); // não se gasta
    expect((await repor(c.email, token, 'nova-palavra-passe-2')).status).toBe(204); // e ainda serve para repor
    expect((await verificar(token)).status).toBe(400); // depois de usado, já não
  });

  it('verificar também esgota o código ao fim de 5 erros', async () => {
    const { c, token } = await comToken();
    const errado = token === '000000' ? '111111' : '000000';
    for (let i = 0; i < 5; i++) await request(app).post('/auth/recuperar/verificar').send({ email: c.email, codigo: errado });
    expect((await request(app).post('/auth/recuperar/verificar').send({ email: c.email, codigo: token })).status).toBe(400);
  });

  it('a auditoria regista o pedido e a reposição sem emails nem tokens', async () => {
    const { c, token } = await comToken();
    await repor(c.email, token, 'nova-palavra-passe-2');
    const { rows } = await db.query("select acao from audit_logs where user_id = $1 and acao like 'auth.%' and acao in ('auth.recuperacao_pedida','auth.senha_reposta') order by id", [c.id]);
    expect(rows.map((r) => r.acao)).toEqual(['auth.recuperacao_pedida', 'auth.senha_reposta']);
    const todos = JSON.stringify((await db.query('select * from audit_logs where user_id = $1', [c.id])).rows);
    expect(todos).not.toContain(token);
    expect(todos).not.toContain(c.email);
  });
});

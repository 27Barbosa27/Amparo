import request from 'supertest';
import { afterAll, afterEach, describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { createPool } from '../src/db.js';
import type { Email, EnviadorEmail } from '../src/email/enviador.js';

const config = loadConfig();
const db = createPool(config.DATABASE_URL);
const enviados: Email[] = [];
const enviadorEmail: EnviadorEmail = {
  async enviar(e) {
    enviados.push(e);
  },
};
const app = createApp(db, config, { auth: { limitarPorIp: false, enviadorEmail, exigirVerificacaoEmail: true }, registar: false });
const emails: string[] = [];

afterEach(async () => {
  enviados.length = 0;
  if (emails.length) await db.query('delete from users where email_hash = any($1::bytea[])', [await hashes(emails.splice(0))]);
});
afterAll(async () => {
  await db.end();
});

async function hashes(lista: string[]) {
  const { hashEmail } = await import('../src/auth/email.js');
  return lista.map((e) => hashEmail(e, config.EMAIL_PEPPER));
}

let n = 0;
const novoEmail = () => {
  const e = `ver.${Date.now()}.${++n}@exemplo.pt`;
  emails.push(e);
  return e;
};
const registo = (email: string, senha = 'palavra-passe-1234', nome = 'Ana') =>
  request(app).post('/auth/registo').send({ email, senha, nome, aceitaTermos: true });
const esperarEmail = async (quantos = 1) => {
  for (let i = 0; i < 100 && enviados.length < quantos; i++) await new Promise((r) => setTimeout(r, 10));
  return enviados[quantos - 1];
};
const codigoDoEmail = (e: Email) => /\b(\d{3}) (\d{3})\b/.exec(e.texto)!.slice(1, 3).join('');
const verificar = (email: string, codigo: string) => request(app).post('/auth/verificar-email').send({ email, codigo });

describe('Registo com verificação do email', () => {
  it('não abre sessão: devolve "verificacaoNecessaria" e envia um código de 6 dígitos ao email', async () => {
    const email = novoEmail();
    const r = await registo(email);
    expect(r.status).toBe(201);
    expect(r.body.verificacaoNecessaria).toBe(true);
    expect(r.body.accessToken).toBeUndefined();
    expect(r.body.refreshToken).toBeUndefined();
    const e = (await esperarEmail())!;
    expect(e.para).toBe(email);
    expect(codigoDoEmail(e)).toMatch(/^\d{6}$/);
    expect(e.texto).not.toContain('http');
  });

  it('guarda só o hash do código e o email fica por verificar', async () => {
    const email = novoEmail();
    await registo(email);
    const codigo = codigoDoEmail((await esperarEmail())!);
    const { rows } = await db.query(
      "select v.codigo_hash, u.email_verificado_em, v.expira_em from email_verificacoes v join users u on u.id = v.user_id where u.email_hash = $1",
      [(await hashes([email]))[0]],
    );
    expect(rows).toHaveLength(1);
    expect(rows[0].email_verificado_em).toBeNull();
    expect(rows[0].codigo_hash.toString('utf8')).not.toContain(codigo);
    const min = (rows[0].expira_em.getTime() - Date.now()) / 60_000;
    expect(min).toBeGreaterThan(9);
    expect(min).toBeLessThanOrEqual(10);
  });

  it('o código certo verifica o email e abre a sessão', async () => {
    const email = novoEmail();
    await registo(email);
    const codigo = codigoDoEmail((await esperarEmail())!);
    const r = await verificar(email, codigo);
    expect(r.status).toBe(200);
    expect(r.body.accessToken).toBeTruthy();
    expect(r.body.refreshToken).toBeTruthy();
    expect(r.body.utilizador.nome).toBe('Ana');
    const me = await request(app).get('/auth/me').set('authorization', `Bearer ${r.body.accessToken}`);
    expect(me.status).toBe(200);
  });

  it('o código é de uso único', async () => {
    const email = novoEmail();
    await registo(email);
    const codigo = codigoDoEmail((await esperarEmail())!);
    expect((await verificar(email, codigo)).status).toBe(200);
    const r = await verificar(email, codigo);
    expect(r.status).toBe(400);
    expect(r.body).toEqual({ erro: 'codigo_invalido' });
  });

  it('5 códigos errados esgotam o código: nem o certo volta a valer', async () => {
    const email = novoEmail();
    await registo(email);
    const codigo = codigoDoEmail((await esperarEmail())!);
    const errado = codigo === '000000' ? '111111' : '000000';
    for (let i = 0; i < 5; i++) expect((await verificar(email, errado)).status).toBe(400);
    expect((await verificar(email, codigo)).status).toBe(400);
  });

  it('um código errado não gasta o certo (até ao limite)', async () => {
    const email = novoEmail();
    await registo(email);
    const codigo = codigoDoEmail((await esperarEmail())!);
    await verificar(email, codigo === '000000' ? '111111' : '000000');
    expect((await verificar(email, codigo)).status).toBe(200);
  });

  it('o código expira ao fim de 10 minutos, com a mesma resposta que um código inventado', async () => {
    const email = novoEmail();
    await registo(email);
    const codigo = codigoDoEmail((await esperarEmail())!);
    await db.query("update email_verificacoes set expira_em = now() - interval '1 second'");
    const expirado = await verificar(email, codigo);
    const outro = await verificar('nao.existe@exemplo.pt', '123456');
    expect(expirado.status).toBe(400);
    expect(expirado.body).toEqual(outro.body);
  });

  it('o código de uma conta não serve noutra', async () => {
    const a = novoEmail();
    const b = novoEmail();
    await registo(a);
    const codigoA = codigoDoEmail((await esperarEmail(1))!);
    await registo(b);
    await esperarEmail(2);
    expect((await verificar(b, codigoA)).status).toBe(400);
  });

  it('o código tem de ter 6 dígitos', async () => {
    expect((await verificar(novoEmail(), '12345')).status).toBe(400);
    expect((await verificar(novoEmail(), 'abcdef')).status).toBe(400);
  });
});

describe('Entrar sem ter verificado o email', () => {
  it('a palavra-passe certa não chega: pede a verificação e envia um código novo', async () => {
    const email = novoEmail();
    await registo(email, 'palavra-passe-1234');
    await esperarEmail(1);
    const r = await request(app).post('/auth/login').send({ email, senha: 'palavra-passe-1234' });
    expect(r.status).toBe(403);
    expect(r.body).toEqual({ erro: 'email_nao_verificado' });
    const e2 = (await esperarEmail(2))!;
    // o código novo serve e dá sessão
    expect((await verificar(email, codigoDoEmail(e2))).status).toBe(200);
    expect((await request(app).post('/auth/login').send({ email, senha: 'palavra-passe-1234' })).status).toBe(200);
  });

  it('uma palavra-passe errada continua a ser "credenciais inválidas" (não revela a conta)', async () => {
    const email = novoEmail();
    await registo(email);
    const r = await request(app).post('/auth/login').send({ email, senha: 'errada-errada-1' });
    expect(r.status).toBe(401);
    expect(r.body).toEqual({ erro: 'credenciais_invalidas' });
  });
});

describe('Reenviar o código', () => {
  it('manda um código novo e o anterior deixa de valer', async () => {
    const email = novoEmail();
    await registo(email);
    const primeiro = codigoDoEmail((await esperarEmail(1))!);
    expect((await request(app).post('/auth/reenviar-verificacao').send({ email })).status).toBe(202);
    const segundo = codigoDoEmail((await esperarEmail(2))!);
    expect(segundo).not.toBe(primeiro);
    expect((await verificar(email, primeiro)).status).toBe(400);
    expect((await verificar(email, segundo)).status).toBe(200);
  });

  it('a resposta é igual para conta inexistente, já verificada e email inválido, e só a por verificar recebe email', async () => {
    const email = novoEmail();
    await registo(email);
    await esperarEmail(1);
    const a = await request(app).post('/auth/reenviar-verificacao').send({ email });
    const b = await request(app).post('/auth/reenviar-verificacao').send({ email: 'nao.existe@exemplo.pt' });
    const m = await request(app).post('/auth/reenviar-verificacao').send({ email: 'isto-nao-e-email' });
    expect(b.body).toEqual(a.body);
    expect(m.body).toEqual(a.body);
    await esperarEmail(2);
    await new Promise((r) => setTimeout(r, 50));
    expect(enviados).toHaveLength(2); // o do registo e o do reenvio; mais nenhum
  });

  it('limita os códigos por conta (10 por hora) sem o revelar', async () => {
    const email = novoEmail();
    await registo(email);
    for (let i = 0; i < 12; i++) expect((await request(app).post('/auth/reenviar-verificacao').send({ email })).status).toBe(202);
    await new Promise((r) => setTimeout(r, 200));
    expect(enviados).toHaveLength(10);
  });
});

describe('Email de quem nunca o verificou', () => {
  it('quem se regista depois com o mesmo email fica com a conta (o primeiro nunca provou que era dono)', async () => {
    const email = novoEmail();
    await registo(email, 'palavra-passe-do-intruso', 'Intruso');
    await esperarEmail(1);
    const r = await registo(email, 'palavra-passe-do-dono-1', 'Dono');
    expect(r.status).toBe(201);
    const codigo = codigoDoEmail((await esperarEmail(2))!);
    expect((await verificar(email, codigo)).status).toBe(200);
    // a palavra-passe do intruso já não entra; a do dono sim
    expect((await request(app).post('/auth/login').send({ email, senha: 'palavra-passe-do-intruso' })).status).toBe(401);
    expect((await request(app).post('/auth/login').send({ email, senha: 'palavra-passe-do-dono-1' })).status).toBe(200);
  });

  it('um email já verificado continua a recusar um registo repetido', async () => {
    const email = novoEmail();
    await registo(email);
    await verificar(email, codigoDoEmail((await esperarEmail())!));
    const r = await registo(email, 'outra-palavra-passe-9');
    expect(r.status).toBe(409);
    expect(r.body).toEqual({ erro: 'email_ja_existe' });
  });
});

describe('Auditoria', () => {
  it('regista o envio e a verificação sem emails nem códigos', async () => {
    const email = novoEmail();
    await registo(email);
    const codigo = codigoDoEmail((await esperarEmail())!);
    await verificar(email, codigo);
    const u = await db.query('select id from users where email_hash = $1', [(await hashes([email]))[0]]);
    const id = u.rows[0].id;
    const { rows } = await db.query("select acao from audit_logs where user_id = $1 and acao in ('auth.verificacao_enviada','auth.email_verificado') order by id", [id]);
    expect(rows.map((r) => r.acao)).toEqual(['auth.verificacao_enviada', 'auth.email_verificado']);
    const todos = JSON.stringify((await db.query('select * from audit_logs where user_id = $1', [id])).rows);
    expect(todos).not.toContain(codigo);
    expect(todos).not.toContain(email);
  });
});

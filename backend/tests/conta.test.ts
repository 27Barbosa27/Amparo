import { SignJWT, createLocalJWKSet, exportJWK, generateKeyPair } from 'jose';
import request from 'supertest';
import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { criarVerificadorExterno } from '../src/auth/externo.js';
import { loadConfig } from '../src/config.js';
import { createPool } from '../src/db.js';

const config = loadConfig();
const db = createPool(config.DATABASE_URL);
const linhas: Record<string, unknown>[] = [];
let app = createApp(db, config, { auth: { limitarPorIp: false }, dispositivos: { limitarCodigos: false }, registar: (l) => linhas.push(l) });
const utilizadores: string[] = [];
const perfis: string[] = [];

afterEach(async () => {
  linhas.length = 0;
  if (perfis.length) await db.query('delete from profiles where id = any($1::uuid[])', [perfis.splice(0)]);
  if (utilizadores.length) await db.query('delete from users where id = any($1::uuid[])', [utilizadores.splice(0)]);
});
afterAll(async () => {
  await db.end();
});

let n = 0;
type Conta = { id: string; token: string; email: string; refresh: string };
async function conta(nome = 'Ana'): Promise<Conta> {
  const email = `conta.${Date.now()}.${++n}@exemplo.pt`;
  const r = await request(app).post('/auth/registo').send({ email, senha: 'uma-senha-segura-123', nome, aceitaTermos: true });
  utilizadores.push(r.body.utilizador.id);
  return { id: r.body.utilizador.id, token: r.body.accessToken, email, refresh: r.body.refreshToken };
}
const auth = (c: { token: string }, p?: string) => ({ Authorization: `Bearer ${c.token}`, ...(p ? { 'X-Profile-Id': p } : {}) });
async function perfil(c: Conta, nome = 'Avó Rosa'): Promise<string> {
  const r = await request(app).post('/profiles').set(auth(c)).send({ pseudonimo: nome, autorizacaoDeclarada: true });
  perfis.push(r.body.perfil.id);
  return r.body.perfil.id;
}
async function partilhar(dono: Conta, outro: Conta, p: string) {
  await db.query("insert into profile_access (user_id, profile_id, papel, autorizacao_declarada_em, autorizacao_versao) values ($1, $2, 'caregiver', now(), '2026-11')", [outro.id, p]);
  expect(dono.id).toBeTruthy();
}
async function umaToma(c: Conta, p: string) {
  const m = await request(app).post(`/profiles/${p}/medicamentos`).set(auth(c)).send({ nome: 'Metformina 850 mg', notas: 'Com a refeição' });
  const r = await request(app).post(`/profiles/${p}/receitas`).set(auth(c)).send({
    medicamentoId: m.body.medicamento.id,
    dose: '1 comprimido',
    horario: { tipo: 'horas_fixas', horasLocais: ['08:00'] },
    inicio: new Date(Date.now() + 3_600_000).toISOString(),
  });
  const { rows } = await db.query('select id from tomas where receita_id = $1 order by agendada_utc limit 1', [r.body.receita.id]);
  return { medicamentoId: m.body.medicamento.id as string, receitaId: r.body.receita.id as string, tomaId: rows[0].id as string };
}
const auditoria = async (p: string, like: string) =>
  (await db.query('select acao, entidade, entidade_id, user_id from audit_logs where profile_id = $1 and acao like $2 order by id', [p, like])).rows;

describe('Auditoria das leituras', () => {
  it('regista cada leitura de dados de saúde por um cuidador, só com ids', async () => {
    const a = await conta();
    const p = await perfil(a);
    const t = await umaToma(a, p);
    await request(app).get(`/profiles/${p}/medicamentos`).set(auth(a));
    await request(app).get(`/profiles/${p}/medicamentos/${t.medicamentoId}`).set(auth(a));
    await request(app).get(`/profiles/${p}/receitas`).set(auth(a));
    await request(app).get(`/profiles/${p}/receitas/${t.receitaId}`).set(auth(a));
    await request(app).get(`/tomas/${t.tomaId}`).set(auth(a, p));
    await request(app).get('/tomas').set(auth(a, p));
    const l = await auditoria(p, '%.ler');
    expect(l.map((x) => x.acao)).toEqual(['medicamento.ler', 'medicamento.ler', 'receita.ler', 'receita.ler', 'toma.ler', 'toma.ler']);
    expect(l[1]!.entidade_id).toBe(t.medicamentoId);
    expect(l[3]!.entidade_id).toBe(t.receitaId);
    expect(l[4]!.entidade_id).toBe(t.tomaId);
    expect(l[0]!.entidade_id).toBeNull(); // uma listagem não tem um id
    expect(l.every((x) => x.user_id === a.id)).toBe(true);
    expect(JSON.stringify(l)).not.toContain('Metformina');
  });

  it('o telemóvel da pessoa lê as suas tomas sem encher a auditoria de cuidadores, e o acesso recusado não deixa rasto no perfil', async () => {
    const a = await conta('Ana');
    const b = await conta('Bruno');
    const p = await perfil(a);
    const t = await umaToma(a, p);
    const cod = await request(app).post(`/profiles/${p}/pairing-codes`).set(auth(a));
    const red = await request(app).post('/pairing/redeem').send({ codigo: cod.body.codigo });
    await request(app).get('/tomas').set({ Authorization: `Bearer ${red.body.token}` });
    expect(await auditoria(p, 'toma.ler')).toEqual([]);
    await request(app).get(`/tomas/${t.tomaId}`).set(auth(b, p));
    await request(app).get(`/profiles/${p}/medicamentos`).set(auth(b));
    expect(await auditoria(p, '%.ler')).toEqual([]);
  });
});

describe('Exportação (portabilidade)', () => {
  it('o owner exporta o perfil completo, em claro, sem tokens, hashes nem identificar cuidadores', async () => {
    const a = await conta('Ana');
    const p = await perfil(a);
    const t = await umaToma(a, p);
    const cod = await request(app).post(`/profiles/${p}/pairing-codes`).set(auth(a));
    await request(app).post('/pairing/redeem').send({ codigo: cod.body.codigo, nome: 'Telemóvel da Rosa' });
    const r = await request(app).get(`/profiles/${p}/exportacao`).set(auth(a));
    expect(r.status).toBe(200);
    expect(r.body.perfil).toMatchObject({ pseudonimo: 'Avó Rosa', timezone: 'Europe/Lisbon' });
    expect(r.body.medicamentos[0]).toMatchObject({ nome: 'Metformina 850 mg', notas: 'Com a refeição' });
    expect(r.body.receitas[0]).toMatchObject({ id: t.receitaId, dose: '1 comprimido' });
    expect(r.body.tomas.length).toBeGreaterThan(80);
    expect(r.body.cuidadores).toHaveLength(1);
    expect(r.body.dispositivos[0].nome).toBe('Telemóvel da Rosa');
    const texto = JSON.stringify(r.body);
    for (const segredo of ['amp_d_', 'token_hash', 'chave_cifrada', a.email, a.id]) expect(texto).not.toContain(segredo);
    expect((await auditoria(p, 'perfil.exportar')).length).toBe(1);
  });

  it('só o owner exporta; quem não tem acesso recebe 404', async () => {
    const a = await conta('Ana');
    const b = await conta('Bruno');
    const c = await conta('Carla');
    const p = await perfil(a);
    await partilhar(a, c, p);
    expect((await request(app).get(`/profiles/${p}/exportacao`).set(auth(c))).status).toBe(403);
    expect((await request(app).get(`/profiles/${p}/exportacao`).set(auth(b))).status).toBe(404);
    expect((await request(app).get(`/profiles/${p}/exportacao`)).status).toBe(401);
  });

  it('exporta os dados da conta, incluindo o email decifrado e o telefone', async () => {
    const a = await conta('Ana');
    const p = await perfil(a);
    await request(app).patch('/auth/me').set(auth(a)).send({ telefone: '+351 912 345 678' });
    const r = await request(app).get('/auth/me/exportacao').set(auth(a));
    expect(r.status).toBe(200);
    expect(r.body.conta).toMatchObject({ id: a.id, nome: 'Ana', email: a.email, telefone: '+351 912 345 678' });
    expect(r.body.conta.consentimentoVersao).toBeTruthy();
    expect(r.body.perfis).toEqual([{ id: p, pseudonimo: 'Avó Rosa', papel: 'owner' }]);
    expect(JSON.stringify(r.body)).not.toMatch(/password|hash/i);
    expect((await request(app).get('/auth/me/exportacao')).status).toBe(401);
  });
});

describe('Apagar a conta', () => {
  it('exige a palavra-passe certa e, sem ela, não apaga nada', async () => {
    const a = await conta();
    const p = await perfil(a);
    for (const corpo of [{}, { senha: 'errada-errada-1' }, { confirmar: true }]) {
      const r = await request(app).delete('/auth/me').set(auth(a)).send(corpo);
      expect(r.status).toBe(403);
      expect(r.body).toEqual({ erro: 'senha_incorreta' });
    }
    expect((await db.query('select 1 from users where id = $1', [a.id])).rowCount).toBe(1);
    expect((await db.query('select 1 from profiles where id = $1', [p])).rowCount).toBe(1);
    expect((await request(app).delete('/auth/me').send({ senha: 'uma-senha-segura-123' })).status).toBe(401);
  });

  it('apaga a conta, os perfis só dela e tudo o que depende deles, e corta as sessões', async () => {
    const a = await conta();
    const p = await perfil(a);
    const t = await umaToma(a, p);
    const cod = await request(app).post(`/profiles/${p}/pairing-codes`).set(auth(a));
    const red = await request(app).post('/pairing/redeem').send({ codigo: cod.body.codigo });
    const r = await request(app).delete('/auth/me').set(auth(a)).send({ senha: 'uma-senha-segura-123' });
    expect(r.status).toBe(204);
    for (const [tabela, coluna, valor] of [
      ['users', 'id', a.id], ['profiles', 'id', p], ['medicamentos', 'id', t.medicamentoId],
      ['receitas', 'id', t.receitaId], ['tomas', 'id', t.tomaId], ['profile_access', 'user_id', a.id],
    ] as const) {
      expect((await db.query(`select 1 from ${tabela} where ${coluna} = $1`, [valor])).rowCount, tabela).toBe(0);
    }
    expect((await request(app).post('/auth/refresh').send({ refreshToken: a.refresh })).status).toBe(401);
    expect((await request(app).get('/auth/me').set(auth(a))).status).toBe(401);
    expect((await request(app).get('/tomas').set({ Authorization: `Bearer ${red.body.token}` })).status).toBe(401);
    expect((await request(app).post('/auth/login').send({ email: a.email, senha: 'uma-senha-segura-123' })).status).toBe(401);
    // a auditoria fica
    expect((await auditoria(p, 'perfil.apagar')).length).toBe(1);
    expect((await db.query("select 1 from audit_logs where acao = 'auth.apagar_conta' and entidade_id = $1", [a.id])).rowCount).toBe(1);
  });

  it('num perfil partilhado, o perfil fica e o cuidador mais antigo passa a owner', async () => {
    const a = await conta('Ana');
    const b = await conta('Bruno');
    const p = await perfil(a);
    await partilhar(a, b, p);
    expect((await request(app).delete('/auth/me').set(auth(a)).send({ senha: 'uma-senha-segura-123' })).status).toBe(204);
    expect((await db.query('select 1 from profiles where id = $1', [p])).rowCount).toBe(1);
    const r = await request(app).get(`/profiles/${p}`).set(auth(b));
    expect(r.status).toBe(200);
    expect(r.body.perfil.papel).toBe('owner');
  });

  it('uma conta só com Apple/Google confirma com "confirmar: true"', async () => {
    const par = await generateKeyPair('RS256');
    const jwk = { ...(await exportJWK(par.publicKey)), kid: 'k1' };
    const verificadorExterno = criarVerificadorExterno({ googleClientIds: ['g-web'] }, { google: createLocalJWKSet({ keys: [jwk] }) });
    const appExt = createApp(db, config, { auth: { limitarPorIp: false, verificadorExterno }, registar: false });
    const idToken = await new SignJWT({ nonce: 'nonce-da-app-123' })
      .setProtectedHeader({ alg: 'RS256', kid: 'k1' })
      .setIssuer('https://accounts.google.com').setAudience('g-web').setSubject(`g.${Date.now()}`).setIssuedAt().setExpirationTime('5m')
      .sign(par.privateKey);
    const e = await request(appExt).post('/auth/google').send({ idToken, nonce: 'nonce-da-app-123', aceitaTermos: true });
    utilizadores.push(e.body.utilizador.id);
    const h = { Authorization: `Bearer ${e.body.accessToken}` };
    expect((await request(appExt).delete('/auth/me').set(h).send({})).status).toBe(403);
    expect((await request(appExt).delete('/auth/me').set(h).send({ confirmar: true })).status).toBe(204);
    expect((await db.query('select 1 from users where id = $1', [e.body.utilizador.id])).rowCount).toBe(0);
  });
});

describe('Registo de pedidos e limite global', () => {
  it('o registo só tem método, rota sem ids, estado e duração, e nunca dados pessoais', async () => {
    const a = await conta('Ana');
    const p = await perfil(a);
    const t = await umaToma(a, p);
    linhas.length = 0;
    await request(app).get(`/profiles/${p}/medicamentos/${t.medicamentoId}?segredo=valor`).set(auth(a));
    await request(app).post('/auth/login').send({ email: a.email, senha: 'errada-errada-1' });
    const texto = JSON.stringify(linhas);
    for (const proibido of [p, t.medicamentoId, a.email, 'errada-errada', 'segredo', 'valor', 'Metformina', a.token, '127.0.0.1']) {
      expect(texto).not.toContain(proibido);
    }
    expect(linhas[0]).toMatchObject({ metodo: 'GET', rota: '/profiles/:id/medicamentos/:id', estado: 200 });
    expect(Object.keys(linhas[0]!).sort()).toEqual(['estado', 'metodo', 'ms', 'rota', 'ts']);
    expect(linhas[1]).toMatchObject({ metodo: 'POST', rota: '/auth/login', estado: 401 });
  });

  it('o limite global devolve 429 sem atingir a saúde do servidor (/health fica de fora)', async () => {
    const limitada = createApp(db, config, { auth: { limitarPorIp: false }, registar: false, limiteGlobal: { janelaMs: 60_000, maximo: 3 } });
    const estados: number[] = [];
    for (let i = 0; i < 5; i++) estados.push((await request(limitada).get('/auth/me')).status);
    expect(estados).toEqual([401, 401, 401, 429, 429]);
    for (let i = 0; i < 10; i++) expect((await request(limitada).get('/health')).status).toBe(200);
  });
});

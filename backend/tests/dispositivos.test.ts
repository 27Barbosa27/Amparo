import request from 'supertest';
import { afterAll, afterEach, describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { createPool } from '../src/db.js';

const config = loadConfig();
const db = createPool(config.DATABASE_URL);
const app = createApp(db, config, { auth: { limitarPorIp: false }, dispositivos: { limitarCodigos: false } });
const utilizadores: string[] = [];
const perfis: string[] = [];

afterEach(async () => {
  if (perfis.length) await db.query('delete from profiles where id = any($1::uuid[])', [perfis.splice(0)]);
  if (utilizadores.length) await db.query('delete from users where id = any($1::uuid[])', [utilizadores.splice(0)]);
});
afterAll(async () => {
  await db.end();
});

let n = 0;
type Conta = { id: string; token: string };
async function conta(nome = 'Ana'): Promise<Conta> {
  const email = `disp.${Date.now()}.${++n}@exemplo.pt`;
  const r = await request(app).post('/auth/registo').send({ email, senha: 'uma-senha-segura-123', nome, aceitaTermos: true });
  utilizadores.push(r.body.utilizador.id);
  return { id: r.body.utilizador.id, token: r.body.accessToken };
}
const auth = (c: { token: string }) => ({ Authorization: `Bearer ${c.token}` });
async function perfil(c: Conta, pseudonimo = 'Avó Rosa'): Promise<string> {
  const r = await request(app).post('/profiles').set(auth(c)).send({ pseudonimo, autorizacaoDeclarada: true });
  perfis.push(r.body.perfil.id);
  return r.body.perfil.id;
}
async function codigo(c: Conta, p: string) {
  const r = await request(app).post(`/profiles/${p}/pairing-codes`).set(auth(c));
  expect(r.status).toBe(201);
  return r.body as { id: string; codigo: string; expiraEm: string };
}
async function ligar(c: Conta, p: string, nome = 'Telemóvel da Rosa') {
  const cod = await codigo(c, p);
  const r = await request(app).post('/pairing/redeem').send({ codigo: cod.codigo, nome });
  expect(r.status, JSON.stringify(r.body)).toBe(201);
  return { token: r.body.token as string, dispositivoId: r.body.dispositivoId as string, codigoId: cod.id, perfil: r.body.perfil };
}

describe('Código de ligação', () => {
  it('tem 6 dígitos, expira em 15 minutos e só o hash fica guardado', async () => {
    const a = await conta();
    const p = await perfil(a);
    const c = await codigo(a, p);
    expect(c.codigo).toMatch(/^\d{6}$/);
    const min = (new Date(c.expiraEm).getTime() - Date.now()) / 60_000;
    expect(min).toBeGreaterThan(14);
    expect(min).toBeLessThanOrEqual(15);
    const { rows } = await db.query('select codigo_hash from pairing_codes where id = $1', [c.id]);
    expect(rows[0].codigo_hash).toHaveLength(32);
    expect(rows[0].codigo_hash.toString('utf8')).not.toContain(c.codigo);
  });

  it('um código novo anula o anterior do mesmo perfil', async () => {
    const a = await conta();
    const p = await perfil(a);
    const c1 = await codigo(a, p);
    await codigo(a, p);
    const r = await request(app).post('/pairing/redeem').send({ codigo: c1.codigo });
    expect(r.status).toBe(400);
  });

  it('o estado vai de "a_espera" a "ligado"', async () => {
    const a = await conta();
    const p = await perfil(a);
    const c = await codigo(a, p);
    expect((await request(app).get(`/profiles/${p}/pairing-codes/${c.id}`).set(auth(a))).body).toEqual({ estado: 'a_espera' });
    await request(app).post('/pairing/redeem').send({ codigo: c.codigo });
    expect((await request(app).get(`/profiles/${p}/pairing-codes/${c.id}`).set(auth(a))).body).toEqual({ estado: 'ligado' });
  });

  it('mostra "expirado" depois do prazo', async () => {
    const a = await conta();
    const p = await perfil(a);
    const c = await codigo(a, p);
    await db.query("update pairing_codes set expira_em = now() - interval '1 second' where id = $1", [c.id]);
    expect((await request(app).get(`/profiles/${p}/pairing-codes/${c.id}`).set(auth(a))).body).toEqual({ estado: 'expirado' });
  });
});

describe('Resgatar o código (telemóvel da pessoa)', () => {
  it('devolve um token de dispositivo e os dados mínimos do perfil; só o hash do token fica guardado', async () => {
    const a = await conta();
    const p = await perfil(a);
    const d = await ligar(a, p);
    expect(d.token.startsWith('amp_d_')).toBe(true);
    expect(d.perfil).toMatchObject({ id: p, pseudonimo: 'Avó Rosa', tamanhoTexto: 'grande' });
    const { rows } = await db.query('select token_hash, nome from profile_devices where id = $1', [d.dispositivoId]);
    expect(rows[0].nome).toBe('Telemóvel da Rosa');
    expect(rows[0].token_hash.toString('utf8')).not.toContain(d.token);
  });

  it('é de uso único', async () => {
    const a = await conta();
    const p = await perfil(a);
    const c = await codigo(a, p);
    expect((await request(app).post('/pairing/redeem').send({ codigo: c.codigo })).status).toBe(201);
    const segunda = await request(app).post('/pairing/redeem').send({ codigo: c.codigo });
    expect(segunda.status).toBe(400);
    expect(segunda.body).toEqual({ erro: 'codigo_invalido' });
  });

  it('código errado, expirado e já usado dão exatamente a mesma resposta', async () => {
    const a = await conta();
    const p = await perfil(a);
    const expirado = await codigo(a, p);
    await db.query("update pairing_codes set expira_em = now() - interval '1 minute' where id = $1", [expirado.id]);
    const usado = await codigo(a, p);
    await request(app).post('/pairing/redeem').send({ codigo: usado.codigo });
    const respostas = await Promise.all(
      [expirado.codigo, usado.codigo, '000000', '123abc', '12345', ''].map((c) => request(app).post('/pairing/redeem').send({ codigo: c })),
    );
    for (const r of respostas) {
      expect(r.status).toBe(400);
      expect(r.body).toEqual({ erro: 'codigo_invalido' });
    }
    expect((await request(app).post('/pairing/redeem').send({})).body).toEqual({ erro: 'codigo_invalido' });
  });

  it('limita as tentativas falhadas por IP e não conta as bem-sucedidas', async () => {
    const limitada = createApp(db, config, { auth: { limitarPorIp: false }, dispositivos: { limitarCodigos: { janelaMs: 60_000, maximo: 3 } } });
    const a = await conta();
    const p = await perfil(a);
    for (let i = 0; i < 2; i++) {
      const c = await codigo(a, p);
      expect((await request(limitada).post('/pairing/redeem').send({ codigo: c.codigo })).status).toBe(201);
    }
    const estados: number[] = [];
    for (let i = 0; i < 5; i++) estados.push((await request(limitada).post('/pairing/redeem').send({ codigo: '000000' })).status);
    expect(estados).toEqual([400, 400, 400, 429, 429]);
  });

  it('a ligação fica na auditoria, sem dados de saúde', async () => {
    const a = await conta();
    const p = await perfil(a);
    const d = await ligar(a, p);
    const { rows } = await db.query("select acao, user_id, entidade_id from audit_logs where profile_id = $1 and acao like 'dispositivo.%' order by id", [p]);
    expect(rows.map((r) => r.acao)).toEqual(['dispositivo.codigo_criar', 'dispositivo.ligar']);
    expect(rows[1].user_id).toBe(a.id);
    expect(rows[1].entidade_id).toBe(d.dispositivoId);
  });
});

describe('Âmbito do token de dispositivo', () => {
  it('só acede ao seu perfil: não vê perfis, não os altera, não gera códigos nem edita receitas', async () => {
    const a = await conta();
    const p = await perfil(a);
    const d = await ligar(a, p);
    const dev = { Authorization: `Bearer ${d.token}` };
    const proibidos = [
      request(app).get('/profiles').set(dev),
      request(app).get(`/profiles/${p}`).set(dev),
      request(app).patch(`/profiles/${p}`).set(dev).send({ pseudonimo: 'X' }),
      request(app).delete(`/profiles/${p}`).set(dev),
      request(app).post(`/profiles/${p}/pairing-codes`).set(dev),
      request(app).get(`/profiles/${p}/devices`).set(dev),
      request(app).post(`/profiles/${p}/medicamentos`).set(dev).send({ nome: 'X' }),
      request(app).get('/auth/me').set(dev),
    ];
    for (const r of await Promise.all(proibidos)) expect(r.status).toBe(401);
  });

  it('um cuidador não usa o heartbeat; o dispositivo sim', async () => {
    const a = await conta();
    const p = await perfil(a);
    const d = await ligar(a, p);
    const corpo = { alarmesAgendados: 12, permissoes: { alarmesExatos: true, bateriaSemLimites: false, ecraBloqueado: true } };
    expect((await request(app).post('/devices/heartbeat').set(auth(a)).send(corpo)).status).toBe(403);
    expect((await request(app).post('/devices/heartbeat').send(corpo)).status).toBe(401);
    expect((await request(app).post('/devices/heartbeat').set({ Authorization: `Bearer ${d.token}` }).send(corpo)).status).toBe(204);
    expect((await request(app).post('/devices/heartbeat').set({ Authorization: `Bearer ${d.token}` }).send({ alarmesAgendados: -1 })).status).toBe(400);
  });

  it('um token inventado ou adulterado não entra', async () => {
    const a = await conta();
    const p = await perfil(a);
    const d = await ligar(a, p);
    for (const t of ['amp_d_inventado', d.token + 'x', d.token.slice(0, -2), 'amp_d_']) {
      const r = await request(app).post('/devices/heartbeat').set({ Authorization: `Bearer ${t}` }).send({});
      expect(r.status, t).toBe(401);
    }
  });
});

describe('Dispositivos ligados (cuidador)', () => {
  it('lista nome, ligado desde, última ligação e o estado reportado pelo telemóvel', async () => {
    const a = await conta();
    const p = await perfil(a);
    const d = await ligar(a, p);
    await request(app)
      .post('/devices/heartbeat')
      .set({ Authorization: `Bearer ${d.token}` })
      .send({ alarmesAgendados: 12, permissoes: { alarmesExatos: true, bateriaSemLimites: false, ecraBloqueado: true } });
    const r = await request(app).get(`/profiles/${p}/devices`).set(auth(a));
    expect(r.body.dispositivos).toHaveLength(1);
    expect(r.body.dispositivos[0]).toMatchObject({
      id: d.dispositivoId, nome: 'Telemóvel da Rosa', alarmesAgendados: 12,
      permissoes: { alarmesExatos: true, bateriaSemLimites: false, ecraBloqueado: true },
    });
    expect(r.body.dispositivos[0].ultimaLigacao).toBeTruthy();
    expect(JSON.stringify(r.body)).not.toContain('amp_d_');
  });

  it('revogar corta o acesso de imediato e fica na auditoria', async () => {
    const a = await conta();
    const p = await perfil(a);
    const d = await ligar(a, p);
    const dev = { Authorization: `Bearer ${d.token}` };
    const corpo = { alarmesAgendados: 1, permissoes: { alarmesExatos: true, bateriaSemLimites: true, ecraBloqueado: true } };
    expect((await request(app).post('/devices/heartbeat').set(dev).send(corpo)).status).toBe(204);
    expect((await request(app).delete(`/profiles/${p}/devices/${d.dispositivoId}`).set(auth(a))).status).toBe(204);
    expect((await request(app).post('/devices/heartbeat').set(dev).send(corpo)).status).toBe(401);
    expect((await request(app).get(`/profiles/${p}/devices`).set(auth(a))).body.dispositivos).toEqual([]);
    expect((await request(app).delete(`/profiles/${p}/devices/${d.dispositivoId}`).set(auth(a))).status).toBe(404);
    const audit = await db.query("select count(*)::int n from audit_logs where profile_id = $1 and acao = 'dispositivo.revogar'", [p]);
    expect(audit.rows[0].n).toBe(1);
  });

  it('apagar o perfil corta também os dispositivos', async () => {
    const a = await conta();
    const p = await perfil(a);
    const d = await ligar(a, p);
    await request(app).delete(`/profiles/${p}`).set(auth(a));
    const r = await request(app).post('/devices/heartbeat').set({ Authorization: `Bearer ${d.token}` }).send({});
    expect(r.status).toBe(401);
  });
});

describe('IDOR nos dispositivos', () => {
  it('B não gera códigos, não vê estados, não lista nem revoga dispositivos do perfil de A', async () => {
    const a = await conta('Ana');
    const b = await conta('Bruno');
    const p = await perfil(a);
    const d = await ligar(a, p);
    const pedidos = [
      request(app).post(`/profiles/${p}/pairing-codes`).set(auth(b)),
      request(app).get(`/profiles/${p}/pairing-codes/${d.codigoId}`).set(auth(b)),
      request(app).get(`/profiles/${p}/devices`).set(auth(b)),
      request(app).delete(`/profiles/${p}/devices/${d.dispositivoId}`).set(auth(b)),
    ];
    for (const r of await Promise.all(pedidos)) {
      expect(r.status).toBe(404);
      expect(r.body).toEqual({ erro: 'perfil_nao_encontrado' });
    }
    const intacto = await db.query('select revogado_em from profile_devices where id = $1', [d.dispositivoId]);
    expect(intacto.rows[0].revogado_em).toBeNull();
  });

  it('B não revoga um dispositivo de A usando o seu próprio perfil', async () => {
    const a = await conta('Ana');
    const b = await conta('Bruno');
    const pa = await perfil(a);
    const pb = await perfil(b, 'Do Bruno');
    const d = await ligar(a, pa);
    expect((await request(app).delete(`/profiles/${pb}/devices/${d.dispositivoId}`).set(auth(b))).status).toBe(404);
    expect((await request(app).get(`/profiles/${pb}/pairing-codes/${d.codigoId}`).set(auth(b))).status).toBe(404);
    const intacto = await db.query('select revogado_em from profile_devices where id = $1', [d.dispositivoId]);
    expect(intacto.rows[0].revogado_em).toBeNull();
  });
});

describe('Contacto do cuidador', () => {
  it('o telefone fica cifrado e é visível ao dispositivo ligado e a quem tem acesso ao perfil', async () => {
    const a = await conta('Ana');
    const b = await conta('Bruno');
    const p = await perfil(a);
    const d = await ligar(a, p);
    expect((await request(app).patch('/auth/me').set(auth(a)).send({ telefone: '+351 912 345 678' })).status).toBe(204);
    const { rows } = await db.query('select telefone_cifrado from users where id = $1', [a.id]);
    expect(rows[0].telefone_cifrado.toString('utf8')).not.toContain('912');
    expect((await request(app).get('/auth/me').set(auth(a))).body.utilizador.telefone).toBe('+351 912 345 678');

    const doDispositivo = await request(app).get('/contacto').set({ Authorization: `Bearer ${d.token}` });
    expect(doDispositivo.body.contactos).toEqual([{ nome: 'Ana', telefone: '+351 912 345 678' }]);
    const doCuidador = await request(app).get('/contacto').set(auth(a)).set('X-Profile-Id', p);
    expect(doCuidador.body.contactos).toHaveLength(1);

    // quem não tem acesso ao perfil não vê o contacto, e o dispositivo ignora um X-Profile-Id de outro perfil
    expect((await request(app).get('/contacto').set(auth(b)).set('X-Profile-Id', p)).status).toBe(404);
    const pb = await perfil(b, 'Do Bruno');
    const comCabecalho = await request(app).get('/contacto').set({ Authorization: `Bearer ${d.token}` }).set('X-Profile-Id', pb);
    expect(comCabecalho.body.contactos).toEqual([{ nome: 'Ana', telefone: '+351 912 345 678' }]);
  });

  it('valida o telefone e permite apagá-lo', async () => {
    const a = await conta();
    expect((await request(app).patch('/auth/me').set(auth(a)).send({ telefone: 'abc' })).status).toBe(400);
    expect((await request(app).patch('/auth/me').set(auth(a)).send({})).status).toBe(400);
    await request(app).patch('/auth/me').set(auth(a)).send({ telefone: '912345678' });
    await request(app).patch('/auth/me').set(auth(a)).send({ telefone: null });
    expect((await request(app).get('/auth/me').set(auth(a))).body.utilizador.telefone).toBeNull();
  });
});

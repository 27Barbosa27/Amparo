import request from 'supertest';
import { afterAll, afterEach, describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { decifrar, lerChave } from '../src/auth/cifra.js';
import { loadConfig } from '../src/config.js';
import { createPool } from '../src/db.js';

const config = loadConfig();
const db = createPool(config.DATABASE_URL);
const app = createApp(db, config, { auth: { limitarPorIp: false } });
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
async function conta(nome = 'Ana') {
  const email = `perfis.${Date.now()}.${++n}@exemplo.pt`;
  const r = await request(app).post('/auth/registo').send({ email, senha: 'uma-senha-segura-123', nome, aceitaTermos: true });
  utilizadores.push(r.body.utilizador.id);
  return { id: r.body.utilizador.id as string, token: r.body.accessToken as string };
}
const auth = (c: { token: string }) => ({ Authorization: `Bearer ${c.token}` });

async function novoPerfil(c: { token: string }, extra: object = {}) {
  const r = await request(app).post('/profiles').set(auth(c)).send({ pseudonimo: 'Avó Rosa', autorizacaoDeclarada: true, ...extra });
  expect(r.status).toBe(201);
  perfis.push(r.body.perfil.id);
  return r.body.perfil as { id: string; pseudonimo: string; papel: string };
}

describe('Criar e listar perfis', () => {
  it('cria um perfil, com quem o cria como owner e as predefinições do design', async () => {
    const a = await conta();
    const p = await novoPerfil(a);
    expect(p).toMatchObject({ pseudonimo: 'Avó Rosa', papel: 'owner', timezone: 'Europe/Lisbon', tamanhoTexto: 'grande', alarmesEm: 'dispositivo_da_pessoa' });
  });

  it('guarda a declaração de autorização e cria as preferências de alertas', async () => {
    const a = await conta();
    const p = await novoPerfil(a);
    const acesso = await db.query('select papel, autorizacao_declarada_em, autorizacao_versao from profile_access where profile_id = $1', [p.id]);
    expect(acesso.rows).toHaveLength(1);
    expect(acesso.rows[0].autorizacao_declarada_em).toBeInstanceOf(Date);
    expect(acesso.rows[0].autorizacao_versao).toBeTruthy();
    const prefs = await db.query('select toma_nao_confirmada, espera_min from alert_prefs where profile_id = $1', [p.id]);
    expect(prefs.rows[0]).toMatchObject({ toma_nao_confirmada: true, espera_min: 15 });
  });

  it('cada perfil tem uma chave própria, cifrada, e que se abre com a chave-mestra', async () => {
    const a = await conta();
    const p1 = await novoPerfil(a);
    const p2 = await novoPerfil(a, { pseudonimo: 'Outro' });
    const { rows } = await db.query('select id, chave_cifrada from profiles where id = any($1::uuid[])', [[p1.id, p2.id]]);
    const mestra = lerChave(config.PROFILE_MASTER_KEY);
    const chaves = rows.map((r) => decifrar(r.chave_cifrada as Buffer, mestra));
    expect(chaves).toHaveLength(2);
    expect(chaves[0]).not.toBe(chaves[1]);
    expect(Buffer.from(chaves[0]!, 'base64url')).toHaveLength(32);
  });

  it('exige a declaração de autorização', async () => {
    const a = await conta();
    const r = await request(app).post('/profiles').set(auth(a)).send({ pseudonimo: 'X' });
    expect(r.status).toBe(400);
    const falsa = await request(app).post('/profiles').set(auth(a)).send({ pseudonimo: 'X', autorizacaoDeclarada: false });
    expect(falsa.status).toBe(400);
  });

  it.each([
    ['pseudónimo vazio', { pseudonimo: '  ' }],
    ['pseudónimo enorme', { pseudonimo: 'a'.repeat(41) }],
    ['fuso desconhecido', { timezone: 'Marte/Olympus' }],
    ['tamanho de texto inválido', { tamanhoTexto: 'gigante' }],
    ['alarmes em sítio inválido', { alarmesEm: 'na_lua' }],
  ])('rejeita %s', async (_nome, alteracao) => {
    const a = await conta();
    const r = await request(app).post('/profiles').set(auth(a)).send({ pseudonimo: 'X', autorizacaoDeclarada: true, ...alteracao });
    expect(r.status).toBe(400);
    expect(r.body.erro).toBe('pedido_invalido');
  });

  it('lista só os perfis do próprio utilizador', async () => {
    const a = await conta();
    const b = await conta('Bruno');
    const pa = await novoPerfil(a, { pseudonimo: 'Da Ana' });
    const pb = await novoPerfil(b, { pseudonimo: 'Do Bruno' });
    const la = await request(app).get('/profiles').set(auth(a));
    expect(la.body.perfis.map((p: { id: string }) => p.id)).toEqual([pa.id]);
    const lb = await request(app).get('/profiles').set(auth(b));
    expect(lb.body.perfis.map((p: { id: string }) => p.id)).toEqual([pb.id]);
  });

  it('um utilizador gere vários perfis', async () => {
    const a = await conta();
    await novoPerfil(a, { pseudonimo: 'Maria' });
    await novoPerfil(a, { pseudonimo: 'Manuel' });
    const l = await request(app).get('/profiles').set(auth(a));
    expect(l.body.perfis.map((p: { pseudonimo: string }) => p.pseudonimo)).toEqual(['Maria', 'Manuel']);
  });

  it('exige autenticação em todas as rotas de perfis', async () => {
    const a = await conta();
    const p = await novoPerfil(a);
    const rotas = [
      ['get', '/profiles'],
      ['post', '/profiles'],
      ['get', `/profiles/${p.id}`],
      ['patch', `/profiles/${p.id}`],
      ['delete', `/profiles/${p.id}`],
      ['get', '/perfil-ativo'],
    ] as const;
    for (const [metodo, url] of rotas) {
      const r = await request(app)[metodo](url);
      expect(r.status, `${metodo} ${url}`).toBe(401);
    }
  });
});

describe('IDOR: o utilizador B nunca acede aos perfis do utilizador A', () => {
  async function cenario() {
    const a = await conta('Ana');
    const b = await conta('Bruno');
    const p = await novoPerfil(a);
    return { a, b, p };
  }

  it('B não vê o perfil de A (nem a ler, nem a alterar, nem a apagar)', async () => {
    const { b, p } = await cenario();
    const ler = await request(app).get(`/profiles/${p.id}`).set(auth(b));
    const alterar = await request(app).patch(`/profiles/${p.id}`).set(auth(b)).send({ pseudonimo: 'Hackeado' });
    const apagar = await request(app).delete(`/profiles/${p.id}`).set(auth(b));
    for (const r of [ler, alterar, apagar]) {
      expect(r.status).toBe(404);
      expect(r.body).toEqual({ erro: 'perfil_nao_encontrado' });
    }
    const { rows } = await db.query('select pseudonimo from profiles where id = $1', [p.id]);
    expect(rows).toHaveLength(1);
    expect(rows[0].pseudonimo).toBe('Avó Rosa');
  });

  it('a resposta para um perfil alheio é idêntica à de um perfil que não existe', async () => {
    const { b, p } = await cenario();
    const alheio = await request(app).get(`/profiles/${p.id}`).set(auth(b));
    const inexistente = await request(app).get('/profiles/11111111-1111-4111-8111-111111111111').set(auth(b));
    const lixo = await request(app).get('/profiles/isto-nao-e-um-uuid').set(auth(b));
    expect(alheio.status).toBe(inexistente.status);
    expect(alheio.body).toEqual(inexistente.body);
    expect(lixo.status).toBe(404);
    expect(lixo.body).toEqual(alheio.body);
  });

  it('o cabeçalho X-Profile-Id não dá acesso a perfis alheios', async () => {
    const { a, b, p } = await cenario();
    const dono = await request(app).get('/perfil-ativo').set(auth(a)).set('X-Profile-Id', p.id);
    expect(dono.status).toBe(200);
    expect(dono.body.perfil.id).toBe(p.id);
    const intruso = await request(app).get('/perfil-ativo').set(auth(b)).set('X-Profile-Id', p.id);
    expect(intruso.status).toBe(404);
    expect(intruso.body).toEqual({ erro: 'perfil_nao_encontrado' });
    const semCabecalho = await request(app).get('/perfil-ativo').set(auth(a));
    expect(semCabecalho.status).toBe(404);
  });

  it('maiúsculas e identificadores manipulados não saltam a verificação', async () => {
    const { a, b, p } = await cenario();
    const maiusculas = await request(app).get(`/profiles/${p.id.toUpperCase()}`).set(auth(a));
    expect(maiusculas.status).toBe(200);
    const intrusoMaiusculas = await request(app).get(`/profiles/${p.id.toUpperCase()}`).set(auth(b));
    expect(intrusoMaiusculas.status).toBe(404);
    for (const tentativa of [`${p.id}%00`, `${p.id}/../${p.id}`, `${p.id}'--`]) {
      const r = await request(app).get(`/profiles/${encodeURIComponent(tentativa)}`).set(auth(b));
      expect(r.status, tentativa).toBe(404);
    }
  });

  it('só conta o token: um id de utilizador no corpo ou em cabeçalhos extra é ignorado', async () => {
    const { b, p } = await cenario();
    const r = await request(app).get(`/profiles/${p.id}`).set(auth(b)).set('X-User-Id', 'qualquer').send({ userId: 'qualquer' });
    expect(r.status).toBe(404);
  });

  it('o acesso revogado deixa de funcionar de imediato', async () => {
    const { a, p } = await cenario();
    expect((await request(app).get(`/profiles/${p.id}`).set(auth(a))).status).toBe(200);
    await db.query('update profile_access set revogado_em = now() where profile_id = $1 and user_id = $2', [p.id, a.id]);
    expect((await request(app).get(`/profiles/${p.id}`).set(auth(a))).status).toBe(404);
    const lista = await request(app).get('/profiles').set(auth(a));
    expect(lista.body.perfis).toEqual([]);
    const ativo = await request(app).get('/perfil-ativo').set(auth(a)).set('X-Profile-Id', p.id);
    expect(ativo.status).toBe(404);
  });

  it('as tentativas de B não alteram nada de A nem ficam registadas como ações de A', async () => {
    const { a, b, p } = await cenario();
    await request(app).patch(`/profiles/${p.id}`).set(auth(b)).send({ pseudonimo: 'X' });
    await request(app).delete(`/profiles/${p.id}`).set(auth(b));
    const audit = await db.query("select user_id, acao from audit_logs where profile_id = $1 and acao in ('perfil.editar','perfil.apagar')", [p.id]);
    expect(audit.rows).toEqual([]);
    expect((await request(app).get(`/profiles/${p.id}`).set(auth(a))).status).toBe(200);
  });
});

describe('Papéis: owner e caregiver', () => {
  it('um caregiver vê o perfil mas não o pode alterar nem apagar (403)', async () => {
    const a = await conta('Ana');
    const c = await conta('Carla');
    const p = await novoPerfil(a);
    await db.query(
      "insert into profile_access (user_id, profile_id, papel, autorizacao_declarada_em, autorizacao_versao) values ($1, $2, 'caregiver', now(), '2026-11')",
      [c.id, p.id],
    );
    const ler = await request(app).get(`/profiles/${p.id}`).set(auth(c));
    expect(ler.status).toBe(200);
    expect(ler.body.perfil.papel).toBe('caregiver');
    const alterar = await request(app).patch(`/profiles/${p.id}`).set(auth(c)).send({ pseudonimo: 'Nova' });
    expect(alterar.status).toBe(403);
    expect(alterar.body).toEqual({ erro: 'sem_permissao' });
    const apagar = await request(app).delete(`/profiles/${p.id}`).set(auth(c));
    expect(apagar.status).toBe(403);
    const { rows } = await db.query('select pseudonimo from profiles where id = $1', [p.id]);
    expect(rows[0].pseudonimo).toBe('Avó Rosa');
  });

  it('o owner altera o perfil e fica registado na auditoria', async () => {
    const a = await conta();
    const p = await novoPerfil(a);
    const r = await request(app).patch(`/profiles/${p.id}`).set(auth(a)).send({ tamanhoTexto: 'muito_grande', alarmesEm: 'dispositivo_do_cuidador' });
    expect(r.status).toBe(200);
    expect(r.body.perfil).toMatchObject({ tamanhoTexto: 'muito_grande', alarmesEm: 'dispositivo_do_cuidador', pseudonimo: 'Avó Rosa' });
    const audit = await db.query("select count(*)::int n from audit_logs where profile_id = $1 and user_id = $2 and acao = 'perfil.editar'", [p.id, a.id]);
    expect(audit.rows[0].n).toBe(1);
  });

  it('rejeita alterações vazias ou inválidas', async () => {
    const a = await conta();
    const p = await novoPerfil(a);
    expect((await request(app).patch(`/profiles/${p.id}`).set(auth(a)).send({})).status).toBe(400);
    expect((await request(app).patch(`/profiles/${p.id}`).set(auth(a)).send({ timezone: 'Marte/Olympus' })).status).toBe(400);
  });

  it('o owner apaga o perfil e tudo o que depende dele; a auditoria fica', async () => {
    const a = await conta();
    const p = await novoPerfil(a);
    await db.query("insert into medicamentos (profile_id, nome_cifrado) values ($1, '\\x00')", [p.id]);
    const r = await request(app).delete(`/profiles/${p.id}`).set(auth(a));
    expect(r.status).toBe(204);
    expect((await db.query('select 1 from profiles where id = $1', [p.id])).rowCount).toBe(0);
    expect((await db.query('select 1 from medicamentos where profile_id = $1', [p.id])).rowCount).toBe(0);
    expect((await db.query('select 1 from profile_access where profile_id = $1', [p.id])).rowCount).toBe(0);
    const audit = await db.query('select acao from audit_logs where profile_id = $1 order by id', [p.id]);
    expect(audit.rows.map((x) => x.acao)).toEqual(['perfil.criar', 'perfil.apagar']);
    expect((await request(app).get(`/profiles/${p.id}`).set(auth(a))).status).toBe(404);
  });
});

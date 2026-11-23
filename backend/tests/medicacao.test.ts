import request from 'supertest';
import { afterAll, afterEach, describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
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
type Conta = { id: string; token: string };
async function conta(nome = 'Ana'): Promise<Conta> {
  const email = `med.${Date.now()}.${++n}@exemplo.pt`;
  const r = await request(app).post('/auth/registo').send({ email, senha: 'uma-senha-segura-123', nome, aceitaTermos: true });
  utilizadores.push(r.body.utilizador.id);
  return { id: r.body.utilizador.id, token: r.body.accessToken };
}
const auth = (c: Conta) => ({ Authorization: `Bearer ${c.token}` });

async function perfil(c: Conta): Promise<string> {
  const r = await request(app).post('/profiles').set(auth(c)).send({ pseudonimo: 'Avó Rosa', autorizacaoDeclarada: true });
  perfis.push(r.body.perfil.id);
  return r.body.perfil.id;
}
async function medicamento(c: Conta, p: string, nome = 'Metformina 850 mg'): Promise<string> {
  const r = await request(app).post(`/profiles/${p}/medicamentos`).set(auth(c)).send({ nome, notas: 'Com a refeição' });
  expect(r.status).toBe(201);
  return r.body.medicamento.id;
}
const inicio = () => new Date(Date.now() + 3_600_000).toISOString();
const corpoReceita = (medicamentoId: string, extra: object = {}) => ({
  medicamentoId,
  dose: '1 comprimido',
  horario: { tipo: 'horas_fixas', horasLocais: ['20:00', '08:00'] },
  inicio: inicio(),
  ...extra,
});
async function receita(c: Conta, p: string, m: string, extra: object = {}): Promise<string> {
  const r = await request(app).post(`/profiles/${p}/receitas`).set(auth(c)).send(corpoReceita(m, extra));
  expect(r.status, JSON.stringify(r.body)).toBe(201);
  return r.body.receita.id;
}

describe('Medicamentos', () => {
  it('cria, lê, edita e apaga', async () => {
    const a = await conta();
    const p = await perfil(a);
    const id = await medicamento(a, p);
    const ler = await request(app).get(`/profiles/${p}/medicamentos/${id}`).set(auth(a));
    expect(ler.body.medicamento).toMatchObject({ nome: 'Metformina 850 mg', notas: 'Com a refeição' });
    const alt = await request(app).patch(`/profiles/${p}/medicamentos/${id}`).set(auth(a)).send({ nome: 'Metformina 500 mg', notas: null });
    expect(alt.body.medicamento).toMatchObject({ nome: 'Metformina 500 mg', notas: null });
    const lista = await request(app).get(`/profiles/${p}/medicamentos`).set(auth(a));
    expect(lista.body.medicamentos).toHaveLength(1);
    expect((await request(app).delete(`/profiles/${p}/medicamentos/${id}`).set(auth(a))).status).toBe(204);
    expect((await request(app).get(`/profiles/${p}/medicamentos/${id}`).set(auth(a))).status).toBe(404);
  });

  it('o nome e as notas ficam cifrados na base de dados', async () => {
    const a = await conta();
    const p = await perfil(a);
    const id = await medicamento(a, p, 'Insulina Lantus');
    const { rows } = await db.query('select nome_cifrado, notas_cifradas from medicamentos where id = $1', [id]);
    const bruto = Buffer.concat([rows[0].nome_cifrado, rows[0].notas_cifradas]).toString('utf8');
    expect(bruto).not.toContain('Insulina');
    expect(bruto).not.toContain('refeição');
  });

  it('valida o pedido', async () => {
    const a = await conta();
    const p = await perfil(a);
    for (const corpo of [{}, { nome: '  ' }, { nome: 'x'.repeat(101) }, { nome: 'ok', notas: 'x'.repeat(1001) }]) {
      expect((await request(app).post(`/profiles/${p}/medicamentos`).set(auth(a)).send(corpo)).status).toBe(400);
    }
    expect((await request(app).get(`/profiles/${p}/medicamentos/nao-e-uuid`).set(auth(a))).status).toBe(404);
  });
});

describe('Receitas e tomas', () => {
  it('criar uma receita de horas fixas gera as tomas na janela de 90 dias', async () => {
    const a = await conta();
    const p = await perfil(a);
    const m = await medicamento(a, p);
    const id = await receita(a, p, m);
    const { rows } = await db.query('select count(*)::int n, min(agendada_utc) mn, max(agendada_utc) mx from tomas where receita_id = $1', [id]);
    expect(rows[0].n).toBeGreaterThanOrEqual(170); // 2 por dia durante ~90 dias
    expect(rows[0].n).toBeLessThanOrEqual(184);
    expect(rows[0].mx.getTime() - Date.now()).toBeLessThanOrEqual(91 * 86_400_000);
  });

  it('devolve o horário como foi dado (horas ordenadas) e cifra a dose', async () => {
    const a = await conta();
    const p = await perfil(a);
    const m = await medicamento(a, p);
    const id = await receita(a, p, m, { dose: '2 gotas no olho esquerdo' });
    const r = await request(app).get(`/profiles/${p}/receitas/${id}`).set(auth(a));
    expect(r.body.receita).toMatchObject({
      dose: '2 gotas no olho esquerdo', horario: { tipo: 'horas_fixas', horasLocais: ['08:00', '20:00'] }, timezone: 'Europe/Lisbon', ativa: true,
    });
    const { rows } = await db.query('select dose_cifrada from receitas where id = $1', [id]);
    expect(rows[0].dose_cifrada.toString('utf8')).not.toContain('gotas');
  });

  it('receita por intervalo', async () => {
    const a = await conta();
    const p = await perfil(a);
    const m = await medicamento(a, p);
    const id = await receita(a, p, m, { horario: { tipo: 'intervalo', intervaloHoras: 8 } });
    const { rows } = await db.query('select count(*)::int n from tomas where receita_id = $1', [id]);
    expect(rows[0].n).toBeGreaterThanOrEqual(268); // 3 por dia
    const r = await request(app).get(`/profiles/${p}/receitas/${id}`).set(auth(a));
    expect(r.body.receita.horario).toEqual({ tipo: 'intervalo', intervaloHoras: 8 });
  });

  it('um tratamento com fim só gera tomas até ao fim', async () => {
    const a = await conta();
    const p = await perfil(a);
    const m = await medicamento(a, p);
    const ini = new Date(Date.now() + 3_600_000);
    const fim = new Date(ini.getTime() + 3 * 86_400_000);
    const id = await receita(a, p, m, { inicio: ini.toISOString(), fim: fim.toISOString() });
    const { rows } = await db.query('select count(*)::int n, max(agendada_utc) mx from tomas where receita_id = $1', [id]);
    expect(rows[0].n).toBeLessThanOrEqual(8);
    expect(rows[0].mx.getTime()).toBeLessThan(fim.getTime());
  });

  it.each([
    ['horário sem horas', { horario: { tipo: 'horas_fixas', horasLocais: [] } }],
    ['hora inválida', { horario: { tipo: 'horas_fixas', horasLocais: ['25:00'] } }],
    ['horas repetidas', { horario: { tipo: 'horas_fixas', horasLocais: ['08:00', '08:00'] } }],
    ['intervalo zero', { horario: { tipo: 'intervalo', intervaloHoras: 0 } }],
    ['intervalo gigante', { horario: { tipo: 'intervalo', intervaloHoras: 1000 } }],
    ['tipo desconhecido', { horario: { tipo: 'quando_apetecer' } }],
    ['fim antes do início', { fim: new Date(Date.now() - 86_400_000).toISOString() }],
    ['fuso desconhecido', { timezone: 'Marte/Olympus' }],
    ['dose vazia', { dose: ' ' }],
    ['data sem fuso', { inicio: '2030-01-01T10:00:00' }],
    ['unidades negativas', { unidadesIniciais: -1 }],
  ])('rejeita %s', async (_nome, extra) => {
    const a = await conta();
    const p = await perfil(a);
    const m = await medicamento(a, p);
    const r = await request(app).post(`/profiles/${p}/receitas`).set(auth(a)).send(corpoReceita(m, extra));
    expect(r.status).toBe(400);
    expect(r.body.erro).toBe('pedido_invalido');
    expect((await db.query('select 1 from receitas where profile_id = $1', [p])).rowCount).toBe(0);
  });

  it('editar o horário refaz só as tomas futuras pendentes e preserva as já registadas', async () => {
    const a = await conta();
    const p = await perfil(a);
    const m = await medicamento(a, p);
    const id = await receita(a, p, m);
    const { rows: [primeira] } = await db.query('select id from tomas where receita_id = $1 order by agendada_utc limit 1', [id]);
    await db.query("update tomas set estado = 'tomada', tomada_em_utc = now(), origem = 'cuidador' where id = $1", [primeira.id]);
    const r = await request(app).patch(`/profiles/${p}/receitas/${id}`).set(auth(a)).send({ horario: { tipo: 'horas_fixas', horasLocais: ['09:00'] } });
    expect(r.status).toBe(200);
    expect(r.body.receita.horario.horasLocais).toEqual(['09:00']);
    const { rows } = await db.query('select count(*)::int n from tomas where receita_id = $1', [id]);
    expect(rows[0].n).toBeGreaterThanOrEqual(88); // ~1 por dia (+ a tomada que ficou)
    expect(rows[0].n).toBeLessThanOrEqual(93);
    const mantida = await db.query("select estado from tomas where id = $1", [primeira.id]);
    expect(mantida.rows[0].estado).toBe('tomada');
  });

  it('desativar a receita para de gerar e remove as tomas futuras pendentes', async () => {
    const a = await conta();
    const p = await perfil(a);
    const m = await medicamento(a, p);
    const id = await receita(a, p, m);
    const r = await request(app).patch(`/profiles/${p}/receitas/${id}`).set(auth(a)).send({ ativa: false });
    expect(r.body.receita.ativa).toBe(false);
    expect((await db.query('select 1 from tomas where receita_id = $1', [id])).rowCount).toBe(0);
  });

  it('apagar o medicamento apaga as receitas e as tomas', async () => {
    const a = await conta();
    const p = await perfil(a);
    const m = await medicamento(a, p);
    const id = await receita(a, p, m);
    await request(app).delete(`/profiles/${p}/medicamentos/${m}`).set(auth(a));
    expect((await db.query('select 1 from receitas where id = $1', [id])).rowCount).toBe(0);
    expect((await db.query('select 1 from tomas where receita_id = $1', [id])).rowCount).toBe(0);
  });

  it('lista as tomas num intervalo, com limite de 32 dias', async () => {
    const a = await conta();
    const p = await perfil(a);
    const m = await medicamento(a, p);
    await receita(a, p, m, { horario: { tipo: 'intervalo', intervaloHoras: 12 } });
    const de = new Date().toISOString();
    const ate = new Date(Date.now() + 2 * 86_400_000).toISOString();
    const r = await request(app).get(`/profiles/${p}/tomas`).query({ de, ate }).set(auth(a));
    expect(r.status).toBe(200);
    expect(r.body.tomas.length).toBeGreaterThanOrEqual(3);
    expect(r.body.tomas[0]).toMatchObject({ estado: 'pendente' });
    const demais = new Date(Date.now() + 40 * 86_400_000).toISOString();
    expect((await request(app).get(`/profiles/${p}/tomas`).query({ de, ate: demais }).set(auth(a))).status).toBe(400);
    expect((await request(app).get(`/profiles/${p}/tomas`).set(auth(a))).status).toBe(400);
  });
});

describe('IDOR na medicação', () => {
  async function cenario() {
    const a = await conta('Ana');
    const b = await conta('Bruno');
    const pa = await perfil(a);
    const pb = await perfil(b);
    const ma = await medicamento(a, pa);
    const ra = await receita(a, pa, ma);
    return { a, b, pa, pb, ma, ra };
  }

  it('B não vê, altera nem apaga nada do perfil de A', async () => {
    const { b, pa, ma, ra } = await cenario();
    const pedidos = [
      request(app).get(`/profiles/${pa}/medicamentos`).set(auth(b)),
      request(app).get(`/profiles/${pa}/medicamentos/${ma}`).set(auth(b)),
      request(app).patch(`/profiles/${pa}/medicamentos/${ma}`).set(auth(b)).send({ nome: 'X' }),
      request(app).delete(`/profiles/${pa}/medicamentos/${ma}`).set(auth(b)),
      request(app).post(`/profiles/${pa}/medicamentos`).set(auth(b)).send({ nome: 'Intruso' }),
      request(app).get(`/profiles/${pa}/receitas`).set(auth(b)),
      request(app).get(`/profiles/${pa}/receitas/${ra}`).set(auth(b)),
      request(app).patch(`/profiles/${pa}/receitas/${ra}`).set(auth(b)).send({ ativa: false }),
      request(app).delete(`/profiles/${pa}/receitas/${ra}`).set(auth(b)),
      request(app).post(`/profiles/${pa}/receitas`).set(auth(b)).send(corpoReceita(ma)),
      request(app).get(`/profiles/${pa}/tomas`).query({ de: new Date().toISOString(), ate: new Date(Date.now() + 86_400_000).toISOString() }).set(auth(b)),
    ];
    for (const r of await Promise.all(pedidos)) {
      expect(r.status).toBe(404);
      expect(r.body).toEqual({ erro: 'perfil_nao_encontrado' });
    }
    expect((await db.query('select nome_cifrado from medicamentos where profile_id = $1', [pa])).rowCount).toBe(1);
    expect((await db.query('select ativa from receitas where id = $1', [ra])).rows[0].ativa).toBe(true);
  });

  it('B, com o seu próprio perfil, não alcança medicamentos ou receitas de A por id', async () => {
    const { b, pb, ma, ra } = await cenario();
    for (const url of [`/profiles/${pb}/medicamentos/${ma}`, `/profiles/${pb}/receitas/${ra}`]) {
      expect((await request(app).get(url).set(auth(b))).status, url).toBe(404);
    }
    expect((await request(app).patch(`/profiles/${pb}/medicamentos/${ma}`).set(auth(b)).send({ nome: 'X' })).status).toBe(404);
    expect((await request(app).patch(`/profiles/${pb}/receitas/${ra}`).set(auth(b)).send({ ativa: false })).status).toBe(404);
    expect((await request(app).delete(`/profiles/${pb}/medicamentos/${ma}`).set(auth(b))).status).toBe(404);
    expect((await request(app).delete(`/profiles/${pb}/receitas/${ra}`).set(auth(b))).status).toBe(404);
    const intacto = await db.query('select ativa from receitas where id = $1', [ra]);
    expect(intacto.rows[0].ativa).toBe(true);
  });

  it('B não consegue criar uma receita no seu perfil apontando para um medicamento de A', async () => {
    const { b, pb, ma } = await cenario();
    const r = await request(app).post(`/profiles/${pb}/receitas`).set(auth(b)).send(corpoReceita(ma));
    expect(r.status).toBe(404);
    expect((await db.query('select 1 from receitas where profile_id = $1', [pb])).rowCount).toBe(0);
    expect((await db.query('select 1 from tomas where profile_id = $1', [pb])).rowCount).toBe(0);
  });

  it('as listas de cada perfil só trazem os seus dados', async () => {
    const { a, b, pa, pb } = await cenario();
    await medicamento(b, pb, 'Do Bruno');
    const la = await request(app).get(`/profiles/${pa}/medicamentos`).set(auth(a));
    const lb = await request(app).get(`/profiles/${pb}/medicamentos`).set(auth(b));
    expect(la.body.medicamentos.map((m: { nome: string }) => m.nome)).toEqual(['Metformina 850 mg']);
    expect(lb.body.medicamentos.map((m: { nome: string }) => m.nome)).toEqual(['Do Bruno']);
  });

  it('as chaves de perfis diferentes não se misturam', async () => {
    const { pa, pb, ma } = await cenario();
    const { rows } = await db.query('select chave_cifrada from profiles where id = any($1::uuid[])', [[pa, pb]]);
    expect(rows[0].chave_cifrada.equals(rows[1].chave_cifrada)).toBe(false);
    expect(ma).toBeTruthy();
  });

  it('o acesso de leitura de um caregiver chega à medicação; exige autenticação sempre', async () => {
    const { a, b, pa, ma } = await cenario();
    expect((await request(app).get(`/profiles/${pa}/medicamentos`)).status).toBe(401);
    await db.query(
      "insert into profile_access (user_id, profile_id, papel, autorizacao_declarada_em, autorizacao_versao) values ($1, $2, 'caregiver', now(), '2026-11')",
      [b.id, pa],
    );
    const r = await request(app).get(`/profiles/${pa}/medicamentos/${ma}`).set(auth(b));
    expect(r.status).toBe(200);
    expect(r.body.medicamento.nome).toBe('Metformina 850 mg');
    expect(a.id).toBeTruthy();
  });
});

describe('Rotas com X-Profile-Id (mapa do plano: /receitas, /medicamentos)', () => {
  const h = (c: Conta, p: string) => ({ ...auth(c), 'X-Profile-Id': p });

  it('criar, ler, editar e apagar com o perfil no cabeçalho', async () => {
    const a = await conta();
    const p = await perfil(a);
    const m = await request(app).post('/medicamentos').set(h(a, p)).send({ nome: 'Ramipril 5 mg' });
    expect(m.status).toBe(201);
    const r = await request(app).post('/receitas').set(h(a, p)).send(corpoReceita(m.body.medicamento.id));
    expect(r.status, JSON.stringify(r.body)).toBe(201);
    expect((await request(app).get('/receitas').set(h(a, p))).body.receitas).toHaveLength(1);
    const alt = await request(app).patch(`/receitas/${r.body.receita.id}`).set(h(a, p)).send({ dose: '2 comprimidos' });
    expect(alt.body.receita.dose).toBe('2 comprimidos');
    // são as mesmas receitas que em /profiles/:id/receitas
    expect((await request(app).get(`/profiles/${p}/receitas/${r.body.receita.id}`).set(auth(a))).body.receita.dose).toBe('2 comprimidos');
    expect((await request(app).delete(`/receitas/${r.body.receita.id}`).set(h(a, p))).status).toBe(204);
  });

  it('exige autenticação e um perfil a que se tenha acesso (IDOR)', async () => {
    const a = await conta('Ana');
    const b = await conta('Bruno');
    const pa = await perfil(a);
    const ma = await medicamento(a, pa);
    const ra = await receita(a, pa, ma);
    expect((await request(app).get('/receitas')).status).toBe(401);
    expect((await request(app).get('/receitas').set(auth(a))).status).toBe(404); // sem X-Profile-Id
    for (const r of await Promise.all([
      request(app).get('/receitas').set(h(b, pa)),
      request(app).get(`/receitas/${ra}`).set(h(b, pa)),
      request(app).patch(`/receitas/${ra}`).set(h(b, pa)).send({ ativa: false }),
      request(app).delete(`/medicamentos/${ma}`).set(h(b, pa)),
      request(app).post('/medicamentos').set(h(b, pa)).send({ nome: 'Intruso' }),
    ])) {
      expect(r.status).toBe(404);
      expect(r.body).toEqual({ erro: 'perfil_nao_encontrado' });
    }
    expect((await db.query('select ativa from receitas where id = $1', [ra])).rows[0].ativa).toBe(true);
  });

  it('o telemóvel da pessoa não alcança estas rotas', async () => {
    const a = await conta();
    const p = await perfil(a);
    const cod = await request(app).post(`/profiles/${p}/pairing-codes`).set(auth(a));
    const red = await request(app).post('/pairing/redeem').send({ codigo: cod.body.codigo });
    const dev = { Authorization: `Bearer ${red.body.token}`, 'X-Profile-Id': p };
    expect((await request(app).get('/receitas').set(dev)).status).toBe(403);
    expect((await request(app).get('/medicamentos').set(dev)).status).toBe(403);
    expect((await request(app).post('/medicamentos').set(dev).send({ nome: 'X' })).status).toBe(403);
  });
});

describe('Geração assíncrona das tomas (ecrã de carregamento)', () => {
  const esperarConcluida = async (c: Conta, p: string, id: string) => {
    for (let i = 0; i < 200; i++) {
      const g = await request(app).get(`/profiles/${p}/receitas/${id}/geracao`).set(auth(c));
      if (g.body.estado !== 'a_gerar') return g.body;
      await new Promise((r) => setTimeout(r, 25));
    }
    throw new Error('a geração nunca terminou');
  };

  it('responde 202 de imediato e as tomas aparecem em segundo plano, com os passos a seguir', async () => {
    const a = await conta();
    const p = await perfil(a);
    const m = await medicamento(a, p);
    const r = await request(app).post(`/profiles/${p}/receitas?assincrono=true`).set(auth(a)).send(corpoReceita(m));
    expect(r.status).toBe(202);
    expect(['a_gerar', 'concluida']).toContain(r.body.receita.geracao.estado);
    const final = await esperarConcluida(a, p, r.body.receita.id);
    expect(final.estado).toBe('concluida');
    expect(final.tomasGeradas).toBeGreaterThanOrEqual(170);
    expect(final.passos).toEqual([{ id: 'gerar_tomas', estado: 'feito' }, { id: 'sincronizar', estado: 'feito' }]);
    const n = await db.query('select count(*)::int n from tomas where receita_id = $1', [r.body.receita.id]);
    expect(n.rows[0].n).toBe(final.tomasGeradas);
    expect((await request(app).get(`/profiles/${p}/receitas/${r.body.receita.id}`).set(auth(a))).body.receita.geracao.estado).toBe('concluida');
  });

  it('o modo normal continua síncrono e já traz o número de tomas', async () => {
    const a = await conta();
    const p = await perfil(a);
    const m = await medicamento(a, p);
    const r = await request(app).post(`/profiles/${p}/receitas`).set(auth(a)).send(corpoReceita(m));
    expect(r.status).toBe(201);
    expect(r.body.receita.geracao.estado).toBe('concluida');
    expect(r.body.receita.geracao.tomasGeradas).toBeGreaterThanOrEqual(170);
  });

  it('uma geração que ficou a meio (servidor reiniciou) é retomada, sem duplicar tomas', async () => {
    const { retomarGeracoes } = await import('../src/medicacao/servico.js');
    const a = await conta();
    const p = await perfil(a);
    const m = await medicamento(a, p);
    const id = await receita(a, p, m);
    await db.query('delete from tomas where receita_id = $1', [id]);
    await db.query("update receitas set geracao_estado = 'a_gerar', geracao_tomas = 0, criado_em = now() - interval '5 minutes' where id = $1", [id]);
    expect((await retomarGeracoes(db)).valueOf()).toBeGreaterThanOrEqual(1);
    const g = await request(app).get(`/profiles/${p}/receitas/${id}/geracao`).set(auth(a));
    expect(g.body.estado).toBe('concluida');
    expect(g.body.tomasGeradas).toBeGreaterThanOrEqual(170);
    await retomarGeracoes(db);
    const n = await db.query('select count(*)::int n from tomas where receita_id = $1', [id]);
    expect(n.rows[0].n).toBe(g.body.tomasGeradas);
  });

  it('o estado da geração respeita os perfis (IDOR)', async () => {
    const a = await conta('Ana');
    const b = await conta('Bruno');
    const pa = await perfil(a);
    const pb = await perfil(b);
    const ma = await medicamento(a, pa);
    const ra = await receita(a, pa, ma);
    expect((await request(app).get(`/profiles/${pa}/receitas/${ra}/geracao`).set(auth(b))).status).toBe(404);
    expect((await request(app).get(`/profiles/${pb}/receitas/${ra}/geracao`).set(auth(b))).status).toBe(404);
    expect((await request(app).get(`/receitas/${ra}/geracao`).set({ ...auth(b), 'X-Profile-Id': pb })).status).toBe(404);
  });
});

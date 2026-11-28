import request from 'supertest';
import { afterAll, afterEach, describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { createPool } from '../src/db.js';
import type { Eventos } from '../src/eventos.js';
import type { Horario } from '../src/medicacao/servico.js';
import { calcularStock, unidadesPorToma } from '../src/medicacao/stock.js';

const config = loadConfig();
const db = createPool(config.DATABASE_URL);
const chamadas: { profileId: string; tomaId: string; porUserId: string | null }[] = [];
let ganchoFalha = false;
const eventos: Eventos = {
  async tomaRegistada(profileId, tomaId, porUserId) {
    chamadas.push({ profileId, tomaId, porUserId });
    if (ganchoFalha) throw new Error('push em baixo');
  },
  async sincronizar() {},
  async lembrar() {
    return 'sem_telemovel';
  },
};
const app = createApp(db, config, { auth: { limitarPorIp: false }, dispositivos: { limitarCodigos: false }, eventos });
const utilizadores: string[] = [];
const perfis: string[] = [];

afterEach(async () => {
  chamadas.length = 0;
  ganchoFalha = false;
  if (perfis.length) await db.query('delete from profiles where id = any($1::uuid[])', [perfis.splice(0)]);
  if (utilizadores.length) await db.query('delete from users where id = any($1::uuid[])', [utilizadores.splice(0)]);
});
afterAll(async () => {
  await db.end();
});

let n = 0;
type Conta = { id: string; token: string };
async function conta(nome = 'Ana'): Promise<Conta> {
  const email = `toma.${Date.now()}.${++n}@exemplo.pt`;
  const r = await request(app).post('/auth/registo').send({ email, senha: 'uma-senha-segura-123', nome, aceitaTermos: true });
  utilizadores.push(r.body.utilizador.id);
  return { id: r.body.utilizador.id, token: r.body.accessToken };
}
const auth = (c: { token: string }, p?: string) => ({ Authorization: `Bearer ${c.token}`, ...(p ? { 'X-Profile-Id': p } : {}) });
async function perfil(c: Conta, nome = 'Avó Rosa'): Promise<string> {
  const r = await request(app).post('/profiles').set(auth(c)).send({ pseudonimo: nome, autorizacaoDeclarada: true });
  perfis.push(r.body.perfil.id);
  return r.body.perfil.id;
}
async function ligar(c: Conta, p: string) {
  const cod = await request(app).post(`/profiles/${p}/pairing-codes`).set(auth(c));
  const r = await request(app).post('/pairing/redeem').send({ codigo: cod.body.codigo });
  return { Authorization: `Bearer ${r.body.token}` };
}

/** Cria medicamento + receita (1 toma por dia) e devolve a primeira toma, posta a `deslocamentoMs` de agora. */
async function umaToma(c: Conta, p: string, deslocamentoMs: number, extra: object = {}) {
  const m = await request(app).post(`/profiles/${p}/medicamentos`).set(auth(c)).send({ nome: 'Metformina 850 mg' });
  const r = await request(app).post(`/profiles/${p}/receitas`).set(auth(c)).send({
    medicamentoId: m.body.medicamento.id,
    dose: '1 comprimido',
    horario: { tipo: 'intervalo', intervaloHoras: 24 },
    inicio: new Date(Date.now() + 86_400_000).toISOString(),
    ...extra,
  });
  expect(r.status, JSON.stringify(r.body)).toBe(201);
  const { rows } = await db.query('select id from tomas where receita_id = $1 order by agendada_utc limit 1', [r.body.receita.id]);
  await db.query('update tomas set agendada_utc = $2 where id = $1', [rows[0].id, new Date(Date.now() + deslocamentoMs)]);
  return { tomaId: rows[0].id as string, receitaId: r.body.receita.id as string };
}
const MIN = 60_000;

describe('Cálculo de stock', () => {
  it('lê as unidades por toma da dose', () => {
    expect(unidadesPorToma('1 comprimido')).toBe(1);
    expect(unidadesPorToma('2 comprimidos')).toBe(2);
    expect(unidadesPorToma('1/2 comprimido')).toBe(0.5);
    expect(unidadesPorToma('0,5 comprimido')).toBe(0.5);
    expect(unidadesPorToma('gotas no olho')).toBe(1);
    expect(unidadesPorToma('0 nada')).toBe(1);
  });
  it('calcula unidades e dias que restam', () => {
    const fixas: Horario = { tipo: 'horas_fixas', horasLocais: ['08:00', '20:00'] };
    expect(calcularStock('1 comprimido', fixas, 30, 2)).toEqual({ unidadesRestantes: 28, diasRestantes: 14, emFalta: null });
    expect(calcularStock('2 comprimidos', { tipo: 'intervalo', intervaloHoras: 8 }, 60, 3)).toEqual({ unidadesRestantes: 54, diasRestantes: 9, emFalta: null });
    expect(calcularStock('1 comprimido', fixas, 2, 10)).toEqual({ unidadesRestantes: 0, diasRestantes: 0, emFalta: null });
    expect(calcularStock('1 comprimido', fixas, null, 0)).toBeNull();
  });
});

describe('Hoje: listar tomas', () => {
  it('traz o medicamento e a dose, e deriva "atrasada" só depois da tolerância', async () => {
    const a = await conta();
    const p = await perfil(a);
    const recente = await umaToma(a, p, -10 * MIN);
    const r1 = await request(app).get('/tomas').set(auth(a, p));
    const t1 = r1.body.tomas.find((t: { id: string }) => t.id === recente.tomaId);
    expect(t1).toMatchObject({ medicamento: { nome: 'Metformina 850 mg' }, dose: '1 comprimido', estado: 'pendente', atrasada: false });
    await db.query("update tomas set agendada_utc = now() - interval '20 minutes' where id = $1", [recente.tomaId]);
    const r2 = await request(app).get('/tomas').set(auth(a, p));
    expect(r2.body.tomas.find((t: { id: string }) => t.id === recente.tomaId).atrasada).toBe(true);
  });

  it('o telemóvel da pessoa vê as tomas do seu perfil, sem enviar cabeçalho', async () => {
    const a = await conta();
    const p = await perfil(a);
    const t = await umaToma(a, p, 30 * MIN);
    const dev = await ligar(a, p);
    const r = await request(app).get('/tomas').set(dev);
    expect(r.status).toBe(200);
    expect(r.body.tomas.map((x: { id: string }) => x.id)).toContain(t.tomaId);
  });

  it('exige autenticação e um perfil válido', async () => {
    const a = await conta();
    const p = await perfil(a);
    expect((await request(app).get('/tomas')).status).toBe(401);
    expect((await request(app).get('/tomas').set(auth(a))).status).toBe(404); // sem X-Profile-Id
    expect((await request(app).get('/tomas').set(auth(a, p)).query({ de: 'ontem' })).status).toBe(400);
  });
});

describe('Sincronização delta (since)', () => {
  it('devolve só o que mudou e as tomas removidas pela regeneração', async () => {
    const a = await conta();
    const p = await perfil(a);
    const t = await umaToma(a, p, 2 * 3_600_000);
    const inicial = await request(app).get('/tomas').set(auth(a, p));
    const desde = inicial.body.servidorAgora as string;
    await new Promise((r) => setTimeout(r, 30));

    const nada = await request(app).get('/tomas').query({ since: desde }).set(auth(a, p));
    expect(nada.body.tomas).toEqual([]);
    expect(nada.body.removidas).toEqual([]);

    await request(app).post(`/tomas/${t.tomaId}/registo`).set(auth(a, p)).send({});
    const mudou = await request(app).get('/tomas').query({ since: desde }).set(auth(a, p));
    expect(mudou.body.tomas.map((x: { id: string }) => x.id)).toEqual([t.tomaId]);
    expect(mudou.body.tomas[0].estado).toBe('tomada');

    // editar a receita refaz as tomas futuras pendentes: as antigas aparecem em "removidas"
    const futura = await db.query("select id from tomas where receita_id = $1 and estado = 'pendente' limit 1", [t.receitaId]);
    expect(futura.rowCount).toBeGreaterThan(0);
    await request(app).patch(`/profiles/${p}/receitas/${t.receitaId}`).set(auth(a)).send({ horario: { tipo: 'intervalo', intervaloHoras: 12 } });
    const apos = await request(app).get('/tomas').query({ since: mudou.body.proximoDesde }).set(auth(a, p));
    expect(apos.body.removidas).toContain(futura.rows[0].id);
    expect(new Date(apos.body.proximoDesde).getTime()).toBeLessThan(new Date(apos.body.servidorAgora).getTime());
  });
});

describe('Marcar como tomada', () => {
  it('o cuidador marca: fica "Marcada pela Ana" e o telemóvel da pessoa vê isso', async () => {
    const a = await conta('Ana');
    const p = await perfil(a);
    const t = await umaToma(a, p, -5 * MIN);
    const dev = await ligar(a, p);
    const r = await request(app).post(`/tomas/${t.tomaId}/registo`).set(auth(a, p)).send({});
    expect(r.status).toBe(200);
    expect(r.body).toEqual({ estado: 'tomada', repetido: false });
    const vista = await request(app).get(`/tomas/${t.tomaId}`).set(dev);
    expect(vista.body.toma).toMatchObject({ estado: 'tomada', origem: 'cuidador', registadaPor: 'Ana' });
    expect(vista.body.toma.tomadaEmUtc).toBeTruthy();
    const { rows } = await db.query('select registada_por_user_id from tomas where id = $1', [t.tomaId]);
    expect(rows[0].registada_por_user_id).toBe(a.id);
  });

  it('a pessoa marca no telemóvel dela: origem "dispositivo", sem nome de cuidador', async () => {
    const a = await conta('Ana');
    const p = await perfil(a);
    const t = await umaToma(a, p, -5 * MIN);
    const dev = await ligar(a, p);
    expect((await request(app).post(`/tomas/${t.tomaId}/registo`).set(dev).send({})).status).toBe(200);
    const vista = await request(app).get(`/tomas/${t.tomaId}`).set(auth(a, p));
    expect(vista.body.toma).toMatchObject({ estado: 'tomada', origem: 'dispositivo', registadaPor: null });
    const audit = await db.query("select user_id from audit_logs where entidade_id = $1 and acao = 'toma.registar'", [t.tomaId]);
    expect(audit.rows).toHaveLength(1);
    expect(audit.rows[0].user_id).toBeNull();
  });

  it('aceita a hora real escolhida ("há 1 hora") e recusa horas impossíveis', async () => {
    const a = await conta();
    const p = await perfil(a);
    const t = await umaToma(a, p, -30 * MIN);
    const futura = new Date(Date.now() + 30 * MIN).toISOString();
    const r1 = await request(app).post(`/tomas/${t.tomaId}/registo`).set(auth(a, p)).send({ tomadaEmUtc: futura });
    expect(r1.status).toBe(400);
    expect(r1.body).toEqual({ erro: 'hora_invalida' });
    const longe = new Date(Date.now() - 3 * 86_400_000).toISOString();
    expect((await request(app).post(`/tomas/${t.tomaId}/registo`).set(auth(a, p)).send({ tomadaEmUtc: longe })).body).toEqual({ erro: 'hora_invalida' });
    const umaHora = new Date(Date.now() - 3_600_000);
    expect((await request(app).post(`/tomas/${t.tomaId}/registo`).set(auth(a, p)).send({ tomadaEmUtc: umaHora.toISOString() })).status).toBe(200);
    const { rows } = await db.query('select tomada_em_utc from tomas where id = $1', [t.tomaId]);
    expect(Math.abs(rows[0].tomada_em_utc.getTime() - umaHora.getTime())).toBeLessThan(1000);
    expect((await request(app).post(`/tomas/${t.tomaId}/registo`).set(auth(a, p)).send({ tomadaEmUtc: 'ontem' })).status).toBe(400);
  });

  it('idempotência: reenviar o mesmo pedido não duplica nem altera nada', async () => {
    const a = await conta();
    const p = await perfil(a);
    const t = await umaToma(a, p, -5 * MIN);
    const chave = 'chave-offline-0001';
    const r1 = await request(app).post(`/tomas/${t.tomaId}/registo`).set(auth(a, p)).send({ idempotencyKey: chave });
    const antes = await db.query('select tomada_em_utc, registado_em from tomas where id = $1', [t.tomaId]);
    const r2 = await request(app).post(`/tomas/${t.tomaId}/registo`).set(auth(a, p)).set('Idempotency-Key', chave).send({});
    const r3 = await request(app).post(`/tomas/${t.tomaId}/registo`).set(auth(a, p)).send({ idempotencyKey: chave });
    expect(r1.body.repetido).toBe(false);
    expect(r2.status).toBe(200);
    expect(r2.body).toEqual({ estado: 'tomada', repetido: true });
    expect(r3.body.repetido).toBe(true);
    const depois = await db.query('select tomada_em_utc, registado_em from tomas where id = $1', [t.tomaId]);
    expect(depois.rows[0]).toEqual(antes.rows[0]);
    expect((await db.query("select count(*)::int n from audit_logs where entidade_id = $1 and acao = 'toma.registar'", [t.tomaId])).rows[0].n).toBe(1);
    expect(chamadas).toHaveLength(1); // o push de "toma feita" não repete
  });

  it('a mesma chave noutra toma é independente; outra chave numa toma já registada dá 409', async () => {
    const a = await conta();
    const p = await perfil(a);
    const t1 = await umaToma(a, p, -5 * MIN);
    const t2 = await umaToma(a, p, -4 * MIN);
    const chave = 'mesma-chave-1234';
    expect((await request(app).post(`/tomas/${t1.tomaId}/registo`).set(auth(a, p)).send({ idempotencyKey: chave })).status).toBe(200);
    expect((await request(app).post(`/tomas/${t2.tomaId}/registo`).set(auth(a, p)).send({ idempotencyKey: chave })).body.repetido).toBe(false);
    const dupla = await request(app).post(`/tomas/${t1.tomaId}/registo`).set(auth(a, p)).send({ idempotencyKey: 'outra-chave-9999' });
    expect(dupla.status).toBe(409);
    expect(dupla.body).toEqual({ erro: 'toma_ja_registada' });
  });

  it('conflito da fila offline: ganha o evento mais recente', async () => {
    const a = await conta();
    const p = await perfil(a);
    const t = await umaToma(a, p, -2 * 3_600_000);
    const cedo = new Date(Date.now() - 40 * MIN).toISOString();
    const tarde = new Date(Date.now() - 10 * MIN).toISOString();
    expect((await request(app).post(`/tomas/${t.tomaId}/saltar`).set(auth(a, p)).send({ eventoEm: tarde })).body.estado).toBe('saltada');
    // um evento mais antigo não ganha
    expect((await request(app).post(`/tomas/${t.tomaId}/registo`).set(auth(a, p)).send({ eventoEm: cedo })).status).toBe(409);
    expect((await db.query('select estado from tomas where id = $1', [t.tomaId])).rows[0].estado).toBe('saltada');
    // um evento mais recente ganha
    const agora = new Date().toISOString();
    expect((await request(app).post(`/tomas/${t.tomaId}/registo`).set(auth(a, p)).send({ eventoEm: agora })).body.estado).toBe('tomada');
  });

  it('o relógio do telemóvel adiantado não cria registos no futuro', async () => {
    const a = await conta();
    const p = await perfil(a);
    const t = await umaToma(a, p, -5 * MIN);
    const futuro = new Date(Date.now() + 3_600_000).toISOString();
    expect((await request(app).post(`/tomas/${t.tomaId}/registo`).set(auth(a, p)).send({ eventoEm: futuro })).status).toBe(200);
    const { rows } = await db.query('select registado_em from tomas where id = $1', [t.tomaId]);
    expect(rows[0].registado_em.getTime()).toBeLessThanOrEqual(Date.now());
  });

  it('o gancho de "toma feita" corre com o cuidador certo, e uma falha dele não falha o pedido', async () => {
    const a = await conta();
    const p = await perfil(a);
    const t1 = await umaToma(a, p, -5 * MIN);
    await request(app).post(`/tomas/${t1.tomaId}/registo`).set(auth(a, p)).send({});
    expect(chamadas).toEqual([{ profileId: p, tomaId: t1.tomaId, porUserId: a.id }]);
    const t2 = await umaToma(a, p, -4 * MIN);
    ganchoFalha = true;
    expect((await request(app).post(`/tomas/${t2.tomaId}/registo`).set(auth(a, p)).send({})).status).toBe(200);
  });
});

describe('Saltar e desfazer', () => {
  it('saltar guarda quem saltou e não tem hora de toma', async () => {
    const a = await conta('Ana');
    const p = await perfil(a);
    const t = await umaToma(a, p, -5 * MIN);
    expect((await request(app).post(`/tomas/${t.tomaId}/saltar`).set(auth(a, p)).send({})).body.estado).toBe('saltada');
    const v = await request(app).get(`/tomas/${t.tomaId}`).set(auth(a, p));
    expect(v.body.toma).toMatchObject({ estado: 'saltada', tomadaEmUtc: null, registadaPor: 'Ana' });
  });

  it('desfazer dentro de 1 minuto volta a pendente, fica na auditoria e permite registar de novo', async () => {
    const a = await conta();
    const p = await perfil(a);
    const t = await umaToma(a, p, -5 * MIN);
    await request(app).post(`/tomas/${t.tomaId}/registo`).set(auth(a, p)).send({ idempotencyKey: 'primeira-chave-1' });
    const r = await request(app).post(`/tomas/${t.tomaId}/desfazer`).set(auth(a, p));
    expect(r.body).toEqual({ estado: 'pendente' });
    const { rows } = await db.query('select estado, tomada_em_utc, origem, registada_por_user_id, registado_em from tomas where id = $1', [t.tomaId]);
    expect(rows[0]).toEqual({ estado: 'pendente', tomada_em_utc: null, origem: null, registada_por_user_id: null, registado_em: null });
    expect((await db.query("select count(*)::int n from audit_logs where entidade_id = $1 and acao = 'toma.desfazer'", [t.tomaId])).rows[0].n).toBe(1);
    // reenviar o pedido de desfazer não faz mal; e a toma pode ser registada outra vez
    expect((await request(app).post(`/tomas/${t.tomaId}/desfazer`).set(auth(a, p))).body).toEqual({ estado: 'pendente' });
    expect((await request(app).post(`/tomas/${t.tomaId}/registo`).set(auth(a, p)).send({ idempotencyKey: 'primeira-chave-1' })).body.repetido).toBe(false);
  });

  it('depois de 1 minuto já não se desfaz', async () => {
    const a = await conta();
    const p = await perfil(a);
    const t = await umaToma(a, p, -5 * MIN);
    await request(app).post(`/tomas/${t.tomaId}/registo`).set(auth(a, p)).send({});
    await db.query("update tomas set registado_em = now() - interval '61 seconds' where id = $1", [t.tomaId]);
    const r = await request(app).post(`/tomas/${t.tomaId}/desfazer`).set(auth(a, p));
    expect(r.status).toBe(409);
    expect(r.body).toEqual({ erro: 'desfazer_expirado' });
    expect((await db.query('select estado from tomas where id = $1', [t.tomaId])).rows[0].estado).toBe('tomada');
  });

  it('o telemóvel da pessoa também pode saltar e desfazer', async () => {
    const a = await conta();
    const p = await perfil(a);
    const t = await umaToma(a, p, -5 * MIN);
    const dev = await ligar(a, p);
    expect((await request(app).post(`/tomas/${t.tomaId}/saltar`).set(dev).send({})).status).toBe(200);
    expect((await request(app).post(`/tomas/${t.tomaId}/desfazer`).set(dev)).body.estado).toBe('pendente');
  });
});

describe('IDOR nas tomas', () => {
  async function cenario() {
    const a = await conta('Ana');
    const b = await conta('Bruno');
    const pa = await perfil(a);
    const pb = await perfil(b, 'Do Bruno');
    const ta = await umaToma(a, pa, -5 * MIN);
    const devA = await ligar(a, pa);
    return { a, b, pa, pb, ta, devA };
  }

  it('B não vê, regista, salta nem desfaz tomas do perfil de A', async () => {
    const { b, pa, pb, ta } = await cenario();
    const pedidos = [
      request(app).get('/tomas').set(auth(b, pa)),
      request(app).get(`/tomas/${ta.tomaId}`).set(auth(b, pa)),
      request(app).post(`/tomas/${ta.tomaId}/registo`).set(auth(b, pa)).send({}),
      request(app).post(`/tomas/${ta.tomaId}/saltar`).set(auth(b, pa)).send({}),
      request(app).post(`/tomas/${ta.tomaId}/desfazer`).set(auth(b, pa)),
      // com o seu próprio perfil, mas o id da toma de A
      request(app).get(`/tomas/${ta.tomaId}`).set(auth(b, pb)),
      request(app).post(`/tomas/${ta.tomaId}/registo`).set(auth(b, pb)).send({}),
      request(app).post(`/tomas/${ta.tomaId}/saltar`).set(auth(b, pb)).send({}),
      request(app).post(`/tomas/${ta.tomaId}/desfazer`).set(auth(b, pb)),
    ];
    for (const r of await Promise.all(pedidos)) expect(r.status).toBe(404);
    expect((await db.query('select estado from tomas where id = $1', [ta.tomaId])).rows[0].estado).toBe('pendente');
  });

  it('o telemóvel de A não toca em tomas de outro perfil, mesmo com X-Profile-Id', async () => {
    const { b, pb, devA } = await cenario();
    const tb = await umaToma(b, pb, -5 * MIN);
    const r1 = await request(app).post(`/tomas/${tb.tomaId}/registo`).set(devA).set('X-Profile-Id', pb).send({});
    const r2 = await request(app).get(`/tomas/${tb.tomaId}`).set(devA).set('X-Profile-Id', pb);
    expect(r1.status).toBe(404);
    expect(r2.status).toBe(404);
    const lista = await request(app).get('/tomas').set(devA).set('X-Profile-Id', pb);
    expect(lista.body.tomas.map((t: { id: string }) => t.id)).not.toContain(tb.tomaId);
    expect((await db.query('select estado from tomas where id = $1', [tb.tomaId])).rows[0].estado).toBe('pendente');
  });

  it('um dispositivo revogado deixa de poder registar', async () => {
    const { a, pa, ta, devA } = await cenario();
    const lista = await request(app).get(`/profiles/${pa}/devices`).set(auth(a));
    await request(app).delete(`/profiles/${pa}/devices/${lista.body.dispositivos[0].id}`).set(auth(a));
    expect((await request(app).post(`/tomas/${ta.tomaId}/registo`).set(devA).send({})).status).toBe(401);
  });

  it('um id que não é UUID responde 404', async () => {
    const { a, pa } = await cenario();
    expect((await request(app).get('/tomas/nao-e-uuid').set(auth(a, pa))).status).toBe(404);
    expect((await request(app).post('/tomas/1%27%20or%201=1/registo').set(auth(a, pa)).send({})).status).toBe(404);
  });
});

describe('Detalhe da toma e stock da receita', () => {
  it('o detalhe traz o histórico dos 7 dias anteriores da mesma receita', async () => {
    const a = await conta();
    const p = await perfil(a);
    const t = await umaToma(a, p, 0);
    for (const dias of [1, 3, 6, 9]) {
      await db.query("insert into tomas (receita_id, profile_id, agendada_utc, estado) values ($1, $2, now() - ($3 || ' days')::interval, 'falhada')", [t.receitaId, p, String(dias)]);
    }
    const r = await request(app).get(`/tomas/${t.tomaId}`).set(auth(a, p));
    expect(r.body.historico7dias).toHaveLength(3); // 1, 3 e 6 dias antes; 9 fica de fora
    expect(r.body.historico7dias.every((h: { estado: string }) => h.estado === 'falhada')).toBe(true);
  });

  it('a receita mostra as unidades e os dias que restam, e atualiza ao marcar tomas', async () => {
    const a = await conta();
    const p = await perfil(a);
    const t = await umaToma(a, p, -5 * MIN, { unidadesIniciais: 30, horario: { tipo: 'horas_fixas', horasLocais: ['08:00', '20:00'] } });
    const antes = await request(app).get(`/profiles/${p}/receitas/${t.receitaId}`).set(auth(a));
    expect(antes.body.receita.stock).toMatchObject({ unidadesRestantes: 30, diasRestantes: 15 });
    await request(app).post(`/tomas/${t.tomaId}/registo`).set(auth(a, p)).send({});
    const depois = await request(app).get(`/profiles/${p}/receitas/${t.receitaId}`).set(auth(a));
    expect(depois.body.receita.stock).toMatchObject({ unidadesRestantes: 29, diasRestantes: 14 });
  });
});

describe('Preferências de alertas', () => {
  it('devolve as predefinições e guarda alterações por cuidador e perfil', async () => {
    const a = await conta();
    const p = await perfil(a);
    const g = await request(app).get('/alert-prefs').set(auth(a, p));
    expect(g.body.prefs).toEqual({ tomaNaoConfirmada: true, esperaMin: 15, tomaFeita: false, receitaAcabar: true, diasAntes: 4 });
    const novo = { tomaNaoConfirmada: false, esperaMin: 30, tomaFeita: true, receitaAcabar: true, diasAntes: 7 };
    expect((await request(app).put('/alert-prefs').set(auth(a, p)).send(novo)).body.prefs).toEqual(novo);
    expect((await request(app).get('/alert-prefs').set(auth(a, p))).body.prefs).toEqual(novo);
  });

  it('valida os valores', async () => {
    const a = await conta();
    const p = await perfil(a);
    const base = { tomaNaoConfirmada: true, esperaMin: 15, tomaFeita: false, receitaAcabar: true, diasAntes: 4 };
    for (const mau of [{ esperaMin: 0 }, { esperaMin: 181 }, { diasAntes: 0 }, { diasAntes: 31 }, { tomaFeita: 'sim' }]) {
      expect((await request(app).put('/alert-prefs').set(auth(a, p)).send({ ...base, ...mau })).status).toBe(400);
    }
  });

  it('um cuidador sem acesso ao perfil não lê nem altera; o telemóvel da pessoa não tem acesso', async () => {
    const a = await conta('Ana');
    const b = await conta('Bruno');
    const p = await perfil(a);
    const dev = await ligar(a, p);
    const corpo = { tomaNaoConfirmada: false, esperaMin: 10, tomaFeita: false, receitaAcabar: false, diasAntes: 1 };
    expect((await request(app).get('/alert-prefs').set(auth(b, p))).status).toBe(404);
    expect((await request(app).put('/alert-prefs').set(auth(b, p)).send(corpo)).status).toBe(404);
    expect((await request(app).get('/alert-prefs').set(dev)).status).toBe(403);
    expect((await request(app).put('/alert-prefs').set(dev).send(corpo)).status).toBe(403);
    expect((await db.query('select toma_nao_confirmada from alert_prefs where profile_id = $1', [p])).rows[0].toma_nao_confirmada).toBe(true);
  });
});

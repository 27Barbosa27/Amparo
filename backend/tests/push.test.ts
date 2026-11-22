import { generateKeyPairSync } from 'node:crypto';
import request from 'supertest';
import { afterAll, afterEach, describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { lerChave } from '../src/auth/cifra.js';
import { loadConfig } from '../src/config.js';
import { createPool } from '../src/db.js';
import { comTrinco, iniciarAgendador } from '../src/jobs/agendador.js';
import { alertarNaoConfirmadas, alertarReceitasAAcabar, limpar, marcarFalhadas, trabalhosDoMinuto, type Contexto } from '../src/jobs/trabalhos.js';
import { corpoMensagem, criarEnviadorFcm, type EnviadorPush, type MensagemPush } from '../src/push/enviador.js';
import { criarEventosPush } from '../src/push/servico.js';

const config = loadConfig();
const db = createPool(config.DATABASE_URL);

class Falso implements EnviadorPush {
  enviadas: { tokens: string[]; m: MensagemPush }[] = [];
  invalidos = new Set<string>();
  async enviar(tokens: string[], m: MensagemPush) {
    this.enviadas.push({ tokens: [...tokens], m });
    return { invalidos: tokens.filter((t) => this.invalidos.has(t)) };
  }
  para(perfil: string, subtipo?: string) {
    return this.enviadas.filter((e) => e.m.perfil === perfil && (!subtipo || e.m.subtipo === subtipo));
  }
}

const chaveCampos = lerChave(config.EMAIL_ENC_KEY);
const chaveMestra = lerChave(config.PROFILE_MASTER_KEY);
let falso = new Falso();
let app = createApp(db, config, { auth: { limitarPorIp: false }, dispositivos: { limitarCodigos: false }, eventos: criarEventosPush(db, falso, chaveCampos) });
const ctx = (): Contexto => ({ db, enviador: falso, chaveCampos, chaveMestra });

const utilizadores: string[] = [];
const perfis: string[] = [];
afterEach(async () => {
  falso = new Falso();
  app = createApp(db, config, { auth: { limitarPorIp: false }, dispositivos: { limitarCodigos: false }, eventos: criarEventosPush(db, falso, chaveCampos) });
  if (perfis.length) await db.query('delete from profiles where id = any($1::uuid[])', [perfis.splice(0)]);
  if (utilizadores.length) await db.query('delete from users where id = any($1::uuid[])', [utilizadores.splice(0)]);
});
afterAll(async () => {
  await db.end();
});

let n = 0;
type Conta = { id: string; token: string };
async function conta(nome = 'Ana'): Promise<Conta> {
  const email = `push.${Date.now()}.${++n}@exemplo.pt`;
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
  return { Authorization: `Bearer ${r.body.token}`, id: r.body.dispositivoId as string };
}
const tokenFcm = (rotulo: string) => `fcm-${rotulo}-${Date.now()}-${++n}-`.padEnd(40, 'x');
async function registarPush(h: Record<string, string>, token: string, plataforma = 'android') {
  const r = await request(app).put('/push-tokens').set(h).send({ plataforma, token });
  expect(r.status).toBe(204);
}
async function umaToma(c: Conta, p: string, deslocamentoMs: number, extra: object = {}) {
  const m = await request(app).post(`/profiles/${p}/medicamentos`).set(auth(c)).send({ nome: 'Metformina' });
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
const esperar = async (cond: () => boolean, ms = 2000) => {
  const fim = Date.now() + ms;
  while (!cond() && Date.now() < fim) await new Promise((r) => setTimeout(r, 20));
};

describe('Enviador FCM', () => {
  const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048, privateKeyEncoding: { type: 'pkcs8', format: 'pem' }, publicKeyEncoding: { type: 'spki', format: 'pem' } });
  const conta_ = { project_id: 'amparo-teste', client_email: 'fcm@amparo-teste.iam.gserviceaccount.com', private_key: privateKey };

  function httpFalso(respostaEnvio: (token: string) => { status: number; corpo?: unknown }) {
    const chamadas: { url: string; init?: RequestInit }[] = [];
    const f = (async (url: string | URL | Request, init?: RequestInit) => {
      const u = String(url);
      chamadas.push({ url: u, init });
      if (u.startsWith('https://oauth2.googleapis.com/token')) return new Response(JSON.stringify({ access_token: 'acesso-1', expires_in: 3600 }), { status: 200 });
      const token = JSON.parse(String(init?.body)).message.token as string;
      const r = respostaEnvio(token);
      return new Response(JSON.stringify(r.corpo ?? {}), { status: r.status });
    }) as typeof fetch;
    return { f, chamadas };
  }

  it('obtém um token de acesso uma só vez e envia a cada telemóvel', async () => {
    const { f, chamadas } = httpFalso(() => ({ status: 200 }));
    const e = criarEnviadorFcm(conta_, f);
    await e.enviar(['t1'.padEnd(30, 'x'), 't2'.padEnd(30, 'x')], { tipo: 'sync', perfil: 'p1' });
    await e.enviar(['t3'.padEnd(30, 'x')], { tipo: 'sync', perfil: 'p1' });
    expect(chamadas.filter((c) => c.url.includes('oauth2')).length).toBe(1);
    const envios = chamadas.filter((c) => c.url.includes('/messages:send'));
    expect(envios).toHaveLength(3);
    expect(envios[0]!.url).toBe('https://fcm.googleapis.com/v1/projects/amparo-teste/messages:send');
    expect((envios[0]!.init!.headers as Record<string, string>).authorization).toBe('Bearer acesso-1');
  });

  it('devolve como inválidos os tokens que o FCM já não conhece e continua com os outros', async () => {
    const mau = 'mau'.padEnd(30, 'x');
    const { f } = httpFalso((t) => (t === mau ? { status: 404, corpo: { error: { status: 'NOT_FOUND', details: [{ errorCode: 'UNREGISTERED' }] } } } : { status: 200 }));
    const r = await criarEnviadorFcm(conta_, f).enviar([mau, 'bom'.padEnd(30, 'x')], { tipo: 'alerta', perfil: 'p1' });
    expect(r.invalidos).toEqual([mau]);
  });

  it('o que vai pela Google tem só tipo e identificadores opacos, com texto genérico', () => {
    const c = corpoMensagem('tok', { tipo: 'alerta', perfil: '11111111-1111-4111-8111-111111111111', subtipo: 'toma_nao_confirmada' });
    expect(Object.keys(c.message.data).sort()).toEqual(['perfil', 'subtipo', 'tipo']);
    const texto = JSON.stringify(c);
    for (const proibido of ['Metformina', 'comprimido', 'Rosa', 'dose', 'medicamento']) expect(texto).not.toContain(proibido);
    expect(JSON.stringify(corpoMensagem('tok', { tipo: 'sync', perfil: 'p' }))).not.toContain('notification');
  });
});

describe('Tokens FCM', () => {
  it('guarda o hash e o token cifrado, e permite removê-lo', async () => {
    const a = await conta();
    const token = tokenFcm('a');
    await registarPush(auth(a), token);
    const { rows } = await db.query('select fcm_token_hash, fcm_token_cifrado, plataforma, revogado_em from push_tokens where user_id = $1', [a.id]);
    expect(rows).toHaveLength(1);
    expect(rows[0].fcm_token_hash).toHaveLength(32);
    expect(rows[0].fcm_token_cifrado.toString('utf8')).not.toContain(token);
    expect(rows[0].plataforma).toBe('android');
    expect((await request(app).delete('/push-tokens').set(auth(a)).send({ token })).status).toBe(204);
    expect((await db.query('select revogado_em from push_tokens where user_id = $1', [a.id])).rows[0].revogado_em).not.toBeNull();
    await registarPush(auth(a), token, 'ios'); // registar outra vez reativa
    const r2 = await db.query('select revogado_em, plataforma from push_tokens where user_id = $1', [a.id]);
    expect(r2.rows[0]).toEqual({ revogado_em: null, plataforma: 'ios' });
  });

  it('ninguém remove os tokens de outro', async () => {
    const a = await conta('Ana');
    const b = await conta('Bruno');
    const token = tokenFcm('a');
    await registarPush(auth(a), token);
    await request(app).delete('/push-tokens').set(auth(b)).send({ token });
    expect((await db.query('select revogado_em from push_tokens where user_id = $1', [a.id])).rows[0].revogado_em).toBeNull();
  });

  it('valida o pedido e exige autenticação', async () => {
    const a = await conta();
    expect((await request(app).put('/push-tokens').send({ plataforma: 'android', token: tokenFcm('x') })).status).toBe(401);
    expect((await request(app).put('/push-tokens').set(auth(a)).send({ plataforma: 'windows', token: tokenFcm('x') })).status).toBe(400);
    expect((await request(app).put('/push-tokens').set(auth(a)).send({ plataforma: 'ios', token: 'curto' })).status).toBe(400);
  });

  it('o telemóvel da pessoa também regista o seu; revogar o dispositivo revoga o token', async () => {
    const a = await conta();
    const p = await perfil(a);
    const d = await ligar(a, p);
    await registarPush(d, tokenFcm('d'));
    expect((await db.query('select 1 from push_tokens where device_id = $1 and revogado_em is null', [d.id])).rowCount).toBe(1);
    await request(app).delete(`/profiles/${p}/devices/${d.id}`).set(auth(a));
    expect((await db.query('select 1 from push_tokens where device_id = $1 and revogado_em is null', [d.id])).rowCount).toBe(0);
  });
});

describe('Eventos: toma feita e sincronização', () => {
  async function cenario() {
    const a = await conta('Ana');
    const b = await conta('Bruno');
    const p = await perfil(a);
    await db.query("insert into profile_access (user_id, profile_id, papel, autorizacao_declarada_em, autorizacao_versao) values ($1, $2, 'caregiver', now(), '2026-11')", [b.id, p]);
    const ta = tokenFcm('ana');
    const tb = tokenFcm('bruno');
    await registarPush(auth(a), ta);
    await registarPush(auth(b), tb);
    return { a, b, p, ta, tb };
  }
  const prefs = (c: Conta, p: string, o: object) =>
    request(app).put('/alert-prefs').set(auth(c, p)).send({ tomaNaoConfirmada: true, esperaMin: 15, tomaFeita: false, receitaAcabar: true, diasAntes: 4, ...o });

  it('avisa de "toma feita" quem o quer, exceto quem a marcou, e só uma vez', async () => {
    const { a, b, p, ta, tb } = await cenario();
    // o Bruno nem tem a preferência; a Ana tem
    await prefs(a, p, { tomaFeita: true });
    await prefs(b, p, { tomaFeita: false });
    const t = await umaToma(a, p, -5 * MIN);
    // marcada pelo Bruno → avisa a Ana
    await request(app).post(`/tomas/${t.tomaId}/registo`).set(auth(b, p)).send({});
    expect(falso.para(p, 'toma_feita')).toEqual([{ tokens: [ta], m: { tipo: 'alerta', perfil: p, subtipo: 'toma_feita' } }]);
    // marcada outra vez pelo mesmo evento: sem repetição
    await db.query("update tomas set estado = 'pendente', tomada_em_utc = null, registado_em = null where id = $1", [t.tomaId]);
    await request(app).post(`/tomas/${t.tomaId}/registo`).set(auth(b, p)).send({});
    expect(falso.para(p, 'toma_feita')).toHaveLength(1);
    expect(tb).toBeTruthy();
  });

  it('quando é a própria pessoa a marcar, avisa todos os cuidadores que o querem', async () => {
    const { a, b, p, ta, tb } = await cenario();
    await prefs(a, p, { tomaFeita: true });
    await prefs(b, p, { tomaFeita: true });
    const t = await umaToma(a, p, -5 * MIN);
    const d = await ligar(a, p);
    await request(app).post(`/tomas/${t.tomaId}/registo`).set(d).send({});
    const enviadas = falso.para(p, 'toma_feita').flatMap((e) => e.tokens).sort();
    expect(enviadas).toEqual([ta, tb].sort());
  });

  it('uma edição do cuidador faz o telemóvel da pessoa sincronizar (e só esse)', async () => {
    const { a, p, ta } = await cenario();
    const d = await ligar(a, p);
    const td = tokenFcm('pessoa');
    await registarPush(d, td);
    const m = await request(app).post(`/profiles/${p}/medicamentos`).set(auth(a)).send({ nome: 'X' });
    expect(m.status).toBe(201);
    await esperar(() => falso.para(p, undefined).some((e) => e.m.tipo === 'sync'));
    const sync = falso.para(p).filter((e) => e.m.tipo === 'sync');
    expect(sync).toEqual([{ tokens: [td], m: { tipo: 'sync', perfil: p } }]);
    expect(sync[0]!.tokens).not.toContain(ta);
  });

  it('o registo de uma toma pelo cuidador também faz o telemóvel da pessoa sincronizar', async () => {
    const { a, p } = await cenario();
    const d = await ligar(a, p);
    const td = tokenFcm('pessoa');
    await registarPush(d, td);
    const t = await umaToma(a, p, -5 * MIN);
    falso.enviadas.length = 0;
    await request(app).post(`/tomas/${t.tomaId}/registo`).set(auth(a, p)).send({});
    expect(falso.para(p).filter((e) => e.m.tipo === 'sync').length).toBeGreaterThanOrEqual(1);
    // se foi a própria pessoa a marcar, não há sincronização para o telemóvel dela
    falso.enviadas.length = 0;
    const t2 = await umaToma(a, p, -4 * MIN);
    falso.enviadas.length = 0;
    await request(app).post(`/tomas/${t2.tomaId}/registo`).set(d).send({});
    await new Promise((r) => setTimeout(r, 100));
    expect(falso.para(p).filter((e) => e.m.tipo === 'sync')).toEqual([]);
  });

  it('os tokens que o FCM rejeita ficam revogados', async () => {
    const { a, p, ta } = await cenario();
    await prefs(a, p, { tomaFeita: true });
    const c = await conta('Carla');
    await db.query("insert into profile_access (user_id, profile_id, papel, autorizacao_declarada_em, autorizacao_versao) values ($1, $2, 'caregiver', now(), '2026-11')", [c.id, p]);
    falso.invalidos.add(ta);
    const t = await umaToma(a, p, -5 * MIN);
    await request(app).post(`/tomas/${t.tomaId}/registo`).set(auth(c, p)).send({});
    expect((await db.query('select revogado_em from push_tokens where user_id = $1', [a.id])).rows[0].revogado_em).not.toBeNull();
  });
});

describe('Trabalhos', () => {
  async function comPrefs(extra: object = {}, espera = 15) {
    const a = await conta('Ana');
    const p = await perfil(a);
    const ta = tokenFcm('ana');
    await registarPush(auth(a), ta);
    await request(app).put('/alert-prefs').set(auth(a, p)).send({ tomaNaoConfirmada: true, esperaMin: espera, tomaFeita: false, receitaAcabar: true, diasAntes: 4, ...extra });
    return { a, p, ta };
  }

  it('toma não confirmada: avisa depois da espera, uma só vez, e só o cuidador desse perfil', async () => {
    const { a, p, ta } = await comPrefs();
    const outro = await conta('Outro');
    const po = await perfil(outro, 'Outra pessoa');
    await registarPush(auth(outro), tokenFcm('outro'));
    await umaToma(a, p, -10 * MIN); // ainda dentro da espera
    const t = await umaToma(a, p, -20 * MIN);
    await alertarNaoConfirmadas(ctx(), new Date());
    expect(falso.para(p, 'toma_nao_confirmada')).toEqual([{ tokens: [ta], m: { tipo: 'alerta', perfil: p, subtipo: 'toma_nao_confirmada' } }]);
    expect(falso.para(po)).toEqual([]);
    await alertarNaoConfirmadas(ctx(), new Date());
    expect(falso.para(p, 'toma_nao_confirmada')).toHaveLength(1);
    // dez minutos depois, a toma que faltava também passa a ser avisada
    await alertarNaoConfirmadas(ctx(), new Date(Date.now() + 6 * MIN));
    expect(falso.para(p, 'toma_nao_confirmada')).toHaveLength(2);
    expect(t.tomaId).toBeTruthy();
  });

  it('respeita a espera escolhida (30 min) e o interruptor', async () => {
    const { a, p } = await comPrefs({}, 30);
    await umaToma(a, p, -20 * MIN);
    await alertarNaoConfirmadas(ctx(), new Date());
    expect(falso.para(p)).toEqual([]);
    await alertarNaoConfirmadas(ctx(), new Date(Date.now() + 11 * MIN));
    expect(falso.para(p)).toHaveLength(1);

    const x = await comPrefs({ tomaNaoConfirmada: false });
    await umaToma(x.a, x.p, -40 * MIN);
    await alertarNaoConfirmadas(ctx(), new Date());
    expect(falso.para(x.p)).toEqual([]);
  });

  it('não avisa tomas já registadas, nem antigas demais, nem quem perdeu o acesso', async () => {
    const { a, p } = await comPrefs();
    const feita = await umaToma(a, p, -30 * MIN);
    await request(app).post(`/tomas/${feita.tomaId}/registo`).set(auth(a, p)).send({});
    await umaToma(a, p, -3 * 3_600_000); // fora da janela: o servidor esteve parado
    await alertarNaoConfirmadas(ctx(), new Date());
    expect(falso.para(p)).toEqual([]);

    const y = await comPrefs();
    await umaToma(y.a, y.p, -30 * MIN);
    await db.query('update profile_access set revogado_em = now() where user_id = $1', [y.a.id]);
    await alertarNaoConfirmadas(ctx(), new Date());
    expect(falso.para(y.p)).toEqual([]);
  });

  it('marca como falhada a toma que passou da janela e deixa o resto', async () => {
    const { a, p } = await comPrefs();
    const velha = await umaToma(a, p, -3 * 3_600_000);
    const recente = await umaToma(a, p, -1 * 3_600_000);
    const feita = await umaToma(a, p, -5 * 3_600_000);
    await db.query("update tomas set estado = 'tomada', tomada_em_utc = now() where id = $1", [feita.tomaId]);
    expect(await marcarFalhadas(db, new Date())).toBeGreaterThanOrEqual(1);
    const estado = async (id: string) => (await db.query('select estado from tomas where id = $1', [id])).rows[0].estado;
    expect(await estado(velha.tomaId)).toBe('falhada');
    expect(await estado(recente.tomaId)).toBe('pendente');
    expect(await estado(feita.tomaId)).toBe('tomada');
  });

  it('receita a acabar: avisa quando os dias que restam chegam ao limite, no máximo uma vez por dia', async () => {
    const { a, p } = await comPrefs();
    await umaToma(a, p, 60 * MIN, { unidadesIniciais: 3 }); // 3 dias de stock, limite de 4
    const longa = await umaToma(a, p, 60 * MIN, { unidadesIniciais: 100 });
    const agora = new Date();
    await alertarReceitasAAcabar(ctx(), agora);
    expect(falso.para(p, 'receita_a_acabar')).toHaveLength(1);
    await alertarReceitasAAcabar(ctx(), agora);
    expect(falso.para(p, 'receita_a_acabar')).toHaveLength(1);
    await alertarReceitasAAcabar(ctx(), new Date(agora.getTime() + 86_400_000)); // no dia seguinte volta a avisar
    expect(falso.para(p, 'receita_a_acabar')).toHaveLength(2);
    expect(longa.receitaId).toBeTruthy();
  });

  it('receita a acabar: respeita o interruptor e as receitas desativadas', async () => {
    const x = await comPrefs({ receitaAcabar: false });
    await umaToma(x.a, x.p, 60 * MIN, { unidadesIniciais: 1 });
    await alertarReceitasAAcabar(ctx(), new Date());
    expect(falso.para(x.p)).toEqual([]);

    const y = await comPrefs();
    const r = await umaToma(y.a, y.p, 60 * MIN, { unidadesIniciais: 1 });
    await request(app).patch(`/profiles/${y.p}/receitas/${r.receitaId}`).set(auth(y.a)).send({ ativa: false });
    await alertarReceitasAAcabar(ctx(), new Date());
    expect(falso.para(y.p)).toEqual([]);
  });

  it('a limpeza apaga o que expirou e nunca toca na auditoria', async () => {
    const { a, p } = await comPrefs();
    await db.query("insert into pairing_codes (profile_id, criado_por_user_id, codigo_hash, expira_em) values ($1, $2, $3, now() - interval '3 days')", [p, a.id, Buffer.from('x'.repeat(32))]);
    await db.query("insert into tomas_removidas (toma_id, profile_id, removida_em) values (gen_random_uuid(), $1, now() - interval '40 days')", [p]);
    await db.query("insert into alertas_enviados (user_id, tipo, chave, enviado_em) values ($1, 'x', 'velho', now() - interval '40 days')", [a.id]);
    const auditoriaAntes = (await db.query('select count(*)::int n from audit_logs where profile_id = $1', [p])).rows[0].n;
    await limpar(db);
    expect((await db.query("select 1 from pairing_codes where profile_id = $1 and expira_em < now() - interval '1 day'", [p])).rowCount).toBe(0);
    expect((await db.query('select 1 from tomas_removidas where profile_id = $1', [p])).rowCount).toBe(0);
    expect((await db.query("select 1 from alertas_enviados where user_id = $1 and chave = 'velho'", [a.id])).rowCount).toBe(0);
    expect((await db.query('select count(*)::int n from audit_logs where profile_id = $1', [p])).rows[0].n).toBe(auditoriaAntes);
  });

  it('os trabalhos do minuto avisam e marcam falhadas; o trinco impede duas instâncias ao mesmo tempo', async () => {
    const { a, p } = await comPrefs();
    await umaToma(a, p, -20 * MIN);
    const velha = await umaToma(a, p, -3 * 3_600_000);
    await trabalhosDoMinuto(ctx());
    expect(falso.para(p, 'toma_nao_confirmada')).toHaveLength(1);
    expect((await db.query('select estado from tomas where id = $1', [velha.tomaId])).rows[0].estado).toBe('falhada');

    let segunda: unknown = 'por correr';
    const primeira = comTrinco(db, 99_001, async () => {
      segunda = await comTrinco(db, 99_001, async () => 'não devia correr');
      return 'primeira';
    });
    expect(await primeira).toBe('primeira');
    expect(segunda).toBeNull();
    expect(await comTrinco(db, 99_001, async () => 'livre')).toBe('livre'); // depois de largado, volta a servir
  });

  it('o agendador corre os trabalhos sozinho e pára quando se manda', async () => {
    const { a, p } = await comPrefs();
    await umaToma(a, p, -20 * MIN);
    const parar = iniciarAgendador(ctx(), { intervaloMinutoMs: 40, intervaloDiarioMs: 3_600_000, atrasoInicialMs: 3_600_000 });
    await esperar(() => falso.para(p, 'toma_nao_confirmada').length > 0, 3000);
    parar();
    expect(falso.para(p, 'toma_nao_confirmada')).toHaveLength(1);
  });
});

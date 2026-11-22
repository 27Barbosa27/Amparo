import { afterAll, afterEach, describe, expect, it } from 'vitest';
import { createPool } from '../src/db.js';
import { gerarTomas, gerarTomasIniciais, manterJanela, regenerarTomasFuturas } from '../src/tomas/servico.js';

const db = createPool(process.env.DATABASE_URL ?? 'postgres://invalido');
const perfis: string[] = [];

afterEach(async () => {
  if (perfis.length) await db.query('delete from profiles where id = any($1::uuid[])', [perfis.splice(0)]);
});
afterAll(async () => {
  await db.end();
});

const DIA = 86_400_000;

/** Cria um perfil, um medicamento e uma receita por intervalo. Os dados sensíveis são só bytes de teste. */
async function criarReceita(opts: { intervaloHoras: number; inicio: Date; fim?: Date | null }) {
  const p = await db.query<{ id: string }>(
    "insert into profiles (pseudonimo, chave_cifrada) values ('Teste', '\\x00') returning id",
  );
  const profileId = p.rows[0]!.id;
  perfis.push(profileId);
  const m = await db.query<{ id: string }>(
    "insert into medicamentos (profile_id, nome_cifrado) values ($1, '\\x00') returning id",
    [profileId],
  );
  const r = await db.query<{ id: string }>(
    `insert into receitas (profile_id, medicamento_id, dose_cifrada, tipo, intervalo_horas, timezone, inicio_utc, fim_utc)
     values ($1, $2, '\\x00', 'intervalo', $3, 'Europe/Lisbon', $4, $5) returning id`,
    [profileId, m.rows[0]!.id, opts.intervaloHoras, opts.inicio, opts.fim ?? null],
  );
  return { profileId, receitaId: r.rows[0]!.id };
}

const contar = async (receitaId: string, filtro = '') =>
  Number((await db.query<{ n: string }>(`select count(*) n from tomas where receita_id = $1 ${filtro}`, [receitaId])).rows[0]!.n);

describe('Geração de tomas na base de dados', () => {
  it('cria as tomas da janela e não duplica ao repetir', async () => {
    const inicio = new Date('2027-01-10T08:00:00Z');
    const { receitaId } = await criarReceita({ intervaloHoras: 8, inicio });
    const ate = new Date(inicio.getTime() + 7 * DIA);

    expect(await gerarTomas(db, receitaId, inicio, ate)).toBe(21);
    expect(await contar(receitaId)).toBe(21);

    // repetir não cria nada
    expect(await gerarTomas(db, receitaId, inicio, ate)).toBe(0);
    expect(await contar(receitaId)).toBe(21);
  });

  it('gera a janela rolante de 90 dias para uma receita nova', async () => {
    const agora = new Date('2027-01-10T08:00:00Z');
    const { receitaId } = await criarReceita({ intervaloHoras: 12, inicio: agora });
    await gerarTomasIniciais(db, receitaId, agora);
    expect(await contar(receitaId)).toBe(180); // 2 por dia × 90 dias
  });

  it('respeita o fim da receita', async () => {
    const inicio = new Date('2027-01-10T08:00:00Z');
    const { receitaId } = await criarReceita({ intervaloHoras: 24, inicio, fim: new Date(inicio.getTime() + 5 * DIA) });
    await gerarTomasIniciais(db, receitaId, inicio);
    expect(await contar(receitaId)).toBe(5);
  });

  it('não gera tomas para uma receita desativada', async () => {
    const inicio = new Date('2027-01-10T08:00:00Z');
    const { receitaId } = await criarReceita({ intervaloHoras: 8, inicio });
    await db.query('update receitas set ativa = false where id = $1', [receitaId]);
    expect(await gerarTomasIniciais(db, receitaId, inicio)).toBe(0);
  });

  it('a manutenção diária completa a janela sem criar tomas no passado', async () => {
    const inicio = new Date('2027-01-10T08:00:00Z');
    const { receitaId } = await criarReceita({ intervaloHoras: 24, inicio });
    await gerarTomas(db, receitaId, inicio, new Date(inicio.getTime() + 10 * DIA)); // só 10 dias gerados

    const agora = new Date(inicio.getTime() + 5 * DIA);
    await manterJanela(db, agora);

    const depois = await db.query<{ min: Date; n: string }>(
      'select min(agendada_utc) min, count(*) n from tomas where receita_id = $1',
      [receitaId],
    );
    expect(depois.rows[0]!.min.toISOString()).toBe(inicio.toISOString()); // as antigas ficam
    // 10 já existentes (dias 0..9) + dias 10..94 até agora+90 dias
    expect(Number(depois.rows[0]!.n)).toBe(95);
    const antes = await contar(receitaId, `and agendada_utc < '${agora.toISOString()}' and agendada_utc >= '${inicio.toISOString()}'`);
    expect(antes).toBe(5); // nada de novo foi criado antes de "agora"
  });
});

describe('Geração de tomas por horas fixas (coluna time[])', () => {
  it('lê as horas da base de dados e respeita a hora local em verão', async () => {
    const p = await db.query<{ id: string }>("insert into profiles (pseudonimo, chave_cifrada) values ('Teste', '\\x00') returning id");
    const profileId = p.rows[0]!.id;
    perfis.push(profileId);
    const m = await db.query<{ id: string }>("insert into medicamentos (profile_id, nome_cifrado) values ($1, '\\x00') returning id", [profileId]);
    const r = await db.query<{ id: string }>(
      `insert into receitas (profile_id, medicamento_id, dose_cifrada, tipo, horas_locais, timezone, inicio_utc)
       values ($1, $2, '\\x00', 'horas_fixas', array['08:00','20:00']::time[], 'Europe/Lisbon', $3) returning id`,
      [profileId, m.rows[0]!.id, new Date('2027-07-10T00:00:00Z')],
    );
    const receitaId = r.rows[0]!.id;
    const criadas = await gerarTomas(db, receitaId, new Date('2027-07-10T00:00:00Z'), new Date('2027-07-13T00:00:00Z'));
    expect(criadas).toBe(6);
    const horas = await db.query<{ h: string }>(
      "select distinct to_char(agendada_utc at time zone 'UTC', 'HH24:MI') h from tomas where receita_id = $1", [receitaId],
    );
    // verão em Lisboa (UTC+1): 08:00 local = 07:00 UTC e 20:00 local = 19:00 UTC
    expect(horas.rows.map((x) => x.h).sort()).toEqual(['07:00', '19:00']);
  });
});

describe('Edição de uma receita', () => {
  it('regenera só as tomas futuras, pendentes e não editadas à mão', async () => {
    const inicio = new Date('2027-01-10T08:00:00Z');
    const agora = new Date('2027-01-12T00:00:00Z');
    const { receitaId } = await criarReceita({ intervaloHoras: 8, inicio });
    await gerarTomas(db, receitaId, inicio, new Date(inicio.getTime() + 10 * DIA));

    // uma toma passada já registada, uma futura editada à mão
    const passada = '2027-01-10T08:00:00Z';
    const futuraManual = '2027-01-13T08:00:00Z';
    await db.query(
      "update tomas set estado='tomada', tomada_em_utc=agendada_utc, origem='cuidador' where receita_id=$1 and agendada_utc=$2",
      [receitaId, passada],
    );
    await db.query('update tomas set editada_manualmente = true where receita_id=$1 and agendada_utc=$2', [receitaId, futuraManual]);

    // a receita passa a "de 12 em 12 horas"
    await db.query('update receitas set intervalo_horas = 12 where id = $1', [receitaId]);
    await regenerarTomasFuturas(db, receitaId, agora);

    // a passada tomada continua lá
    expect(await contar(receitaId, `and agendada_utc = '${passada}' and estado = 'tomada'`)).toBe(1);
    // a futura editada à mão continua lá
    expect(await contar(receitaId, `and agendada_utc = '${futuraManual}' and editada_manualmente`)).toBe(1);
    // as futuras pendentes passam à grelha de 12 em 12 horas (08:00 e 20:00)
    const horas = await db.query<{ h: string }>(
      `select distinct to_char(agendada_utc at time zone 'UTC', 'HH24:MI') h
         from tomas where receita_id = $1 and agendada_utc > $2 and not editada_manualmente`,
      [receitaId, agora],
    );
    expect(horas.rows.map((r) => r.h).sort()).toEqual(['08:00', '20:00']);
    // não ficou nenhuma duplicada
    const dup = await db.query(
      'select agendada_utc from tomas where receita_id = $1 group by agendada_utc having count(*) > 1',
      [receitaId],
    );
    expect(dup.rowCount).toBe(0);
  });

  it('nunca toca em tomas já registadas, mesmo futuras', async () => {
    const inicio = new Date('2027-01-10T08:00:00Z');
    const agora = new Date('2027-01-11T00:00:00Z');
    const { receitaId } = await criarReceita({ intervaloHoras: 8, inicio });
    await gerarTomas(db, receitaId, inicio, new Date(inicio.getTime() + 5 * DIA));
    // a pessoa registou antecipadamente uma toma de amanhã
    await db.query(
      "update tomas set estado='saltada', origem='dispositivo' where receita_id=$1 and agendada_utc='2027-01-11T16:00:00Z'",
      [receitaId],
    );
    await db.query('update receitas set intervalo_horas = 6 where id = $1', [receitaId]);
    await regenerarTomasFuturas(db, receitaId, agora);
    expect(await contar(receitaId, "and agendada_utc='2027-01-11T16:00:00Z' and estado='saltada'")).toBe(1);
  });
});

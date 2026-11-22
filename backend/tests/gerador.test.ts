import { describe, expect, it } from 'vitest';
import { gerarAgendamentos, type AgendaReceita } from '../src/tomas/gerador.js';

const iso = (ds: Date[]) => ds.map((d) => d.toISOString());
const utc = (s: string) => new Date(s);

describe('gerarAgendamentos: por intervalo (tempo absoluto)', () => {
  const base: AgendaReceita = {
    tipo: 'intervalo',
    intervaloHoras: 8,
    inicioUtc: utc('2027-01-10T08:00:00Z'),
    fimUtc: null,
  };

  it('"de 8 em 8 horas" gera 3 tomas por dia a partir do início', () => {
    const r = gerarAgendamentos(base, utc('2027-01-10T00:00:00Z'), utc('2027-01-12T00:00:00Z'));
    expect(iso(r)).toEqual([
      '2027-01-10T08:00:00.000Z',
      '2027-01-10T16:00:00.000Z',
      '2027-01-11T00:00:00.000Z',
      '2027-01-11T08:00:00.000Z',
      '2027-01-11T16:00:00.000Z',
    ]);
  });

  it('nunca gera antes do início, mesmo que a janela comece mais cedo', () => {
    const r = gerarAgendamentos(base, utc('2027-01-01T00:00:00Z'), utc('2027-01-10T09:00:00Z'));
    expect(iso(r)).toEqual(['2027-01-10T08:00:00.000Z']);
  });

  it('respeita o fim da receita (exclusivo)', () => {
    const r = gerarAgendamentos(
      { ...base, fimUtc: utc('2027-01-11T08:00:00Z') },
      utc('2027-01-10T00:00:00Z'),
      utc('2027-02-01T00:00:00Z'),
    );
    expect(iso(r)).toEqual(['2027-01-10T08:00:00.000Z', '2027-01-10T16:00:00.000Z', '2027-01-11T00:00:00.000Z']);
  });

  it('continua a grelha original quando a janela começa a meio', () => {
    const r = gerarAgendamentos(base, utc('2027-01-20T10:00:00Z'), utc('2027-01-21T00:00:00Z'));
    expect(iso(r)).toEqual(['2027-01-20T16:00:00.000Z']);
  });

  it('não é afetado pela mudança de hora: continua a ser de 8 em 8 horas absolutas', () => {
    // Lisboa muda para a hora de verão a 28 mar 2027 (01:00 UTC); o intervalo é absoluto.
    const r = gerarAgendamentos(
      { ...base, inicioUtc: utc('2027-03-27T08:00:00Z') },
      utc('2027-03-27T00:00:00Z'),
      utc('2027-03-29T00:00:00Z'),
    );
    const deltas = r.slice(1).map((d, i) => (d.getTime() - r[i]!.getTime()) / 3_600_000);
    expect(deltas.every((h) => h === 8)).toBe(true);
  });

  it('aceita intervalos fracionários (7,5 horas)', () => {
    const r = gerarAgendamentos(
      { ...base, intervaloHoras: 7.5 },
      utc('2027-01-10T00:00:00Z'),
      utc('2027-01-10T20:00:00Z'),
    );
    expect(iso(r)).toEqual(['2027-01-10T08:00:00.000Z', '2027-01-10T15:30:00.000Z']);
  });

  it('rejeita intervalos inválidos', () => {
    for (const h of [0, -1, Number.NaN, 0.001]) {
      expect(() => gerarAgendamentos({ ...base, intervaloHoras: h }, utc('2027-01-10T00:00:00Z'), utc('2027-01-11T00:00:00Z'))).toThrow();
    }
  });
});

describe('gerarAgendamentos: horas fixas (hora local)', () => {
  type HorasFixas = Extract<AgendaReceita, { tipo: 'horas_fixas' }>;
  const lisboa = (horas: string[], extra: Partial<HorasFixas> = {}): HorasFixas => ({
    tipo: 'horas_fixas',
    horasLocais: horas,
    timezone: 'Europe/Lisbon',
    inicioUtc: utc('2027-01-01T00:00:00Z'),
    fimUtc: null,
    ...extra,
  });

  it('"às 08:00 e às 20:00" em inverno (UTC+0)', () => {
    const r = gerarAgendamentos(lisboa(['08:00', '20:00']), utc('2027-01-10T00:00:00Z'), utc('2027-01-11T00:00:00Z'));
    expect(iso(r)).toEqual(['2027-01-10T08:00:00.000Z', '2027-01-10T20:00:00.000Z']);
  });

  it('em verão (UTC+1) a mesma hora local é uma hora mais cedo em UTC', () => {
    const r = gerarAgendamentos(lisboa(['08:00']), utc('2027-07-10T00:00:00Z'), utc('2027-07-11T00:00:00Z'));
    expect(iso(r)).toEqual(['2027-07-10T07:00:00.000Z']);
  });

  it('a hora local mantém-se à volta da mudança de março (mola para a frente)', () => {
    const r = gerarAgendamentos(lisboa(['08:00']), utc('2027-03-26T00:00:00Z'), utc('2027-03-31T00:00:00Z'));
    expect(iso(r)).toEqual([
      '2027-03-26T08:00:00.000Z', // inverno
      '2027-03-27T08:00:00.000Z', // inverno
      '2027-03-28T07:00:00.000Z', // verão começou nessa madrugada
      '2027-03-29T07:00:00.000Z',
      '2027-03-30T07:00:00.000Z',
    ]);
  });

  it('a hora local mantém-se à volta da mudança de outubro (mola para trás)', () => {
    const r = gerarAgendamentos(lisboa(['08:00']), utc('2027-10-29T00:00:00Z'), utc('2027-11-03T00:00:00Z'));
    expect(iso(r)).toEqual([
      '2027-10-29T07:00:00.000Z',
      '2027-10-30T07:00:00.000Z',
      '2027-10-31T08:00:00.000Z', // já em hora de inverno
      '2027-11-01T08:00:00.000Z',
      '2027-11-02T08:00:00.000Z',
    ]);
  });

  it('hora inexistente (01:30 no dia em que se adianta o relógio) passa para a seguinte válida', () => {
    const r = gerarAgendamentos(lisboa(['01:30']), utc('2027-03-28T00:00:00Z'), utc('2027-03-29T00:00:00Z'));
    expect(iso(r)).toEqual(['2027-03-28T01:30:00.000Z']); // 02:30 locais
  });

  it('hora ambígua (01:30 no dia em que se atrasa o relógio) usa a primeira ocorrência', () => {
    const r = gerarAgendamentos(lisboa(['01:30']), utc('2027-10-30T00:00:00Z'), utc('2027-11-01T12:00:00Z'));
    expect(iso(r)).toEqual([
      '2027-10-30T00:30:00.000Z',
      '2027-10-31T00:30:00.000Z', // primeira 01:30 local (hora de verão), 24 h depois da anterior
      '2027-11-01T01:30:00.000Z',
    ]);
  });

  it('funciona noutro fuso horário (Açores, UTC-1 no inverno)', () => {
    const r = gerarAgendamentos(
      lisboa(['08:00'], { timezone: 'Atlantic/Azores' }),
      utc('2027-01-10T00:00:00Z'),
      utc('2027-01-11T00:00:00Z'),
    );
    expect(iso(r)).toEqual(['2027-01-10T09:00:00.000Z']);
  });

  it('só gera depois do início e antes do fim da receita', () => {
    const r = gerarAgendamentos(
      lisboa(['08:00', '20:00'], { inicioUtc: utc('2027-01-10T12:00:00Z'), fimUtc: utc('2027-01-12T08:00:00Z') }),
      utc('2027-01-01T00:00:00Z'),
      utc('2027-02-01T00:00:00Z'),
    );
    expect(iso(r)).toEqual(['2027-01-10T20:00:00.000Z', '2027-01-11T08:00:00.000Z', '2027-01-11T20:00:00.000Z']);
  });

  it('ignora repetidos e ordena', () => {
    const r = gerarAgendamentos(lisboa(['20:00', '08:00', '08:00']), utc('2027-01-10T00:00:00Z'), utc('2027-01-11T00:00:00Z'));
    expect(iso(r)).toEqual(['2027-01-10T08:00:00.000Z', '2027-01-10T20:00:00.000Z']);
  });

  it('aceita HH:mm:ss como vem da base de dados', () => {
    const r = gerarAgendamentos(lisboa(['08:00:00']), utc('2027-01-10T00:00:00Z'), utc('2027-01-11T00:00:00Z'));
    expect(iso(r)).toEqual(['2027-01-10T08:00:00.000Z']);
  });

  it('rejeita fusos e horas inválidos', () => {
    const de = utc('2027-01-10T00:00:00Z');
    const ate = utc('2027-01-11T00:00:00Z');
    expect(() => gerarAgendamentos(lisboa(['08:00'], { timezone: 'Marte/Olympus' }), de, ate)).toThrow();
    expect(() => gerarAgendamentos(lisboa(['25:00']), de, ate)).toThrow();
    expect(() => gerarAgendamentos(lisboa(['8h']), de, ate)).toThrow();
    expect(() => gerarAgendamentos(lisboa([]), de, ate)).toThrow();
  });
});

describe('gerarAgendamentos: janela', () => {
  it('devolve vazio se a janela não tem sobreposição com a receita', () => {
    const r = gerarAgendamentos(
      { tipo: 'intervalo', intervaloHoras: 8, inicioUtc: utc('2027-06-01T00:00:00Z'), fimUtc: null },
      utc('2027-01-01T00:00:00Z'),
      utc('2027-02-01T00:00:00Z'),
    );
    expect(r).toEqual([]);
  });

  it('protege contra janelas gigantes', () => {
    expect(() =>
      gerarAgendamentos(
        { tipo: 'intervalo', intervaloHoras: 0.02, inicioUtc: utc('2027-01-01T00:00:00Z'), fimUtc: null },
        utc('2027-01-01T00:00:00Z'),
        utc('2037-01-01T00:00:00Z'),
      ),
    ).toThrow(/demasiad/i);
  });
});

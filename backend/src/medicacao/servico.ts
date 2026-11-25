import { cifrar, decifrar, lerChave } from '../auth/cifra.js';
import type { Db } from '../db.js';
import { gerarTomasIniciais, regenerarTomasFuturas } from '../tomas/servico.js';
import { calcularStock, type Stock } from './stock.js';

type Cliente = Pick<Db, 'query'>;

/** Chave de cifra do perfil (guardada cifrada com a chave-mestra). */
export async function chaveDoPerfil(db: Cliente, profileId: string, mestra: Buffer): Promise<Buffer> {
  const { rows } = await db.query<{ chave_cifrada: Buffer }>('select chave_cifrada from profiles where id = $1', [profileId]);
  if (!rows[0]) throw new Error('perfil sem chave');
  return lerChave(decifrar(rows[0].chave_cifrada, mestra));
}

async function auditar(db: Cliente, acao: string, entidade: string, entidadeId: string, userId: string, profileId: string, ip?: string) {
  await db.query('insert into audit_logs (acao, entidade, entidade_id, user_id, profile_id, ip) values ($1, $2, $3, $4, $5, $6)', [
    acao, entidade, entidadeId, userId, profileId, ip ?? null,
  ]);
}

// ---------- Medicamentos ----------

export interface Medicamento {
  id: string;
  nome: string;
  notas: string | null;
  criadoEm: Date;
}

interface LinhaMed {
  id: string;
  nome_cifrado: Buffer;
  notas_cifradas: Buffer | null;
  criado_em: Date;
}

const paraMed = (l: LinhaMed, chave: Buffer): Medicamento => ({
  id: l.id,
  nome: decifrar(l.nome_cifrado, chave),
  notas: l.notas_cifradas ? decifrar(l.notas_cifradas, chave) : null,
  criadoEm: l.criado_em,
});

export async function criarMedicamento(db: Db, mestra: Buffer, userId: string, profileId: string, d: { nome: string; notas?: string }, ip?: string) {
  const chave = await chaveDoPerfil(db, profileId, mestra);
  const { rows } = await db.query<LinhaMed>(
    'insert into medicamentos (profile_id, nome_cifrado, notas_cifradas) values ($1, $2, $3) returning *',
    [profileId, cifrar(d.nome, chave), d.notas ? cifrar(d.notas, chave) : null],
  );
  await auditar(db, 'medicamento.criar', 'medicamento', rows[0]!.id, userId, profileId, ip);
  return paraMed(rows[0]!, chave);
}

export async function listarMedicamentos(db: Db, mestra: Buffer, profileId: string): Promise<Medicamento[]> {
  const chave = await chaveDoPerfil(db, profileId, mestra);
  const { rows } = await db.query<LinhaMed>('select * from medicamentos where profile_id = $1 order by criado_em, id', [profileId]);
  return rows.map((l) => paraMed(l, chave));
}

export async function obterMedicamento(db: Db, mestra: Buffer, profileId: string, id: string): Promise<Medicamento | null> {
  const { rows } = await db.query<LinhaMed>('select * from medicamentos where id = $1 and profile_id = $2', [id, profileId]);
  return rows[0] ? paraMed(rows[0], await chaveDoPerfil(db, profileId, mestra)) : null;
}

export async function alterarMedicamento(
  db: Db, mestra: Buffer, userId: string, profileId: string, id: string, a: { nome?: string; notas?: string | null }, ip?: string,
): Promise<Medicamento | null> {
  const chave = await chaveDoPerfil(db, profileId, mestra);
  const notasDadas = a.notas !== undefined;
  const { rows } = await db.query<LinhaMed>(
    `update medicamentos set
       nome_cifrado = coalesce($3, nome_cifrado),
       notas_cifradas = case when $4 then $5 else notas_cifradas end
     where id = $1 and profile_id = $2 returning *`,
    [id, profileId, a.nome ? cifrar(a.nome, chave) : null, notasDadas, a.notas ? cifrar(a.notas, chave) : null],
  );
  if (!rows[0]) return null;
  await auditar(db, 'medicamento.editar', 'medicamento', id, userId, profileId, ip);
  return paraMed(rows[0], chave);
}

/** Apaga o medicamento e, em cascata, as suas receitas e tomas. */
export async function apagarMedicamento(db: Db, userId: string, profileId: string, id: string, ip?: string): Promise<boolean> {
  const res = await db.query('delete from medicamentos where id = $1 and profile_id = $2', [id, profileId]);
  if (!res.rowCount) return false;
  await auditar(db, 'medicamento.apagar', 'medicamento', id, userId, profileId, ip);
  return true;
}

// ---------- Receitas ----------

export type Horario =
  | { tipo: 'intervalo'; intervaloHoras: number }
  | { tipo: 'horas_fixas'; horasLocais: string[] };

export interface Receita {
  id: string;
  medicamentoId: string;
  dose: string;
  horario: Horario;
  timezone: string;
  inicio: Date;
  fim: Date | null;
  validaAte: string | null;
  unidadesIniciais: number | null;
  stock: Stock | null;
  ativa: boolean;
  /** Estado da geração das tomas (pode correr em segundo plano). */
  geracao: { estado: 'a_gerar' | 'concluida' | 'falhou'; tomasGeradas: number };
}

interface LinhaReceita {
  id: string;
  medicamento_id: string;
  dose_cifrada: Buffer;
  tipo: 'intervalo' | 'horas_fixas';
  intervalo_horas: string | null;
  horas_locais: string[] | null;
  timezone: string;
  inicio_utc: Date;
  fim_utc: Date | null;
  valida_ate: string | null;
  unidades_iniciais: number | null;
  ativa: boolean;
  tomadas: number;
  geracao_estado: 'a_gerar' | 'concluida' | 'falhou';
  geracao_tomas: number;
}

const COLUNAS_RECEITA = `id, medicamento_id, dose_cifrada, tipo, intervalo_horas::text as intervalo_horas,
  horas_locais::text[] as horas_locais, timezone, inicio_utc, fim_utc, valida_ate::text as valida_ate, unidades_iniciais, ativa, geracao_estado, geracao_tomas,
  (select count(*)::int from tomas t where t.receita_id = receitas.id and t.estado = 'tomada') as tomadas`;

const paraReceita = (l: LinhaReceita, chave: Buffer): Receita => {
  const dose = decifrar(l.dose_cifrada, chave);
  const horario: Horario =
    l.tipo === 'intervalo'
      ? { tipo: 'intervalo', intervaloHoras: Number(l.intervalo_horas) }
      : { tipo: 'horas_fixas', horasLocais: (l.horas_locais ?? []).map((h) => h.slice(0, 5)) };
  return {
    id: l.id,
    medicamentoId: l.medicamento_id,
    dose,
    horario,
    timezone: l.timezone,
    inicio: l.inicio_utc,
    fim: l.fim_utc,
    validaAte: l.valida_ate,
    unidadesIniciais: l.unidades_iniciais,
    stock: calcularStock(dose, horario, l.unidades_iniciais, l.tomadas, l.fim_utc),
    ativa: l.ativa,
    geracao: { estado: l.geracao_estado, tomasGeradas: l.geracao_tomas },
  };
};

const colunasHorario = (h: Horario) =>
  h.tipo === 'intervalo' ? [h.tipo, h.intervaloHoras, null] : [h.tipo, null, h.horasLocais];

export interface DadosReceita {
  medicamentoId: string;
  dose: string;
  horario: Horario;
  timezone: string;
  inicio: Date;
  fim: Date | null;
  validaAte: string | null;
  unidadesIniciais: number | null;
}

/** Cria a receita e as suas tomas iniciais, tudo ou nada. Devolve null se o medicamento não for deste perfil. */
/**
 * Gera as tomas de uma receita já criada e regista o resultado. Idempotente (nunca duplica tomas),
 * por isso pode ser repetida se o servidor reiniciar a meio.
 */
export async function gerarEmSegundoPlano(db: Db, receitaId: string): Promise<void> {
  try {
    const n = await gerarTomasIniciais(db, receitaId, new Date());
    await db.query("update receitas set geracao_estado = 'concluida', geracao_tomas = (select count(*)::int from tomas where receita_id = $1) where id = $1", [receitaId]);
    void n;
  } catch (e) {
    console.error('Geração de tomas falhou:', e instanceof Error ? e.message : 'desconhecido');
    await db.query("update receitas set geracao_estado = 'falhou' where id = $1", [receitaId]).catch(() => undefined);
  }
}

/** Receitas que ficaram a meio (o servidor reiniciou): volta a gerar. */
export async function retomarGeracoes(db: Db): Promise<number> {
  const { rows } = await db.query<{ id: string }>(
    "select id from receitas where geracao_estado in ('a_gerar', 'falhou') and criado_em < now() - interval '1 minute' and ativa limit 50",
  );
  for (const r of rows) await gerarEmSegundoPlano(db, r.id);
  return rows.length;
}

export async function estadoGeracao(db: Db, profileId: string, id: string) {
  const { rows } = await db.query<{ geracao_estado: string; geracao_tomas: number }>(
    'select geracao_estado, geracao_tomas from receitas where id = $1 and profile_id = $2',
    [id, profileId],
  );
  const r = rows[0];
  if (!r) return null;
  const fase = r.geracao_estado === 'concluida' ? 'feito' : r.geracao_estado === 'falhou' ? 'falhou' : 'em_curso';
  return {
    estado: r.geracao_estado,
    tomasGeradas: r.geracao_tomas,
    // Os passos do ecrã "Carregamento". "Agendar os alarmes" é do telemóvel e só começa depois deste.
    passos: [
      { id: 'gerar_tomas', estado: fase },
      { id: 'sincronizar', estado: fase === 'feito' ? 'feito' : fase === 'falhou' ? 'falhou' : 'pendente' },
    ],
  };
}

export async function criarReceita(
  db: Db, mestra: Buffer, userId: string, profileId: string, d: DadosReceita, ip?: string,
  opcoes: { assincrono?: boolean; aoGerar?: () => void } = {},
): Promise<Receita | null> {
  const chave = await chaveDoPerfil(db, profileId, mestra);
  const cliente = await db.connect();
  try {
    await cliente.query('begin');
    const med = await cliente.query('select 1 from medicamentos where id = $1 and profile_id = $2', [d.medicamentoId, profileId]);
    if (!med.rowCount) {
      await cliente.query('rollback');
      return null;
    }
    const { rows } = await cliente.query<LinhaReceita>(
      `insert into receitas (profile_id, medicamento_id, dose_cifrada, tipo, intervalo_horas, horas_locais,
                             timezone, inicio_utc, fim_utc, valida_ate, unidades_iniciais)
       values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11) returning ${COLUNAS_RECEITA}`,
      [profileId, d.medicamentoId, cifrar(d.dose, chave), ...colunasHorario(d.horario), d.timezone, d.inicio, d.fim, d.validaAte, d.unidadesIniciais],
    );
    const receita = rows[0]!;
    if (opcoes.assincrono) {
      // Fica "a gerar" e as tomas são criadas em segundo plano; o cliente consulta o estado.
      await cliente.query("update receitas set geracao_estado = 'a_gerar' where id = $1", [receita.id]);
    } else {
      await gerarTomasIniciais(cliente, receita.id, new Date());
      await cliente.query('update receitas set geracao_tomas = (select count(*)::int from tomas where receita_id = $1) where id = $1', [receita.id]);
    }
    await auditar(cliente, 'receita.criar', 'receita', receita.id, userId, profileId, ip);
    await cliente.query('commit');
    if (opcoes.assincrono) {
      setImmediate(() => void gerarEmSegundoPlano(db, receita.id).then(() => opcoes.aoGerar?.()));
      const { rows: atual } = await db.query<LinhaReceita>(`select ${COLUNAS_RECEITA} from receitas where id = $1`, [receita.id]);
      return paraReceita(atual[0]!, chave);
    }
    const { rows: atual } = await db.query<LinhaReceita>(`select ${COLUNAS_RECEITA} from receitas where id = $1`, [receita.id]);
    return paraReceita(atual[0]!, chave);
  } catch (e) {
    await cliente.query('rollback').catch(() => undefined);
    throw e;
  } finally {
    cliente.release();
  }
}

export async function listarReceitas(db: Db, mestra: Buffer, profileId: string): Promise<Receita[]> {
  const chave = await chaveDoPerfil(db, profileId, mestra);
  const { rows } = await db.query<LinhaReceita>(`select ${COLUNAS_RECEITA} from receitas where profile_id = $1 order by criado_em, id`, [profileId]);
  return rows.map((l) => paraReceita(l, chave));
}

export async function obterReceita(db: Db, mestra: Buffer, profileId: string, id: string): Promise<Receita | null> {
  const { rows } = await db.query<LinhaReceita>(`select ${COLUNAS_RECEITA} from receitas where id = $1 and profile_id = $2`, [id, profileId]);
  return rows[0] ? paraReceita(rows[0], await chaveDoPerfil(db, profileId, mestra)) : null;
}

export interface AlteracaoReceita {
  dose?: string;
  horario?: Horario;
  fim?: Date | null;
  validaAte?: string | null;
  unidadesIniciais?: number | null;
  ativa?: boolean;
}

/** Edita a receita e refaz só as tomas futuras ainda pendentes (as registadas nunca se tocam). */
export async function alterarReceita(
  db: Db, mestra: Buffer, userId: string, profileId: string, id: string, a: AlteracaoReceita, ip?: string,
): Promise<Receita | null> {
  const chave = await chaveDoPerfil(db, profileId, mestra);
  const h = a.horario ? colunasHorario(a.horario) : [null, null, null];
  const { rows } = await db.query<LinhaReceita>(
    `update receitas set
       dose_cifrada = coalesce($3, dose_cifrada),
       tipo = coalesce($4::tipo_horario, tipo),
       intervalo_horas = case when $7 then $5::numeric else intervalo_horas end,
       horas_locais = case when $7 then $6::time[] else horas_locais end,
       fim_utc = case when $8 then $9::timestamptz else fim_utc end,
       valida_ate = case when $10 then $11::date else valida_ate end,
       unidades_iniciais = case when $12 then $13::int else unidades_iniciais end,
       ativa = coalesce($14, ativa)
     where id = $1 and profile_id = $2 returning ${COLUNAS_RECEITA}`,
    [
      id, profileId, a.dose ? cifrar(a.dose, chave) : null,
      h[0], h[1], h[2], a.horario !== undefined,
      a.fim !== undefined, a.fim ?? null,
      a.validaAte !== undefined, a.validaAte ?? null,
      a.unidadesIniciais !== undefined, a.unidadesIniciais ?? null,
      a.ativa ?? null,
    ],
  );
  if (!rows[0]) return null;
  await regenerarTomasFuturas(db, id, new Date());
  await auditar(db, 'receita.editar', 'receita', id, userId, profileId, ip);
  return paraReceita(rows[0], chave);
}

export async function apagarReceita(db: Db, userId: string, profileId: string, id: string, ip?: string): Promise<boolean> {
  const res = await db.query('delete from receitas where id = $1 and profile_id = $2', [id, profileId]);
  if (!res.rowCount) return false;
  await auditar(db, 'receita.apagar', 'receita', id, userId, profileId, ip);
  return true;
}

// ---------- Tomas ----------

export interface Toma {
  id: string;
  receitaId: string;
  agendadaUtc: Date;
  estado: 'pendente' | 'tomada' | 'saltada' | 'falhada';
  tomadaEmUtc: Date | null;
}

export async function listarTomas(db: Db, profileId: string, de: Date, ate: Date): Promise<Toma[]> {
  const { rows } = await db.query(
    `select id, receita_id, agendada_utc, estado, tomada_em_utc from tomas
      where profile_id = $1 and agendada_utc >= $2 and agendada_utc < $3 order by agendada_utc, id`,
    [profileId, de, ate],
  );
  return rows.map((r) => ({ id: r.id, receitaId: r.receita_id, agendadaUtc: r.agendada_utc, estado: r.estado, tomadaEmUtc: r.tomada_em_utc }));
}

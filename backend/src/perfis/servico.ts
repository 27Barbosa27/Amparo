import { randomBytes } from 'node:crypto';
import { cifrar, decifrar } from '../auth/cifra.js';
import type { Db } from '../db.js';
import type { PapelAcesso } from './acesso.js';

export type TamanhoTexto = 'normal' | 'grande' | 'muito_grande';
export type AlarmesEm = 'dispositivo_da_pessoa' | 'dispositivo_do_cuidador';

export interface Perfil {
  id: string;
  pseudonimo: string;
  timezone: string;
  tamanhoTexto: TamanhoTexto;
  alarmesEm: AlarmesEm;
  /** Para o botão "Ligar" do cuidador. Opcional. */
  telefone: string | null;
  papel: PapelAcesso;
  criadoEm: Date;
}

interface Linha {
  id: string;
  pseudonimo: string;
  timezone: string;
  tamanho_texto: TamanhoTexto;
  alarmes_em: AlarmesEm;
  telefone_cifrado: Buffer | null;
  papel: PapelAcesso;
  criado_em: Date;
}

const paraPerfil = (l: Linha, chaveCampos: Buffer): Perfil => ({
  id: l.id,
  pseudonimo: l.pseudonimo,
  timezone: l.timezone,
  tamanhoTexto: l.tamanho_texto,
  alarmesEm: l.alarmes_em,
  telefone: l.telefone_cifrado ? decifrar(l.telefone_cifrado, chaveCampos) : null,
  papel: l.papel,
  criadoEm: l.criado_em,
});

const COLUNAS = `p.id, p.pseudonimo, p.timezone, p.tamanho_texto, p.alarmes_em, p.telefone_cifrado, p.criado_em, a.papel`;

async function auditar(db: Pick<Db, 'query'>, acao: string, userId: string, profileId: string, ip?: string): Promise<void> {
  await db.query('insert into audit_logs (acao, entidade, entidade_id, user_id, profile_id, ip) values ($1, $2, $3, $4, $3, $5)', [
    acao, 'profile', profileId, userId, ip ?? null,
  ]);
}

export interface DadosNovoPerfil {
  pseudonimo: string;
  timezone: string;
  tamanhoTexto: TamanhoTexto;
  alarmesEm: AlarmesEm;
  telefone?: string | null;
  autorizacaoVersao: string;
}

/**
 * Cria o perfil de uma pessoa acompanhada. Quem o cria fica como `owner` e declara (com data e
 * versão do texto) que tem a autorização da pessoa ou do seu representante legal.
 * Cada perfil recebe uma chave de cifra própria, guardada cifrada com a chave-mestra.
 */
export async function criarPerfil(
  db: Db,
  userId: string,
  d: DadosNovoPerfil,
  chaves: { mestra: Buffer; campos: Buffer },
  ip?: string,
): Promise<Perfil> {
  const chavePerfil = cifrar(randomBytes(32).toString('base64url'), chaves.mestra);
  const cliente = await db.connect();
  try {
    await cliente.query('begin');
    const p = await cliente.query<{ id: string }>(
      `insert into profiles (pseudonimo, timezone, tamanho_texto, alarmes_em, chave_cifrada, telefone_cifrado)
       values ($1, $2, $3, $4, $5, $6) returning id`,
      [d.pseudonimo, d.timezone, d.tamanhoTexto, d.alarmesEm, chavePerfil, d.telefone ? cifrar(d.telefone, chaves.campos) : null],
    );
    const profileId = p.rows[0]!.id;
    await cliente.query(
      `insert into profile_access (user_id, profile_id, papel, autorizacao_declarada_em, autorizacao_versao)
       values ($1, $2, 'owner', now(), $3)`,
      [userId, profileId, d.autorizacaoVersao],
    );
    await cliente.query('insert into alert_prefs (user_id, profile_id) values ($1, $2)', [userId, profileId]);
    await auditar(cliente, 'perfil.criar', userId, profileId, ip);
    await cliente.query('commit');
    const criado = await obterPerfil(db, userId, profileId, chaves.campos);
    return criado!;
  } catch (e) {
    await cliente.query('rollback').catch(() => undefined);
    throw e;
  } finally {
    cliente.release();
  }
}

/** Só os perfis a que o utilizador tem acesso ativo. */
export async function listarPerfis(db: Db, userId: string, chaveCampos: Buffer): Promise<Perfil[]> {
  const { rows } = await db.query<Linha>(
    `select ${COLUNAS} from profile_access a join profiles p on p.id = a.profile_id
      where a.user_id = $1 and a.revogado_em is null order by p.criado_em, p.id`,
    [userId],
  );
  return rows.map((l) => paraPerfil(l, chaveCampos));
}

export async function obterPerfil(db: Db, userId: string, profileId: string, chaveCampos: Buffer): Promise<Perfil | null> {
  const { rows } = await db.query<Linha>(
    `select ${COLUNAS} from profile_access a join profiles p on p.id = a.profile_id
      where a.user_id = $1 and p.id = $2 and a.revogado_em is null`,
    [userId, profileId],
  );
  return rows[0] ? paraPerfil(rows[0], chaveCampos) : null;
}

export interface AlteracaoPerfil {
  pseudonimo?: string;
  timezone?: string;
  tamanhoTexto?: TamanhoTexto;
  alarmesEm?: AlarmesEm;
  /** `null` apaga o telefone; ausente deixa-o como está. */
  telefone?: string | null;
}

export async function alterarPerfil(
  db: Db,
  userId: string,
  profileId: string,
  a: AlteracaoPerfil,
  chaveCampos: Buffer,
  ip?: string,
): Promise<Perfil | null> {
  await db.query(
    `update profiles set
       pseudonimo = coalesce($2, pseudonimo),
       timezone = coalesce($3, timezone),
       tamanho_texto = coalesce($4::tamanho_texto, tamanho_texto),
       alarmes_em = coalesce($5::alarmes_em, alarmes_em),
       telefone_cifrado = case when $6 then $7 else telefone_cifrado end
     where id = $1`,
    [
      profileId,
      a.pseudonimo ?? null,
      a.timezone ?? null,
      a.tamanhoTexto ?? null,
      a.alarmesEm ?? null,
      a.telefone !== undefined,
      a.telefone ? cifrar(a.telefone, chaveCampos) : null,
    ],
  );
  await auditar(db, 'perfil.editar', userId, profileId, ip);
  return obterPerfil(db, userId, profileId, chaveCampos);
}

/**
 * Apaga o perfil e tudo o que depende dele (receitas, tomas, dispositivos...). Como a chave de
 * cifra do perfil desaparece com ele, os dados cifrados que restem em cópias de segurança
 * deixam de ser legíveis (crypto-shredding). O registo de auditoria fica, só com ids.
 */
export async function apagarPerfil(db: Db, userId: string, profileId: string, ip?: string): Promise<void> {
  await auditar(db, 'perfil.apagar', userId, profileId, ip);
  await db.query('delete from profiles where id = $1', [profileId]);
}

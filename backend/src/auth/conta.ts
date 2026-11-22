import type { Db } from '../db.js';
import { cifrar, decifrar } from './cifra.js';
import { ErroAuth } from './erros.js';
import { verificarSenha } from './senha.js';

/** Telefone do cuidador (para o botão "Ligar"): dado pessoal opcional, guardado cifrado. */
export async function atualizarConta(
  db: Db,
  userId: string,
  a: { nome?: string; telefone?: string | null },
  chave: Buffer,
): Promise<void> {
  await db.query(
    `update users set
       nome_exibicao = coalesce($2, nome_exibicao),
       telefone_cifrado = case when $3 then $4 else telefone_cifrado end
     where id = $1`,
    [userId, a.nome ?? null, a.telefone !== undefined, a.telefone ? cifrar(a.telefone, chave) : null],
  );
}

export async function telefoneDoUtilizador(db: Db, userId: string, chave: Buffer): Promise<string | null> {
  const { rows } = await db.query<{ telefone_cifrado: Buffer | null }>('select telefone_cifrado from users where id = $1', [userId]);
  const t = rows[0]?.telefone_cifrado;
  return t ? decifrar(t, chave) : null;
}

/** Quem cuida deste perfil e tem telefone. Só é visível a quem tem acesso ao perfil (cuidador ou telemóvel ligado). */
export async function contactosDoPerfil(db: Db, profileId: string, chave: Buffer): Promise<{ nome: string | null; telefone: string }[]> {
  const { rows } = await db.query<{ nome_exibicao: string | null; telefone_cifrado: Buffer }>(
    `select u.nome_exibicao, u.telefone_cifrado from profile_access a join users u on u.id = a.user_id
      where a.profile_id = $1 and a.revogado_em is null and u.telefone_cifrado is not null order by a.criado_em, u.id`,
    [profileId],
  );
  return rows.map((r) => ({ nome: r.nome_exibicao, telefone: decifrar(r.telefone_cifrado, chave) }));
}

/** Portabilidade (RGPD): os dados da conta do cuidador, incluindo o email (decifrado só aqui) e o telefone. */
export async function exportarConta(db: Db, userId: string, chave: Buffer, ip?: string) {
  const u = await db.query(
    'select id, nome_exibicao, email_cifrado, telefone_cifrado, consentimento_versao, consentimento_em, criado_em from users where id = $1',
    [userId],
  );
  const r = u.rows[0];
  if (!r) return null;
  const fornecedores = await db.query('select provedor, criado_em from auth_providers where user_id = $1 order by criado_em', [userId]);
  const perfis = await db.query(
    `select p.id, p.pseudonimo, a.papel from profile_access a join profiles p on p.id = a.profile_id
      where a.user_id = $1 and a.revogado_em is null order by p.criado_em, p.id`,
    [userId],
  );
  await db.query('insert into audit_logs (acao, entidade, entidade_id, user_id, ip) values ($1, $2, $3, $3, $4)', ['auth.exportar', 'user', userId, ip ?? null]);
  return {
    geradoEm: new Date(),
    conta: {
      id: r.id as string,
      nome: r.nome_exibicao as string | null,
      email: r.email_cifrado ? decifrar(r.email_cifrado as Buffer, chave) : null,
      telefone: r.telefone_cifrado ? decifrar(r.telefone_cifrado as Buffer, chave) : null,
      consentimentoVersao: r.consentimento_versao as string,
      consentimentoEm: r.consentimento_em as Date,
      criadoEm: r.criado_em as Date,
    },
    fornecedores: fornecedores.rows.map((f) => ({ provedor: f.provedor as string, desde: f.criado_em as Date })),
    perfis: perfis.rows.map((p) => ({ id: p.id as string, pseudonimo: p.pseudonimo as string, papel: p.papel as string })),
  };
}

/**
 * Apaga a conta do cuidador. Os perfis de que era o único cuidador são apagados com tudo o que têm
 * (a chave cifrada desaparece com eles). Nos perfis partilhados, se era o `owner`, o cuidador mais antigo passa a `owner`.
 * A auditoria fica (só tem ids).
 */
export async function apagarConta(db: Db, userId: string, confirmacao: { senha?: string; confirmar?: boolean }, ip?: string): Promise<void> {
  const u = await db.query<{ password_hash: string | null }>('select password_hash from users where id = $1', [userId]);
  if (!u.rows[0]) throw new ErroAuth('nao_autenticado', 401);
  const hash = u.rows[0].password_hash;
  // Conta com palavra-passe: pede-a outra vez. Conta só com Apple/Google: pede a confirmação explícita.
  if (hash ? !confirmacao.senha || !(await verificarSenha(hash, confirmacao.senha)) : confirmacao.confirmar !== true) {
    throw new ErroAuth('senha_incorreta', 403);
  }

  const cliente = await db.connect();
  try {
    await cliente.query('begin');
    const meus = await cliente.query<{ profile_id: string; papel: string; outros: number }>(
      `select pa.profile_id, pa.papel,
              (select count(*)::int from profile_access o where o.profile_id = pa.profile_id and o.user_id <> pa.user_id and o.revogado_em is null) as outros
         from profile_access pa where pa.user_id = $1 and pa.revogado_em is null`,
      [userId],
    );
    for (const p of meus.rows) {
      if (p.outros === 0) {
        await cliente.query('insert into audit_logs (acao, entidade, entidade_id, user_id, profile_id, ip) values ($1, $2, $3, $4, $3, $5)', [
          'perfil.apagar', 'profile', p.profile_id, userId, ip ?? null,
        ]);
        await cliente.query('delete from profiles where id = $1', [p.profile_id]);
      } else if (p.papel === 'owner') {
        await cliente.query(
          `update profile_access set papel = 'owner' where profile_id = $1 and user_id = (
             select user_id from profile_access where profile_id = $1 and user_id <> $2 and revogado_em is null order by criado_em, user_id limit 1)`,
          [p.profile_id, userId],
        );
      }
    }
    await cliente.query('insert into audit_logs (acao, entidade, entidade_id, user_id, ip) values ($1, $2, $3, $3, $4)', ['auth.apagar_conta', 'user', userId, ip ?? null]);
    await cliente.query('delete from users where id = $1', [userId]);
    await cliente.query('commit');
  } catch (e) {
    await cliente.query('rollback').catch(() => undefined);
    throw e;
  } finally {
    cliente.release();
  }
}

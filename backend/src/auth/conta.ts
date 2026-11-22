import type { Db } from '../db.js';
import { cifrar, decifrar } from './cifra.js';

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

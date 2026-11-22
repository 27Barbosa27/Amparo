import type { NextFunction, Request, RequestHandler, Response } from 'express';
import type { Db } from '../db.js';

export type PapelAcesso = 'owner' | 'caregiver';
/** Quem faz o pedido: um cuidador com um dos papéis, ou o telemóvel de uma pessoa (token de dispositivo). */
export type PapelPedido = PapelAcesso | 'dispositivo';

/** Erro de acesso a um perfil. "não encontrado" cobre também "existe mas não é seu". */
export class ErroPerfil extends Error {
  constructor(
    public readonly codigo: 'perfil_nao_encontrado' | 'sem_permissao',
    public readonly estado: number,
  ) {
    super(codigo);
    this.name = 'ErroPerfil';
  }
}

declare module 'express-serve-static-core' {
  interface Request {
    /** Perfil a que o pedido tem acesso, preenchido por `acessoPorParametro` / `acessoPorCabecalho`. */
    perfil?: { id: string; papel: PapelPedido };
    /** Preenchido quando o pedido vem do telemóvel de uma pessoa (token de dispositivo). */
    dispositivo?: { id: string; profileId: string };
  }
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * A ÚNICA verificação de acesso a dados de um perfil. Nenhuma rota lê ou escreve dados de um
 * perfil sem passar por aqui. Se o utilizador não tiver acesso ativo (nunca teve, ou foi revogado),
 * a resposta é a mesma de um perfil inexistente: assim não se descobre que perfis existem.
 */
export async function resolverAcesso(db: Db, userId: string | undefined, profileId: string | undefined) {
  if (!userId) throw new ErroPerfil('perfil_nao_encontrado', 404);
  if (!profileId || !UUID.test(profileId)) throw new ErroPerfil('perfil_nao_encontrado', 404);
  const { rows } = await db.query<{ papel: PapelAcesso }>(
    'select papel from profile_access where user_id = $1 and profile_id = $2 and revogado_em is null',
    [userId, profileId.toLowerCase()],
  );
  const papel = rows[0]?.papel;
  if (!papel) throw new ErroPerfil('perfil_nao_encontrado', 404);
  return { id: profileId.toLowerCase(), papel };
}

/** Para rotas do tipo `/profiles/:profileId/...`. Exige que o utilizador já esteja autenticado. */
export function acessoPorParametro(db: Db): RequestHandler {
  return async (req: Request, _res: Response, next: NextFunction) => {
    try {
      req.perfil = await resolverAcesso(db, req.userId, req.params.profileId as string | undefined);
      next();
    } catch (e) {
      next(e);
    }
  };
}

/** Para rotas que usam o "perfil ativo" enviado no cabeçalho `X-Profile-Id`. */
export function acessoPorCabecalho(db: Db): RequestHandler {
  return async (req: Request, _res: Response, next: NextFunction) => {
    try {
      req.perfil = await resolverAcesso(db, req.userId, req.header('x-profile-id'));
      next();
    } catch (e) {
      next(e);
    }
  };
}

/** Depois do acesso: só estes papéis podem continuar (os outros sabem que o perfil existe, logo 403). */
export function exigirPapel(...papeis: PapelPedido[]): RequestHandler {
  return (req: Request, _res: Response, next: NextFunction) => {
    if (!req.perfil || !papeis.includes(req.perfil.papel)) return next(new ErroPerfil('sem_permissao', 403));
    next();
  };
}

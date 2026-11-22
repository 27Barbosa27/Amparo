import type { NextFunction, Request, RequestHandler, Response } from 'express';
import type { Db } from '../db.js';
import { acessoPorCabecalho, ErroPerfil } from '../perfis/acesso.js';
import { ErroAuth } from './erros.js';
import { hashRefreshToken, verificarAccessToken } from './tokens.js';

/** Os tokens de dispositivo (telemóvel de uma pessoa) começam por isto; os de utilizador são JWT. */
export const PREFIXO_DISPOSITIVO = 'amp_d_';

/**
 * Identifica quem faz o pedido: um cuidador (JWT de acesso) ou o telemóvel de uma pessoa
 * (token de dispositivo, de âmbito de um só perfil). Um token de dispositivo revogado deixa de valer logo.
 */
export function exigirPrincipal(db: Db, jwtSecret: string): RequestHandler {
  return async (req: Request, _res: Response, next: NextFunction) => {
    try {
      const cabecalho = req.header('authorization');
      const token = cabecalho?.startsWith('Bearer ') ? cabecalho.slice(7).trim() : undefined;
      if (!token) throw new ErroAuth('nao_autenticado', 401);
      if (token.startsWith(PREFIXO_DISPOSITIVO)) {
        const { rows } = await db.query<{ id: string; profile_id: string }>(
          `update profile_devices set ultimo_uso_em = now()
            where token_hash = $1 and revogado_em is null returning id, profile_id`,
          [hashRefreshToken(token)],
        );
        if (!rows[0]) throw new ErroAuth('nao_autenticado', 401);
        req.dispositivo = { id: rows[0].id, profileId: rows[0].profile_id };
        req.perfil = { id: rows[0].profile_id, papel: 'dispositivo' };
      } else {
        try {
          req.userId = await verificarAccessToken(token, jwtSecret);
        } catch {
          throw new ErroAuth('nao_autenticado', 401);
        }
      }
      next();
    } catch (e) {
      next(e);
    }
  };
}

/** Um cuidador escolhe o perfil com `X-Profile-Id`; um dispositivo já tem o seu (e só esse). */
export function perfilDoPedido(db: Db): RequestHandler {
  const porCabecalho = acessoPorCabecalho(db);
  return (req, res, next) => (req.dispositivo ? next() : void porCabecalho(req, res, next));
}

/** Só cuidadores (com conta). */
export const soUtilizador: RequestHandler = (req, _res, next) =>
  req.userId ? next() : next(new ErroPerfil('sem_permissao', 403));

/** Só o telemóvel de uma pessoa. */
export const soDispositivo: RequestHandler = (req, _res, next) =>
  req.dispositivo ? next() : next(new ErroPerfil('sem_permissao', 403));

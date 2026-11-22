import type { NextFunction, Request, Response } from 'express';
import { ErroAuth } from './erros.js';
import { verificarAccessToken } from './tokens.js';

declare module 'express-serve-static-core' {
  interface Request {
    /** Preenchido por `exigirAutenticacao`. */
    userId?: string;
  }
}

/** Exige `Authorization: Bearer <token de acesso>` válido e põe o id do utilizador no pedido. */
export function exigirAutenticacao(jwtSecret: string) {
  return async (req: Request, _res: Response, next: NextFunction): Promise<void> => {
    const cabecalho = req.header('authorization');
    const token = cabecalho?.startsWith('Bearer ') ? cabecalho.slice(7).trim() : undefined;
    if (!token) return next(new ErroAuth('nao_autenticado', 401));
    try {
      req.userId = await verificarAccessToken(token, jwtSecret);
      next();
    } catch {
      next(new ErroAuth('nao_autenticado', 401));
    }
  };
}

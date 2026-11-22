import type { RequestHandler } from 'express';
import type { Db } from './db.js';

const UUID = /^\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})(\/|$)/i;

/**
 * Regista no `audit_logs` cada LEITURA de dados de saúde feita por um cuidador (o plano pede escritas e leituras).
 * Guarda só quem, qual perfil, o tipo (`medicamento.ler`...) e o id; nunca o conteúdo.
 * Corre depois da verificação de acesso, por isso um pedido recusado não deixa rasto no perfil de outra pessoa.
 * Se o registo falhar, o pedido falha: uma leitura sem rasto não é aceitável.
 */
export function auditarLeituras(db: Db, entidade: string): RequestHandler {
  return async (req, _res, next) => {
    try {
      if (req.method === 'GET' && req.userId && req.perfil) {
        const id = UUID.exec(req.path)?.[1] ?? null;
        await db.query('insert into audit_logs (acao, entidade, entidade_id, user_id, profile_id, ip) values ($1, $2, $3, $4, $5, $6)', [
          `${entidade}.ler`, entidade, id, req.userId, req.perfil.id, req.ip ?? null,
        ]);
      }
      next();
    } catch (e) {
      next(e);
    }
  };
}

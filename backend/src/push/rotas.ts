import { Router } from 'express';
import { z } from 'zod';
import { lerChave } from '../auth/cifra.js';
import { exigirPrincipal } from '../auth/principal.js';
import type { Config } from '../config.js';
import type { Db } from '../db.js';
import { registarToken, removerToken, type Dono } from './servico.js';

const registoSchema = z.object({
  plataforma: z.enum(['android', 'ios']),
  token: z.string().min(20).max(4096),
});
const removerSchema = z.object({ token: z.string().min(20).max(4096) });

/** `PUT/DELETE /push-tokens`: o telemóvel (de um cuidador ou de uma pessoa ligada) regista o seu token FCM. */
export function rotasPush(db: Db, config: Config): Router {
  const chave = lerChave(config.EMAIL_ENC_KEY);
  const router = Router();
  router.use(exigirPrincipal(db, config.JWT_SECRET));
  const donoDe = (req: { userId?: string; dispositivo?: { id: string } }): Dono =>
    req.userId ? { userId: req.userId } : { dispositivoId: req.dispositivo!.id };

  router.put('/', async (req, res) => {
    const d = registoSchema.parse(req.body);
    await registarToken(db, chave, donoDe(req), d.plataforma, d.token);
    res.status(204).end();
  });

  router.delete('/', async (req, res) => {
    const d = removerSchema.parse(req.body);
    await removerToken(db, donoDe(req), d.token);
    res.status(204).end(); // igual se existia ou não: não se revela
  });

  return router;
}

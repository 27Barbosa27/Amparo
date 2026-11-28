import { Router } from 'express';
import { z } from 'zod';
import { exigirPrincipal, perfilDoPedido, soUtilizador } from '../auth/principal.js';
import type { Config } from '../config.js';
import { auditarLeituras } from '../auditoria.js';
import type { Db } from '../db.js';
import { dispararSemFalhar, type Eventos } from '../eventos.js';
import { lerChave } from '../auth/cifra.js';
import { ErroPerfil } from '../perfis/acesso.js';
import { desfazerRegisto, detalheToma, listarTomasVista, marcarTomada, saltarToma, type Autor } from './registo.js';

const naoEncontrado = () => new ErroPerfil('perfil_nao_encontrado', 404);
const idDa = (v: unknown) => {
  const r = z.uuid().safeParse(v);
  if (!r.success) throw naoEncontrado();
  return r.data.toLowerCase();
};
const data = z.iso.datetime({ offset: true }).transform((v) => new Date(v));

const listaSchema = z.object({ since: data.optional(), de: data.optional(), ate: data.optional() }).refine(
  (q) => !q.de || !q.ate || (q.ate > q.de && q.ate.getTime() - q.de.getTime() <= 92 * 86_400_000),
  { message: 'intervalo inválido (máximo 92 dias)' },
);

const registoSchema = z.object({
  /** Hora real da toma. */
  tomadaEmUtc: data.optional(),
  /** Quando o utilizador tocou, se o pedido saiu da fila offline. */
  eventoEm: data.optional(),
  idempotencyKey: z.string().min(8).max(100).optional(),
});

/**
 * `/tomas`: o que a app mostra em "Hoje". Serve cuidadores (perfil no cabeçalho `X-Profile-Id`) e o telemóvel
 * de uma pessoa (o perfil vem do token). A chave de idempotência pode ir no cabeçalho `Idempotency-Key`.
 */
export function rotasTomas(db: Db, config: Config, eventos: Eventos): Router {
  const mestra = lerChave(config.PROFILE_MASTER_KEY);
  const router = Router();
  router.use(exigirPrincipal(db, config.JWT_SECRET), perfilDoPedido(db), auditarLeituras(db, 'toma'));

  const autorDe = (req: { userId?: string; dispositivo?: { id: string } }): Autor =>
    req.userId ? { userId: req.userId } : { dispositivoId: req.dispositivo!.id };

  /** Só um registo do cuidador avisa o telemóvel da pessoa; o da própria pessoa já está nele. */
  const sincronizarSeCuidador = (req: { userId?: string; perfil?: { id: string } }) =>
    req.userId && req.perfil ? dispararSemFalhar(() => eventos.sincronizar(req.perfil!.id)) : Promise.resolve();

  router.get('/', async (req, res) => {
    const q = listaSchema.parse(req.query);
    const r = await listarTomasVista(db, mestra, req.perfil!.id, { desde: q.since, de: q.de, ate: q.ate });
    res.json(r);
  });

  router.get('/:id', async (req, res) => {
    const d = await detalheToma(db, mestra, req.perfil!.id, idDa(req.params.id));
    if (!d) throw naoEncontrado();
    res.json(d);
  });

  const corpoRegisto = (req: { body: unknown; header(n: string): string | undefined }) => {
    const b = registoSchema.parse(req.body ?? {});
    return { ...b, idempotencyKey: b.idempotencyKey ?? req.header('idempotency-key') ?? undefined };
  };

  router.post('/:id/registo', async (req, res) => {
    const tomaId = idDa(req.params.id);
    const b = corpoRegisto(req);
    const autor = autorDe(req);
    const r = await marcarTomada(db, { tomaId, profileId: req.perfil!.id, autor, ip: req.ip, ...b });
    if (!r.repetido) {
      await dispararSemFalhar(() => eventos.tomaRegistada(req.perfil!.id, tomaId, 'userId' in autor ? autor.userId : null));
      await sincronizarSeCuidador(req);
    }
    res.json({ estado: r.estado, repetido: r.repetido });
  });

  router.post('/:id/saltar', async (req, res) => {
    const b = corpoRegisto(req);
    const r = await saltarToma(db, { tomaId: idDa(req.params.id), profileId: req.perfil!.id, autor: autorDe(req), ip: req.ip, ...b });
    if (!r.repetido) await sincronizarSeCuidador(req);
    res.json({ estado: r.estado, repetido: r.repetido });
  });

  // "Lembrar a Rosa": só um cuidador, e só para uma toma ainda por fazer. O push leva só ids.
  router.post('/:id/lembrar', soUtilizador, async (req, res) => {
    const tomaId = idDa(req.params.id);
    const d = await detalheToma(db, mestra, req.perfil!.id, tomaId);
    if (!d) throw naoEncontrado();
    if (d.toma.estado !== 'pendente') {
      res.status(409).json({ erro: 'toma_ja_registada' });
      return;
    }
    const r = await eventos.lembrar(req.perfil!.id, tomaId, req.userId!);
    if (r === 'enviado') res.status(202).json({ estado: r });
    else res.status(r === 'recente' ? 429 : 409).json({ erro: r === 'recente' ? 'lembrete_recente' : 'sem_telemovel' });
  });

  router.post('/:id/desfazer', async (req, res) => {
    const estado = await desfazerRegisto(db, { tomaId: idDa(req.params.id), profileId: req.perfil!.id, autor: autorDe(req), ip: req.ip });
    await sincronizarSeCuidador(req);
    res.json({ estado });
  });

  return router;
}

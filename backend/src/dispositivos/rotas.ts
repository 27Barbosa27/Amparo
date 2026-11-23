import { Router } from 'express';
import { rateLimit } from 'express-rate-limit';
import { z } from 'zod';
import { ErroAuth } from '../auth/erros.js';
import { exigirPrincipal, soDispositivo } from '../auth/principal.js';
import type { Config } from '../config.js';
import type { Db } from '../db.js';
import { ErroPerfil } from '../perfis/acesso.js';
import { criarCodigo, estadoCodigo, listarDispositivos, registarHeartbeat, resgatarCodigo, revogarDispositivo } from './servico.js';

const naoEncontrado = () => new ErroPerfil('perfil_nao_encontrado', 404);
const idDa = (v: unknown) => {
  const r = z.uuid().safeParse(v);
  if (!r.success) throw naoEncontrado();
  return r.data.toLowerCase();
};

/** Sob `/profiles/:profileId`, depois da verificação de acesso (só cuidadores). */
export function rotasDispositivosDoPerfil(db: Db, config: Config): Router {
  const router = Router();

  router.post('/pairing-codes', async (req, res) => {
    const c = await criarCodigo(db, config.EMAIL_PEPPER, req.userId!, req.perfil!.id, req.ip);
    res.status(201).json({ id: c.id, codigo: c.codigo, expiraEm: c.expiraEm });
  });

  router.get('/pairing-codes/:id', async (req, res) => {
    const estado = await estadoCodigo(db, req.perfil!.id, idDa(req.params.id));
    if (!estado) throw naoEncontrado();
    res.json({ estado });
  });

  router.get('/devices', async (req, res) => {
    res.json({ dispositivos: await listarDispositivos(db, req.perfil!.id) });
  });

  router.delete('/devices/:id', async (req, res) => {
    if (!(await revogarDispositivo(db, req.userId!, req.perfil!.id, idDa(req.params.id), req.ip))) throw naoEncontrado();
    res.status(204).end();
  });

  return router;
}

export interface OpcoesDispositivos {
  /** Limite de tentativas FALHADAS de código por IP (desligável nos testes). */
  limitarCodigos?: { janelaMs: number; maximo: number } | false;
  /** Limite de falhas de TODOS os IPs juntos: com 6 dígitos, um ataque com muitos IPs ainda é uma ameaça. */
  limitarCodigosGlobal?: { janelaMs: number; maximo: number } | false;
}

const resgatarSchema = z.object({
  codigo: z.string().regex(/^\d{6}$/),
  nome: z.string().trim().min(1).max(40).optional(),
});
const heartbeatSchema = z.object({
  alarmesAgendados: z.number().int().min(0).max(10_000),
  permissoes: z.object({ alarmesExatos: z.boolean(), bateriaSemLimites: z.boolean(), ecraBloqueado: z.boolean() }),
});

/** Rotas do telemóvel da pessoa: `/pairing/redeem` (sem conta) e `/devices/heartbeat`. */
export function rotasPublicasDispositivo(db: Db, config: Config, opcoes: OpcoesDispositivos = {}): Router {
  const router = Router();
  const limite = opcoes.limitarCodigos ?? { janelaMs: 15 * 60_000, maximo: 10 };
  const limiteGlobal = opcoes.limitarCodigosGlobal ?? { janelaMs: 15 * 60_000, maximo: 100 };

  router.post(
    '/pairing/redeem',
    limite
      ? rateLimit({
          windowMs: limite.janelaMs,
          limit: limite.maximo,
          skipSuccessfulRequests: true, // só contam as tentativas falhadas
          standardHeaders: 'draft-7',
          legacyHeaders: false,
          handler: (_req, res) => {
            res.status(429).json({ erro: 'demasiadas_tentativas' });
          },
        })
      : (_req, _res, next) => next(),
    limiteGlobal
      ? rateLimit({
          windowMs: limiteGlobal.janelaMs,
          limit: limiteGlobal.maximo,
          skipSuccessfulRequests: true,
          keyGenerator: () => 'global',
          standardHeaders: false,
          legacyHeaders: false,
          handler: (_req, res) => {
            res.status(429).json({ erro: 'demasiadas_tentativas' });
          },
        })
      : (_req, _res, next) => next(),
    async (req, res) => {
      const d = resgatarSchema.safeParse(req.body);
      if (!d.success) throw new ErroAuth('codigo_invalido', 400);
      res.status(201).json(await resgatarCodigo(db, config.EMAIL_PEPPER, d.data.codigo, d.data.nome ?? null, req.ip));
    },
  );

  router.post('/devices/heartbeat', exigirPrincipal(db, config.JWT_SECRET), soDispositivo, async (req, res) => {
    await registarHeartbeat(db, req.dispositivo!.id, heartbeatSchema.parse(req.body));
    res.status(204).end();
  });

  return router;
}

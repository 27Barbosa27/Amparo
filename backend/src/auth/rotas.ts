import { Router } from 'express';
import { rateLimit } from 'express-rate-limit';
import { z } from 'zod';
import type { Config } from '../config.js';
import type { Db } from '../db.js';
import { lerChave } from './cifra.js';
import { ErroAuth } from './erros.js';
import { exigirAutenticacao } from './middleware.js';
import { entrar, perfilDoUtilizador, registar, renovar, sair } from './servico.js';

/** Versão do texto de consentimento que a app mostra (guardada junto do utilizador). */
export const VERSAO_CONSENTIMENTO_ATUAL = '2026-11';

const emailSchema = z.string().trim().max(254).pipe(z.email());
const senhaSchema = z.string().min(8, 'curta').max(128, 'longa');

const registoSchema = z.object({
  email: emailSchema,
  senha: senhaSchema,
  nome: z.string().trim().min(1).max(60),
  aceitaTermos: z.literal(true),
  consentimentoVersao: z.string().min(1).max(20).default(VERSAO_CONSENTIMENTO_ATUAL),
});
const loginSchema = z.object({ email: emailSchema, senha: z.string().min(1).max(128) });
const refreshSchema = z.object({ refreshToken: z.string().min(20).max(200) });

export interface OpcoesAuth {
  /** Limita os pedidos por IP nas rotas de entrada (desligável nos testes). */
  limitarPorIp?: { janelaMs: number; maximo: number } | false;
}

export function rotasAuth(db: Db, config: Config, opcoes: OpcoesAuth = {}): Router {
  const segredos = { jwtSecret: config.JWT_SECRET, emailPepper: config.EMAIL_PEPPER, emailChave: lerChave(config.EMAIL_ENC_KEY) };
  const router = Router();

  const limite = opcoes.limitarPorIp ?? { janelaMs: 60_000, maximo: 20 };
  if (limite) {
    router.use(
      ['/registo', '/login', '/refresh'],
      rateLimit({
        windowMs: limite.janelaMs,
        limit: limite.maximo,
        standardHeaders: 'draft-7',
        legacyHeaders: false,
        handler: (_req, res) => {
          res.status(429).json({ erro: 'demasiadas_tentativas' });
        },
      }),
    );
  }

  router.post('/registo', async (req, res) => {
    const d = registoSchema.parse(req.body);
    const { userId, sessao } = await registar(
      db,
      { email: d.email, senha: d.senha, nome: d.nome, consentimentoVersao: d.consentimentoVersao },
      segredos,
      req.ip,
    );
    res.status(201).json({ utilizador: { id: userId, nome: d.nome }, ...sessao });
  });

  router.post('/login', async (req, res) => {
    const d = loginSchema.parse(req.body);
    const { userId, sessao } = await entrar(db, d.email, d.senha, segredos, req.ip);
    const perfil = await perfilDoUtilizador(db, userId);
    res.json({ utilizador: { id: userId, nome: perfil?.nome ?? null }, ...sessao });
  });

  router.post('/refresh', async (req, res) => {
    const d = refreshSchema.parse(req.body);
    res.json(await renovar(db, d.refreshToken, segredos, req.ip));
  });

  router.post('/logout', async (req, res) => {
    const d = refreshSchema.parse(req.body);
    await sair(db, d.refreshToken, req.ip);
    res.status(204).end();
  });

  router.get('/me', exigirAutenticacao(config.JWT_SECRET), async (req, res) => {
    const perfil = req.userId ? await perfilDoUtilizador(db, req.userId) : null;
    if (!perfil) throw new ErroAuth('nao_autenticado', 401);
    res.json({ utilizador: { id: perfil.id, nome: perfil.nome, criadoEm: perfil.criadoEm } });
  });

  return router;
}

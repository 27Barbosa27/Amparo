import { Router } from 'express';
import { rateLimit } from 'express-rate-limit';
import { z } from 'zod';
import type { Config } from '../config.js';
import type { Db } from '../db.js';
import { atualizarConta, telefoneDoUtilizador } from './conta.js';
import { lerChave } from './cifra.js';
import { ErroAuth } from './erros.js';
import { criarVerificadorExterno, entrarComFornecedor, type Provedor, type VerificadorExterno } from './externo.js';
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
const contaSchema = z
  .object({
    nome: z.string().trim().min(1).max(60),
    telefone: z.string().trim().regex(/^\+?[0-9 ]{9,18}$/).nullable(),
  })
  .partial()
  .refine((o) => Object.keys(o).length > 0, 'nada para alterar');
const externoSchema = z.object({
  idToken: z.string().min(20).max(4096),
  /** O nonce em claro que a app gerou e enviou ao fornecedor. */
  nonce: z.string().min(8).max(200),
  nome: z.string().trim().min(1).max(60).optional(),
  aceitaTermos: z.boolean().optional(),
  consentimentoVersao: z.string().min(1).max(20).default(VERSAO_CONSENTIMENTO_ATUAL),
});
const refreshSchema = z.object({ refreshToken: z.string().min(20).max(200) });

export interface OpcoesAuth {
  /** Limita os pedidos por IP nas rotas de entrada (desligável nos testes). */
  limitarPorIp?: { janelaMs: number; maximo: number } | false;
  /** Valida os ID tokens da Apple e da Google (os testes injetam chaves locais). */
  verificadorExterno?: VerificadorExterno;
}

export function rotasAuth(db: Db, config: Config, opcoes: OpcoesAuth = {}): Router {
  const segredos = { jwtSecret: config.JWT_SECRET, emailPepper: config.EMAIL_PEPPER, emailChave: lerChave(config.EMAIL_ENC_KEY) };
  const router = Router();

  const limite = opcoes.limitarPorIp ?? { janelaMs: 60_000, maximo: 20 };
  if (limite) {
    router.use(
      ['/registo', '/register', '/login', '/refresh', '/apple', '/google'],
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

  router.post(['/registo', '/register'], async (req, res) => {
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

  const verificador =
    opcoes.verificadorExterno ?? criarVerificadorExterno({ appleClientId: config.APPLE_CLIENT_ID, googleClientIds: config.GOOGLE_CLIENT_IDS });
  for (const provedor of ['apple', 'google'] as Provedor[]) {
    router.post(`/${provedor}`, async (req, res) => {
      const d = externoSchema.parse(req.body);
      const identidade = await verificador.verificar(provedor, d.idToken, d.nonce);
      const r = await entrarComFornecedor(db, provedor, identidade, d, segredos, req.ip);
      res.status(r.novo ? 201 : 200).json({ utilizador: { id: r.userId, nome: r.nome }, ...r.sessao });
    });
  }

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
    const telefone = await telefoneDoUtilizador(db, perfil.id, segredos.emailChave);
    res.json({ utilizador: { id: perfil.id, nome: perfil.nome, criadoEm: perfil.criadoEm, telefone } });
  });

  router.patch('/me', exigirAutenticacao(config.JWT_SECRET), async (req, res) => {
    const a = contaSchema.parse(req.body);
    await atualizarConta(db, req.userId!, a, segredos.emailChave);
    res.status(204).end();
  });

  return router;
}

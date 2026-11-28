import express, { Router } from 'express';
import { rateLimit } from 'express-rate-limit';
import { z } from 'zod';
import type { Config } from '../config.js';
import type { Db } from '../db.js';
import { apagarConta, atualizarConta, exportarConta, telefoneDoUtilizador } from './conta.js';
import { lerChave } from './cifra.js';
import { ErroAuth } from './erros.js';
import { pedirRecuperacao, reporSenha, verificarCodigo } from './recuperacao.js';
import { enviadorEmailNulo, type EnviadorEmail } from '../email/enviador.js';
import { criarVerificadorExterno, entrarComFornecedor, type Provedor, type VerificadorExterno } from './externo.js';
import { exigirAutenticacao } from './middleware.js';
import { criarConta, entrar, perfilDoUtilizador, registar, renovar, sair } from './servico.js';
import { confirmarEmail, enviarCodigoVerificacao, reenviarCodigoVerificacao } from './verificacao.js';

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
const apagarSchema = z.object({ senha: z.string().max(128).optional(), confirmar: z.boolean().optional() });
const recuperarSchema = z.object({ email: emailSchema });
const verificarSchema = z.object({ email: emailSchema, codigo: z.string().regex(/^\d{6}$/) });
const reporSchema = z.object({ email: emailSchema, codigo: z.string().regex(/^\d{6}$/), senha: senhaSchema });
const verificarEmailSchema = z.object({ email: emailSchema, codigo: z.string().regex(/^\d{6}$/) });
const refreshSchema = z.object({ refreshToken: z.string().min(20).max(200) });

export interface OpcoesAuth {
  /** Limita os pedidos por IP nas rotas de entrada (desligável nos testes). */
  limitarPorIp?: { janelaMs: number; maximo: number } | false;
  /** Valida os ID tokens da Apple e da Google (os testes injetam chaves locais). */
  verificadorExterno?: VerificadorExterno;
  /** Envia o email de recuperação de palavra-passe (os testes passam um falso). */
  enviadorEmail?: EnviadorEmail;
  /** Exige confirmar o email com um código antes de abrir a sessão. Por omissão vem da configuração (`EXIGIR_VERIFICACAO_EMAIL`, sim). */
  exigirVerificacaoEmail?: boolean;
}

export function rotasAuth(db: Db, config: Config, opcoes: OpcoesAuth = {}): Router {
  const segredos = { jwtSecret: config.JWT_SECRET, emailPepper: config.EMAIL_PEPPER, emailChave: lerChave(config.EMAIL_ENC_KEY) };
  const router = Router();

  const exigirVerificacao = opcoes.exigirVerificacaoEmail ?? config.EXIGIR_VERIFICACAO_EMAIL;
  const enviador = opcoes.enviadorEmail ?? enviadorEmailNulo;
  const limite = opcoes.limitarPorIp ?? { janelaMs: 60_000, maximo: 20 };
  if (limite) {
    router.use(
      ['/registo', '/register', '/login', '/refresh', '/apple', '/google', '/recuperar', '/repor', '/verificar-email', '/reenviar-verificacao'],
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
    const dados = { email: d.email, senha: d.senha, nome: d.nome, consentimentoVersao: d.consentimentoVersao };
    if (!exigirVerificacao) {
      const { userId, sessao } = await registar(db, dados, segredos, req.ip);
      res.status(201).json({ utilizador: { id: userId, nome: d.nome }, ...sessao });
      return;
    }
    // Sem sessão: primeiro prova-se que o email é de quem se registou, com o código que vai por email.
    const userId = await criarConta(db, dados, segredos, false, req.ip);
    await enviarCodigoVerificacao(db, userId, d.email.trim(), segredos, enviador, req.ip);
    res.status(201).json({ utilizador: { id: userId, nome: d.nome }, verificacaoNecessaria: true });
  });

  router.post('/verificar-email', async (req, res) => {
    const d = verificarEmailSchema.parse(req.body);
    const { userId, nome, sessao } = await confirmarEmail(db, d.email, d.codigo, segredos, req.ip);
    res.json({ utilizador: { id: userId, nome }, ...sessao });
  });

  router.post('/reenviar-verificacao', async (req, res) => {
    const d = recuperarSchema.safeParse(req.body);
    // Resposta igual para tudo (conta que existe ou não, verificada ou não, até um email mal formado).
    if (d.success) await reenviarCodigoVerificacao(db, d.data.email, segredos, enviador, req.ip);
    res.status(202).json({ mensagem: 'Se existir uma conta por verificar com esse email, enviámos um código novo.' });
  });

  router.post('/login', async (req, res) => {
    const d = loginSchema.parse(req.body);
    let entrada;
    try {
      entrada = await entrar(db, d.email, d.senha, segredos, req.ip);
    } catch (e) {
      // Palavra-passe certa, email por verificar: manda-se um código novo e a app pede-o.
      if (e instanceof ErroAuth && e.codigo === 'email_nao_verificado') {
        await reenviarCodigoVerificacao(db, d.email, segredos, enviador, req.ip);
      }
      throw e;
    }
    const { userId, sessao } = entrada;
    const perfil = await perfilDoUtilizador(db, userId);
    res.json({ utilizador: { id: userId, nome: perfil?.nome ?? null }, ...sessao });
  });

  const verificador =
    opcoes.verificadorExterno ?? criarVerificadorExterno({ appleClientIds: config.APPLE_CLIENT_ID, googleClientIds: config.GOOGLE_CLIENT_IDS });
  // No Android, "Entrar com a Apple" abre uma página da Apple que no fim faz POST do formulário para aqui. O servidor
  // devolve-o à app por um intent (é o que o plugin sign_in_with_apple espera). Nada se guarda nem se valida aqui:
  // a app recebe o ID token e envia-o depois para `/auth/apple`, que o valida.
  router.post('/apple/callback', express.urlencoded({ extended: false, limit: '16kb' }), (req, res) => {
    const campos = new URLSearchParams();
    for (const [k, v] of Object.entries(req.body ?? {})) if (typeof v === 'string') campos.set(k, v);
    res.redirect(303, `intent://callback?${campos}#Intent;package=${config.APP_ANDROID_PACKAGE};scheme=signinwithapple;end`);
  });

  for (const provedor of ['apple', 'google'] as Provedor[]) {
    router.post(`/${provedor}`, async (req, res) => {
      const d = externoSchema.parse(req.body);
      const identidade = await verificador.verificar(provedor, d.idToken, d.nonce);
      const r = await entrarComFornecedor(db, provedor, identidade, d, segredos, req.ip);
      res.status(r.novo ? 201 : 200).json({ utilizador: { id: r.userId, nome: r.nome }, ...r.sessao });
    });
  }

  router.post('/recuperar', async (req, res) => {
    const d = recuperarSchema.safeParse(req.body);
    // Resposta igual para tudo (conta que existe ou não, e até um email mal formado): não se revela nada.
    if (d.success) {
      await pedirRecuperacao(db, d.data.email, segredos, { enviador: opcoes.enviadorEmail ?? enviadorEmailNulo }, req.ip);
    }
    res.status(202).json({ mensagem: 'Se existir uma conta com esse email, enviámos uma ligação para definir a palavra-passe.' });
  });

  router.post('/recuperar/verificar', async (req, res) => {
    const d = verificarSchema.parse(req.body);
    await verificarCodigo(db, d.email, d.codigo, segredos, req.ip);
    res.status(204).end();
  });

  router.post('/repor', async (req, res) => {
    const d = reporSchema.parse(req.body);
    await reporSenha(db, d.email, d.codigo, d.senha, segredos, req.ip);
    res.status(204).end();
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
    const telefone = await telefoneDoUtilizador(db, perfil.id, segredos.emailChave);
    // `temSenha`: ao apagar a conta, a app pede a palavra-passe ou (só Apple/Google) a confirmação explícita.
    res.json({ utilizador: { id: perfil.id, nome: perfil.nome, criadoEm: perfil.criadoEm, telefone, temSenha: perfil.temSenha } });
  });

  router.get('/me/exportacao', exigirAutenticacao(config.JWT_SECRET), async (req, res) => {
    const dados = await exportarConta(db, req.userId!, segredos.emailChave, req.ip);
    if (!dados) throw new ErroAuth('nao_autenticado', 401);
    res.json(dados);
  });

  router.delete('/me', exigirAutenticacao(config.JWT_SECRET), async (req, res) => {
    await apagarConta(db, req.userId!, apagarSchema.parse(req.body ?? {}), req.ip);
    res.status(204).end();
  });

  router.patch('/me', exigirAutenticacao(config.JWT_SECRET), async (req, res) => {
    const a = contaSchema.parse(req.body);
    await atualizarConta(db, req.userId!, a, segredos.emailChave);
    res.status(204).end();
  });

  return router;
}

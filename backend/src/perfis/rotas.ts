import { Router } from 'express';
import { z } from 'zod';
import { lerChave } from '../auth/cifra.js';
import { exigirAutenticacao } from '../auth/middleware.js';
import { VERSAO_CONSENTIMENTO_ATUAL } from '../auth/rotas.js';
import type { Config } from '../config.js';
import type { Db } from '../db.js';
import { rotasMedicacao } from '../medicacao/rotas.js';
import { timezoneSchema } from './validacao.js';
import { acessoPorCabecalho, acessoPorParametro, exigirPapel, ErroPerfil } from './acesso.js';
import { alterarPerfil, apagarPerfil, criarPerfil, listarPerfis, obterPerfil } from './servico.js';

const tamanhoTexto = z.enum(['normal', 'grande', 'muito_grande']);
const alarmesEm = z.enum(['dispositivo_da_pessoa', 'dispositivo_do_cuidador']);

const novoPerfilSchema = z.object({
  pseudonimo: z.string().trim().min(1).max(40),
  timezone: timezoneSchema.default('Europe/Lisbon'),
  tamanhoTexto: tamanhoTexto.default('grande'),
  alarmesEm: alarmesEm.default('dispositivo_da_pessoa'),
  /** O cuidador declara que tem a autorização da pessoa ou do seu representante legal. */
  autorizacaoDeclarada: z.literal(true),
  autorizacaoVersao: z.string().min(1).max(20).default(VERSAO_CONSENTIMENTO_ATUAL),
});

const alteracaoSchema = z
  .object({
    pseudonimo: z.string().trim().min(1).max(40),
    timezone: timezoneSchema,
    tamanhoTexto,
    alarmesEm,
  })
  .partial()
  .refine((o) => Object.keys(o).length > 0, 'nada para alterar');

/** `/profiles`: gestão dos perfis a que o utilizador tem acesso. */
export function rotasPerfis(db: Db, config: Config): Router {
  const chaveMestra = lerChave(config.PROFILE_MASTER_KEY);
  const router = Router();
  router.use(exigirAutenticacao(config.JWT_SECRET));

  router.get('/', async (req, res) => {
    res.json({ perfis: await listarPerfis(db, req.userId!) });
  });

  router.post('/', async (req, res) => {
    const d = novoPerfilSchema.parse(req.body);
    const perfil = await criarPerfil(db, req.userId!, d, chaveMestra, req.ip);
    res.status(201).json({ perfil });
  });

  // Tudo o que está abaixo de /profiles/:profileId passa PRIMEIRO pela verificação de acesso.
  const porPerfil = Router();
  router.use('/:profileId', acessoPorParametro(db), porPerfil);

  porPerfil.use(rotasMedicacao(db, chaveMestra));

  porPerfil.get('/', async (req, res) => {
    const perfil = await obterPerfil(db, req.userId!, req.perfil!.id);
    if (!perfil) throw new ErroPerfil('perfil_nao_encontrado', 404);
    res.json({ perfil });
  });

  porPerfil.patch('/', exigirPapel('owner'), async (req, res) => {
    const a = alteracaoSchema.parse(req.body);
    const perfil = await alterarPerfil(db, req.userId!, req.perfil!.id, a, req.ip);
    res.json({ perfil });
  });

  porPerfil.delete('/', exigirPapel('owner'), async (req, res) => {
    await apagarPerfil(db, req.userId!, req.perfil!.id, req.ip);
    res.status(204).end();
  });

  return router;
}

/** `GET /perfil-ativo`: o perfil indicado no cabeçalho `X-Profile-Id`, se o utilizador tiver acesso. */
export function rotaPerfilAtivo(db: Db, config: Config): Router {
  const router = Router();
  router.get('/', exigirAutenticacao(config.JWT_SECRET), acessoPorCabecalho(db), async (req, res) => {
    const perfil = await obterPerfil(db, req.userId!, req.perfil!.id);
    if (!perfil) throw new ErroPerfil('perfil_nao_encontrado', 404);
    res.json({ perfil });
  });
  return router;
}

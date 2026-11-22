import { Router } from 'express';
import { z } from 'zod';
import { ErroPerfil } from '../perfis/acesso.js';
import { timezoneSchema } from '../perfis/validacao.js';
import type { Db } from '../db.js';
import * as s from './servico.js';

const uuid = z.uuid();
const naoEncontrado = () => new ErroPerfil('perfil_nao_encontrado', 404);

/** Um id inválido na URL responde como "não encontrado", igual a um que não existe. */
function idDa(valor: unknown): string {
  const r = uuid.safeParse(valor);
  if (!r.success) throw naoEncontrado();
  return r.data.toLowerCase();
}

const medicamentoSchema = z.object({
  nome: z.string().trim().min(1).max(100),
  notas: z.string().trim().max(1000).optional(),
});
const alteracaoMedSchema = z
  .object({ nome: z.string().trim().min(1).max(100), notas: z.string().trim().max(1000).nullable() })
  .partial()
  .refine((o) => Object.keys(o).length > 0, 'nada para alterar');

const horaLocal = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/);
const horarioSchema = z.discriminatedUnion('tipo', [
  z.object({ tipo: z.literal('intervalo'), intervaloHoras: z.number().min(0.25).max(168) }),
  z.object({
    tipo: z.literal('horas_fixas'),
    horasLocais: z
      .array(horaLocal)
      .min(1)
      .max(24)
      .refine((h) => new Set(h).size === h.length, 'horas repetidas')
      .transform((h) => [...h].sort()),
  }),
]);

const data = z.iso.datetime({ offset: true }).transform((v) => new Date(v));
const diaSchema = z.iso.date();

const receitaSchema = z
  .object({
    medicamentoId: z.uuid(),
    dose: z.string().trim().min(1).max(100),
    horario: horarioSchema,
    timezone: timezoneSchema.default('Europe/Lisbon'),
    inicio: data,
    fim: data.nullable().default(null),
    validaAte: diaSchema.nullable().default(null),
    unidadesIniciais: z.number().int().min(0).max(100000).nullable().default(null),
  })
  .refine((r) => r.fim === null || r.fim > r.inicio, { message: 'fim antes do início', path: ['fim'] });

const alteracaoReceitaSchema = z
  .object({
    dose: z.string().trim().min(1).max(100),
    horario: horarioSchema,
    fim: data.nullable(),
    validaAte: diaSchema.nullable(),
    unidadesIniciais: z.number().int().min(0).max(100000).nullable(),
    ativa: z.boolean(),
  })
  .partial()
  .refine((o) => Object.keys(o).length > 0, 'nada para alterar');

const intervaloTomasSchema = z.object({ de: data, ate: data }).refine((q) => q.ate > q.de && q.ate.getTime() - q.de.getTime() <= 32 * 86_400_000, {
  message: 'intervalo inválido (máximo 32 dias)',
});

/**
 * Rotas de medicação de um perfil. Montadas SOB `/profiles/:profileId`, depois da verificação
 * de acesso, por isso `req.perfil` já está validado. Cada consulta filtra também por perfil.
 */
export function rotasMedicacao(db: Db, mestra: Buffer): Router {
  const router = Router();

  router.post('/medicamentos', async (req, res) => {
    const d = medicamentoSchema.parse(req.body);
    res.status(201).json({ medicamento: await s.criarMedicamento(db, mestra, req.userId!, req.perfil!.id, d, req.ip) });
  });
  router.get('/medicamentos', async (req, res) => {
    res.json({ medicamentos: await s.listarMedicamentos(db, mestra, req.perfil!.id) });
  });
  router.get('/medicamentos/:id', async (req, res) => {
    const m = await s.obterMedicamento(db, mestra, req.perfil!.id, idDa(req.params.id));
    if (!m) throw naoEncontrado();
    res.json({ medicamento: m });
  });
  router.patch('/medicamentos/:id', async (req, res) => {
    const id = idDa(req.params.id);
    const m = await s.alterarMedicamento(db, mestra, req.userId!, req.perfil!.id, id, alteracaoMedSchema.parse(req.body), req.ip);
    if (!m) throw naoEncontrado();
    res.json({ medicamento: m });
  });
  router.delete('/medicamentos/:id', async (req, res) => {
    if (!(await s.apagarMedicamento(db, req.userId!, req.perfil!.id, idDa(req.params.id), req.ip))) throw naoEncontrado();
    res.status(204).end();
  });

  router.post('/receitas', async (req, res) => {
    const d = receitaSchema.parse(req.body);
    const r = await s.criarReceita(db, mestra, req.userId!, req.perfil!.id, d, req.ip);
    if (!r) throw naoEncontrado(); // medicamento inexistente ou de outro perfil
    res.status(201).json({ receita: r });
  });
  router.get('/receitas', async (req, res) => {
    res.json({ receitas: await s.listarReceitas(db, mestra, req.perfil!.id) });
  });
  router.get('/receitas/:id', async (req, res) => {
    const r = await s.obterReceita(db, mestra, req.perfil!.id, idDa(req.params.id));
    if (!r) throw naoEncontrado();
    res.json({ receita: r });
  });
  router.patch('/receitas/:id', async (req, res) => {
    const id = idDa(req.params.id);
    const r = await s.alterarReceita(db, mestra, req.userId!, req.perfil!.id, id, alteracaoReceitaSchema.parse(req.body), req.ip);
    if (!r) throw naoEncontrado();
    res.json({ receita: r });
  });
  router.delete('/receitas/:id', async (req, res) => {
    if (!(await s.apagarReceita(db, req.userId!, req.perfil!.id, idDa(req.params.id), req.ip))) throw naoEncontrado();
    res.status(204).end();
  });

  router.get('/tomas', async (req, res) => {
    const { de, ate } = intervaloTomasSchema.parse(req.query);
    res.json({ tomas: await s.listarTomas(db, req.perfil!.id, de, ate) });
  });

  return router;
}

import { Router } from 'express';
import { z } from 'zod';
import { exigirPrincipal, perfilDoPedido, soUtilizador } from '../auth/principal.js';
import type { Config } from '../config.js';
import type { Db } from '../db.js';

const prefsSchema = z.object({
  tomaNaoConfirmada: z.boolean(),
  esperaMin: z.number().int().min(1).max(180),
  tomaFeita: z.boolean(),
  receitaAcabar: z.boolean(),
  diasAntes: z.number().int().min(1).max(30),
});

const paraPrefs = (r: Record<string, any>) => ({
  tomaNaoConfirmada: r.toma_nao_confirmada as boolean,
  esperaMin: r.espera_min as number,
  tomaFeita: r.toma_feita as boolean,
  receitaAcabar: r.receita_a_acabar as boolean,
  diasAntes: r.dias_antes as number,
});

/** `GET/PUT /alert-prefs`: as preferências de alerta do cuidador para o perfil ativo (`X-Profile-Id`). */
export function rotasAlertPrefs(db: Db, config: Config): Router {
  const router = Router();
  router.use(exigirPrincipal(db, config.JWT_SECRET), soUtilizador, perfilDoPedido(db));

  router.get('/', async (req, res) => {
    // O acesso já foi validado: se por algum motivo a linha não existir, cria-se com as predefinições.
    await db.query('insert into alert_prefs (user_id, profile_id) values ($1, $2) on conflict do nothing', [req.userId, req.perfil!.id]);
    const { rows } = await db.query('select * from alert_prefs where user_id = $1 and profile_id = $2', [req.userId, req.perfil!.id]);
    res.json({ prefs: paraPrefs(rows[0]) });
  });

  router.put('/', async (req, res) => {
    const p = prefsSchema.parse(req.body);
    const { rows } = await db.query(
      `insert into alert_prefs (user_id, profile_id, toma_nao_confirmada, espera_min, toma_feita, receita_a_acabar, dias_antes)
       values ($1, $2, $3, $4, $5, $6, $7)
       on conflict (user_id, profile_id) do update set toma_nao_confirmada = $3, espera_min = $4,
         toma_feita = $5, receita_a_acabar = $6, dias_antes = $7
       returning *`,
      [req.userId, req.perfil!.id, p.tomaNaoConfirmada, p.esperaMin, p.tomaFeita, p.receitaAcabar, p.diasAntes],
    );
    res.json({ prefs: paraPrefs(rows[0]) });
  });

  return router;
}

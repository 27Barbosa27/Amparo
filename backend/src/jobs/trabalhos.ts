import type { Db } from '../db.js';
import { listarReceitas } from '../medicacao/servico.js';
import type { EnviadorPush } from '../push/enviador.js';
import { alertarUtilizadores, marcarAlertaEnviado } from '../push/servico.js';
import { manterJanela } from '../tomas/servico.js';

/** Uma toma pendente passa a `falhada` quando se esgota esta janela depois da hora prevista. */
export const JANELA_FALHADA_MIN = 120;

export interface Contexto {
  db: Db;
  enviador: EnviadorPush;
  /** Chave dos campos pessoais (cifra dos tokens FCM). */
  chaveCampos: Buffer;
  /** Chave-mestra dos perfis (para ler doses e calcular os dias que restam). */
  chaveMestra: Buffer;
}

/** Marca como `falhada` a toma pendente que passou da janela. Devolve quantas. */
export async function marcarFalhadas(db: Db, agora: Date, janelaMin = JANELA_FALHADA_MIN): Promise<number> {
  const r = await db.query(
    `update tomas set estado = 'falhada'
      where estado = 'pendente' and agendada_utc < $1::timestamptz - make_interval(mins => $2)`,
    [agora, janelaMin],
  );
  return r.rowCount ?? 0;
}

/**
 * "Toma não confirmada": avisa cada cuidador depois do tempo que escolheu (10, 15 ou 30 min) e uma só vez.
 * Só olha para tomas dentro da janela, para que uma paragem do servidor não inunde ninguém de avisos antigos.
 */
export async function alertarNaoConfirmadas(c: Contexto, agora: Date): Promise<number> {
  const { rows } = await c.db.query<{ toma_id: string; profile_id: string; user_id: string }>(
    `select t.id as toma_id, t.profile_id, a.user_id
       from tomas t
       join alert_prefs a on a.profile_id = t.profile_id and a.toma_nao_confirmada
       join profile_access pa on pa.user_id = a.user_id and pa.profile_id = a.profile_id and pa.revogado_em is null
      where t.estado = 'pendente'
        and t.agendada_utc + make_interval(mins => a.espera_min) <= $1
        and t.agendada_utc > $1::timestamptz - make_interval(mins => $2)
        and not exists (select 1 from alertas_enviados e where e.user_id = a.user_id and e.tipo = 'toma_nao_confirmada' and e.chave = t.id::text)`,
    [agora, JANELA_FALHADA_MIN],
  );
  const porPerfil = new Map<string, Set<string>>();
  for (const r of rows) {
    if (await marcarAlertaEnviado(c.db, r.user_id, 'toma_nao_confirmada', r.toma_id)) {
      porPerfil.set(r.profile_id, (porPerfil.get(r.profile_id) ?? new Set()).add(r.user_id));
    }
  }
  let enviados = 0;
  for (const [perfil, users] of porPerfil) {
    await alertarUtilizadores(c.db, c.enviador, c.chaveCampos, [...users], { tipo: 'alerta', perfil, subtipo: 'toma_nao_confirmada' });
    enviados += users.size;
  }
  return enviados;
}

/** "Receita a acabar": quando os dias que restam chegam ao que o cuidador escolheu. No máximo um aviso por receita e por dia. */
export async function alertarReceitasAAcabar(c: Contexto, agora: Date): Promise<number> {
  const { rows } = await c.db.query<{ profile_id: string; user_id: string; dias_antes: number }>(
    `select a.profile_id, a.user_id, a.dias_antes from alert_prefs a
       join profile_access pa on pa.user_id = a.user_id and pa.profile_id = a.profile_id and pa.revogado_em is null
      where a.receita_a_acabar`,
  );
  const dia = agora.toISOString().slice(0, 10);
  const cache = new Map<string, Awaited<ReturnType<typeof listarReceitas>>>();
  const porPerfil = new Map<string, Set<string>>();
  for (const p of rows) {
    if (!cache.has(p.profile_id)) {
      try {
        cache.set(p.profile_id, await listarReceitas(c.db, c.chaveMestra, p.profile_id));
      } catch (e) {
        // Um perfil com problemas (apagado a meio, chave ilegível) nunca pode calar os alertas dos outros.
        console.error('Receitas a acabar: perfil ignorado:', e instanceof Error ? e.message : 'desconhecido');
        cache.set(p.profile_id, []);
      }
    }
    for (const r of cache.get(p.profile_id)!) {
      const terminada = r.fim !== null && r.fim <= agora;
      if (!r.ativa || terminada || r.stock?.diasRestantes == null || r.stock.diasRestantes > p.dias_antes) continue;
      if (await marcarAlertaEnviado(c.db, p.user_id, 'receita_a_acabar', `${r.id}:${dia}`)) {
        porPerfil.set(p.profile_id, (porPerfil.get(p.profile_id) ?? new Set()).add(p.user_id));
      }
    }
  }
  let enviados = 0;
  for (const [perfil, users] of porPerfil) {
    await alertarUtilizadores(c.db, c.enviador, c.chaveCampos, [...users], { tipo: 'alerta', perfil, subtipo: 'receita_a_acabar' });
    enviados += users.size;
  }
  return enviados;
}

/** Apaga o que já não serve (nunca o `audit_logs`, que é só de acrescentar). */
export async function limpar(db: Db): Promise<void> {
  await db.query("delete from pairing_codes where expira_em < now() - interval '1 day'");
  await db.query("delete from refresh_tokens where expira_em < now() - interval '1 day' or revogado_em < now() - interval '30 days'");
  await db.query("delete from tomas_removidas where removida_em < now() - interval '30 days'");
  await db.query("delete from alertas_enviados where enviado_em < now() - interval '30 days'");
  await db.query("delete from push_tokens where revogado_em < now() - interval '30 days'");
  await db.query("delete from password_resets where expira_em < now() - interval '1 day'");
}

/** Todos os minutos: primeiro os avisos (olham para tomas pendentes), depois marcar as falhadas. */
export async function trabalhosDoMinuto(c: Contexto, agora = new Date()) {
  const alertas = await alertarNaoConfirmadas(c, agora);
  const falhadas = await marcarFalhadas(c.db, agora);
  return { alertas, falhadas };
}

/** Uma vez por dia: mantém a janela de 90 dias de tomas, avisa receitas a acabar e limpa. */
export async function trabalhosDiarios(c: Contexto, agora = new Date()) {
  const janela = await manterJanela(c.db, agora);
  const receitas = await alertarReceitasAAcabar(c, agora);
  await limpar(c.db);
  return { ...janela, alertasReceita: receitas };
}

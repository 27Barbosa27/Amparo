import { listarDispositivos } from '../dispositivos/servico.js';
import type { Db } from '../db.js';
import { listarMedicamentos, listarReceitas } from '../medicacao/servico.js';

/**
 * Portabilidade (RGPD): tudo o que a app guarda sobre a pessoa acompanhada, em JSON legível.
 * Sem hashes, tokens nem chaves, e sem identificar os cuidadores (só quantos são).
 */
export async function exportarPerfil(db: Db, mestra: Buffer, profileId: string, userId: string, ip?: string) {
  const p = await db.query('select pseudonimo, timezone, tamanho_texto, alarmes_em, criado_em from profiles where id = $1', [profileId]);
  const acesso = await db.query('select papel, criado_em, revogado_em, autorizacao_declarada_em, autorizacao_versao from profile_access where profile_id = $1 order by criado_em, user_id', [profileId]);
  const tomas = await db.query(
    'select id, receita_id, agendada_utc, estado, tomada_em_utc, origem, registado_em from tomas where profile_id = $1 order by agendada_utc, id',
    [profileId],
  );
  await db.query('insert into audit_logs (acao, entidade, entidade_id, user_id, profile_id, ip) values ($1, $2, $3, $4, $3, $5)', [
    'perfil.exportar', 'profile', profileId, userId, ip ?? null,
  ]);
  const r = p.rows[0];
  return {
    geradoEm: new Date(),
    perfil: { pseudonimo: r.pseudonimo, timezone: r.timezone, tamanhoTexto: r.tamanho_texto, alarmesEm: r.alarmes_em, criadoEm: r.criado_em },
    cuidadores: acesso.rows.map((a) => ({
      papel: a.papel,
      desde: a.criado_em,
      revogadoEm: a.revogado_em,
      autorizacaoDeclaradaEm: a.autorizacao_declarada_em,
      autorizacaoVersao: a.autorizacao_versao,
    })),
    medicamentos: await listarMedicamentos(db, mestra, profileId),
    receitas: await listarReceitas(db, mestra, profileId),
    tomas: tomas.rows.map((t) => ({
      id: t.id,
      receitaId: t.receita_id,
      agendadaUtc: t.agendada_utc,
      estado: t.estado,
      tomadaEmUtc: t.tomada_em_utc,
      origem: t.origem,
      registadoEm: t.registado_em,
    })),
    dispositivos: await listarDispositivos(db, profileId),
  };
}

import { afterAll, describe, expect, it } from 'vitest';
import { createPool } from '../src/db.js';

const db = createPool(process.env.DATABASE_URL ?? 'postgres://invalido');
afterAll(async () => {
  await db.end();
});

describe('Esquema da base de dados', () => {
  it('tem todas as tabelas do plano', async () => {
    const { rows } = await db.query<{ table_name: string }>(
      "select table_name from information_schema.tables where table_schema = 'public'",
    );
    const nomes = rows.map((r) => r.table_name);
    for (const t of [
      'users', 'auth_providers', 'profiles', 'profile_access', 'alert_prefs', 'pairing_codes',
      'profile_devices', 'push_tokens', 'medicamentos', 'receitas', 'tomas', 'refresh_tokens', 'audit_logs',
    ]) {
      expect(nomes).toContain(t);
    }
  });

  it('audit_logs aceita inserções mas rejeita alterações e apagamentos', async () => {
    const ins = await db.query<{ id: string }>(
      "insert into audit_logs (acao, entidade) values ('teste', 'schema') returning id",
    );
    const id = ins.rows[0]?.id;
    expect(id).toBeDefined();
    await expect(db.query('update audit_logs set acao = $1 where id = $2', ['x', id])).rejects.toThrow(/append-only/);
    await expect(db.query('delete from audit_logs where id = $1', [id])).rejects.toThrow(/append-only/);
    await expect(db.query('truncate audit_logs')).rejects.toThrow(/append-only/);
  });

  it('uma receita por intervalo exige o intervalo e proíbe horas fixas', async () => {
    const q = db.query(
      `insert into receitas (profile_id, medicamento_id, dose_cifrada, tipo, horas_locais, timezone, inicio_utc)
       values (gen_random_uuid(), gen_random_uuid(), '\\x00', 'intervalo', array['08:00']::time[], 'Europe/Lisbon', now())`,
    );
    await expect(q).rejects.toThrow(/check constraint/i);
  });

  it('não permite uma toma tomada sem hora de toma', async () => {
    const q = db.query(
      `insert into tomas (receita_id, profile_id, agendada_utc, estado)
       values (gen_random_uuid(), gen_random_uuid(), now(), 'tomada')`,
    );
    await expect(q).rejects.toThrow(/check constraint/i);
  });
});

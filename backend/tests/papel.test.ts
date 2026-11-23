import { afterAll, describe, expect, it } from 'vitest';
import { loadConfig } from '../src/config.js';
import { createPool } from '../src/db.js';

const db = createPool(loadConfig().DATABASE_URL);
afterAll(async () => {
  await db.end();
});

/** Corre `f` como o papel de execução da API (amparo_app) numa transação que se desfaz sempre. */
async function comoPapelApp<T>(f: (q: (sql: string, p?: unknown[]) => Promise<{ rows: any[]; rowCount: number | null }>) => Promise<T>): Promise<T> {
  const c = await db.connect();
  try {
    await c.query('begin');
    await c.query('set local role amparo_app');
    return await f((sql, p) => c.query(sql, p));
  } finally {
    await c.query('rollback').catch(() => undefined);
    c.release();
  }
}
/** Executa dentro de um savepoint e devolve o erro (ou null), para a transação continuar utilizável. */
async function tentar(q: (sql: string, p?: unknown[]) => Promise<unknown>, sql: string): Promise<{ code?: string; message?: string } | null> {
  await q('savepoint t');
  try {
    await q(sql);
    await q('release savepoint t');
    return null;
  } catch (e) {
    await q('rollback to savepoint t');
    return e as { code?: string; message?: string };
  }
}

describe('Papel de execução da API (amparo_app)', () => {
  it('lê e acrescenta à auditoria, mas não a consegue alterar, apagar nem esvaziar (REVOKE, além do trigger)', async () => {
    await comoPapelApp(async (q) => {
      expect(await tentar(q, "insert into audit_logs (acao) values ('teste.papel')")).toBeNull();
      expect(await tentar(q, 'select count(*) from audit_logs')).toBeNull();
      for (const sql of ["update audit_logs set acao = 'x'", 'delete from audit_logs', 'truncate audit_logs']) {
        const erro = await tentar(q, sql);
        expect(erro?.code, sql).toBe('42501');
        expect(erro?.message, sql).toMatch(/permission denied/i); // negado pelas permissões, antes de chegar ao trigger
      }
    });
  });

  it('trabalha normalmente nas outras tabelas', async () => {
    await comoPapelApp(async (q) => {
      const u = await q("insert into users (consentimento_versao, consentimento_em) values ('t', now()) returning id");
      const id = u.rows[0].id;
      expect(await tentar(q, `update users set nome_exibicao = 'x' where id = '${id}'`)).toBeNull();
      expect(await tentar(q, "select count(*) from tomas where estado = 'pendente'")).toBeNull();
      expect(await tentar(q, `delete from users where id = '${id}'`)).toBeNull();
      expect(await tentar(q, "select nextval(pg_get_serial_sequence('audit_logs', 'id'))")).toBeNull();
    });
  });

  it('não toca no histórico de migrações', async () => {
    await comoPapelApp(async (q) => {
      for (const sql of ['select * from pgmigrations', 'delete from pgmigrations']) {
        expect((await tentar(q, sql))?.code, sql).toBe('42501');
      }
    });
  });

  it('o trigger continua a travar quem tem permissões a mais (duas barreiras)', async () => {
    const e = await db.query("update audit_logs set acao = 'x' where false").then(() => null, (x) => x as { code?: string; message?: string });
    expect(e).toBeNull(); // nenhuma linha afetada: o trigger é por linha
    const c = await db.query("insert into audit_logs (acao) values ('teste.trigger') returning id");
    const erro = await db.query('update audit_logs set acao = $2 where id = $1', [c.rows[0].id, 'x']).then(() => null, (x) => x as { message?: string });
    expect(erro?.message).toMatch(/append-only/);
  });
});

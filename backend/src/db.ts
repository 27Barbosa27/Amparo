import pg from 'pg';

export type Db = pg.Pool;

export function createPool(connectionString: string): Db {
  return new pg.Pool({ connectionString, max: 10, idleTimeoutMillis: 30_000 });
}

/** Devolve true se a base de dados responde. */
export async function pingDb(db: Db): Promise<boolean> {
  try {
    await db.query('select 1');
    return true;
  } catch {
    return false;
  }
}

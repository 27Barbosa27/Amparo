import pg from 'pg';

export type Db = pg.Pool;

export interface OpcoesPool {
  /** Quanto esperar por uma ligação à base de dados antes de desistir. */
  ligacaoMs?: number;
}

export function createPool(connectionString: string, o: OpcoesPool = {}): Db {
  const pool = new pg.Pool({
    connectionString,
    max: 10,
    idleTimeoutMillis: 30_000,
    // Sem isto, uma base de dados inacessível deixava os pedidos pendurados minutos.
    connectionTimeoutMillis: o.ligacaoMs ?? 5_000,
    statement_timeout: 30_000,
    query_timeout: 35_000,
  });
  // Um erro numa ligação ociosa (a base de dados reiniciou) não pode derrubar o processo.
  pool.on('error', (e) => console.error('Erro numa ligação ociosa à base de dados:', e.message));
  return pool;
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

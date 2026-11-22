import { createApp } from './app.js';
import { loadConfig } from './config.js';
import { createPool } from './db.js';

const config = loadConfig();
const db = createPool(config.DATABASE_URL);
const app = createApp(db, config);

const server = app.listen(config.PORT, '127.0.0.1', () => {
  console.log(`Amparo API a ouvir em http://127.0.0.1:${config.PORT}`);
});

async function parar(): Promise<void> {
  server.close();
  await db.end();
  process.exit(0);
}
process.on('SIGINT', parar);
process.on('SIGTERM', parar);

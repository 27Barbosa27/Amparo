import express, { type ErrorRequestHandler } from 'express';
import helmet from 'helmet';
import { pingDb, type Db } from './db.js';

export function createApp(db: Db) {
  const app = express();
  app.disable('x-powered-by');
  app.use(helmet());
  app.use(express.json({ limit: '100kb' }));

  // Estado do servidor (sem tocar na base de dados).
  app.get('/health', (_req, res) => {
    res.json({ estado: 'ok' });
  });

  // Estado do servidor e da base de dados.
  app.get('/health/db', async (_req, res) => {
    const ok = await pingDb(db);
    res.status(ok ? 200 : 503).json({ estado: ok ? 'ok' : 'sem_base_de_dados' });
  });

  app.use((_req, res) => {
    res.status(404).json({ erro: 'nao_encontrado' });
  });

  // Nunca devolve detalhes internos ao cliente (podem conter dados de saúde).
  const erros: ErrorRequestHandler = (err, _req, res, _next) => {
    console.error('Erro não tratado:', err instanceof Error ? err.message : 'desconhecido');
    res.status(500).json({ erro: 'erro_interno' });
  };
  app.use(erros);

  return app;
}

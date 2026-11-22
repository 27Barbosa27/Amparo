import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { createPool } from '../src/db.js';

describe('API: estado', () => {
  const config = loadConfig();
  const db = createPool(config.DATABASE_URL);
  const app = createApp(db, config);

  it('GET /health responde ok sem tocar na base de dados', async () => {
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ estado: 'ok' });
  });

  it('não revela a tecnologia do servidor', async () => {
    const res = await request(app).get('/health');
    expect(res.headers['x-powered-by']).toBeUndefined();
  });

  it('rota inexistente devolve 404 em JSON', async () => {
    const res = await request(app).get('/nao-existe');
    expect(res.status).toBe(404);
    expect(res.body).toEqual({ erro: 'nao_encontrado' });
  });

  it('GET /health/db confirma a ligação à base de dados', async () => {
    const res = await request(app).get('/health/db');
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ estado: 'ok' });
  });
});

describe('API: base de dados inacessível', () => {
  it('/health/db responde 503 depressa em vez de ficar pendurado', async () => {
    const config = loadConfig();
    // 10.255.255.1 não é encaminhável: a ligação nunca se completa.
    const db = createPool('postgres://amparo:x@10.255.255.1:5432/amparo', { ligacaoMs: 400 });
    const app = createApp(db, config);
    const inicio = Date.now();
    const res = await request(app).get('/health/db');
    expect(res.status).toBe(503);
    expect(res.body).toEqual({ estado: 'sem_base_de_dados' });
    expect(Date.now() - inicio).toBeLessThan(3000);
    await db.end().catch(() => undefined);
  });
});

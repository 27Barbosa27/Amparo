import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../src/app.js';
import { createPool } from '../src/db.js';

describe('API: estado', () => {
  const db = createPool(process.env.DATABASE_URL ?? 'postgres://invalido');
  const app = createApp(db);

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

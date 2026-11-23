import request from 'supertest';
import { afterAll, describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { createPool } from '../src/db.js';

const base = loadConfig();
const db = createPool(base.DATABASE_URL);
afterAll(async () => {
  await db.end();
});
const comOrigens = (o: string) => createApp(db, loadConfig({ ...process.env, CORS_ORIGINS: o }), { registar: false });

describe('CORS (só para origens da lista)', () => {
  const app = comOrigens('http://127.0.0.1:8099, http://localhost:8099');

  it('autoriza uma origem da lista, incluindo o pedido prévio (preflight)', async () => {
    const pre = await request(app)
      .options('/auth/login')
      .set('Origin', 'http://127.0.0.1:8099')
      .set('Access-Control-Request-Method', 'POST')
      .set('Access-Control-Request-Headers', 'content-type, authorization, x-profile-id');
    expect(pre.status).toBe(204);
    expect(pre.headers['access-control-allow-origin']).toBe('http://127.0.0.1:8099');
    expect(pre.headers['access-control-allow-headers']).toContain('x-profile-id');
    expect(pre.headers.vary).toContain('Origin');
    const real = await request(app).get('/health').set('Origin', 'http://localhost:8099');
    expect(real.headers['access-control-allow-origin']).toBe('http://localhost:8099');
  });

  it('não autoriza outras origens nem usa "*"', async () => {
    const r = await request(app).get('/health').set('Origin', 'https://evil.example');
    expect(r.status).toBe(200);
    expect(r.headers['access-control-allow-origin']).toBeUndefined();
    const pre = await request(app).options('/auth/login').set('Origin', 'https://evil.example').set('Access-Control-Request-Method', 'POST');
    expect(pre.headers['access-control-allow-origin']).toBeUndefined();
    expect(pre.status).not.toBe(204);
  });

  it('sem lista, não há CORS nenhum (o comportamento de produção)', async () => {
    const semLista = comOrigens('');
    const r = await request(semLista).get('/health').set('Origin', 'http://127.0.0.1:8099');
    expect(r.headers['access-control-allow-origin']).toBeUndefined();
  });
});

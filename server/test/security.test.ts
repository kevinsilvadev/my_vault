import request from 'supertest';
import { describe, expect, it } from 'vitest';

import { loadConfig } from '../src/config/env.js';
import { ACCOUNT_PASSWORD, buildTestApp, registerUser, testConfig } from './support/test-app.js';

const device = { name: 'Teste', platform: 'windows' };

describe('cabeçalhos e respostas', () => {
  it('envia cabeçalhos de segurança e não identifica o framework', async () => {
    const { app } = buildTestApp();
    const res = await request(app).get('/health').expect(200);
    expect(res.headers['x-powered-by']).toBeUndefined();
    expect(res.headers['x-content-type-options']).toBe('nosniff');
    expect(res.headers['strict-transport-security']).toBeDefined();
    expect(res.headers['cache-control']).toBe('no-store');
  });

  it('CORS fechado por padrão', async () => {
    const { app } = buildTestApp();
    const res = await request(app).get('/health').set('Origin', 'https://malicioso.example');
    expect(res.headers['access-control-allow-origin']).toBeUndefined();
  });

  it('CORS permite apenas as origens configuradas', async () => {
    const { app } = buildTestApp({ corsOrigins: ['https://app.example'] });
    const allowed = await request(app).get('/health').set('Origin', 'https://app.example');
    expect(allowed.headers['access-control-allow-origin']).toBe('https://app.example');
  });

  it('JSON malformado e rota inexistente devolvem erros genéricos', async () => {
    const { app } = buildTestApp();
    const bad = await request(app)
      .post('/api/v1/auth/login')
      .set('Content-Type', 'application/json')
      .send('{"email": "x", "password": "segredo123"')
      .expect(400);
    expect(bad.body.error.code).toBe('INVALID_JSON');
    expect(JSON.stringify(bad.body)).not.toContain('segredo123');
    await request(app).get('/api/v1/nao-existe').expect(404);
  });

  it('erros de validação não ecoam os valores enviados', async () => {
    const { app } = buildTestApp();
    const res = await request(app)
      .post('/api/v1/auth/login')
      .send({ email: 'x@example.com', password: 'senha-secreta-123', device, extra: 'valor-secreto' })
      .expect(400);
    const body = JSON.stringify(res.body);
    expect(body).not.toContain('senha-secreta-123');
    expect(body).not.toContain('valor-secreto');
  });
});

describe('HTTPS obrigatório', () => {
  it('recusa HTTP quando exigido', async () => {
    const { app } = buildTestApp({ requireHttps: true });
    const res = await request(app).get('/health').expect(403);
    expect(res.body.error.code).toBe('HTTPS_REQUIRED');
  });

  it('aceita HTTPS terminado em proxy confiável', async () => {
    const { app } = buildTestApp({ requireHttps: true, trustProxy: 1 });
    await request(app).get('/health').set('X-Forwarded-Proto', 'https').expect(200);
  });

  it('ignora X-Forwarded-Proto sem proxy confiável', async () => {
    const { app } = buildTestApp({ requireHttps: true, trustProxy: false });
    await request(app).get('/health').set('X-Forwarded-Proto', 'https').expect(403);
  });
});

describe('rate limiting', () => {
  it('bloqueia tentativas repetidas de login na mesma conta', async () => {
    const { app } = buildTestApp({
      rateLimit: { ...testConfig().rateLimit, failedLoginsPerAccount: 3 },
    });
    const { email } = await registerUser(app);
    const attempt = () =>
      request(app).post('/api/v1/auth/login').send({ email, password: 'tentativa-errada', device });

    for (let i = 0; i < 3; i++) await attempt().expect(401);
    const blocked = await attempt().expect(429);
    expect(blocked.body.error.code).toBe('RATE_LIMITED');

    // Mesmo com a senha certa, a conta segue bloqueada até a janela expirar.
    await request(app)
      .post('/api/v1/auth/login')
      .send({ email, password: ACCOUNT_PASSWORD, device })
      .expect(429);
  });

  it('limita requisições de autenticação por IP', async () => {
    const { app } = buildTestApp({ rateLimit: { ...testConfig().rateLimit, authPerIp: 2 } });
    const refresh = () => request(app).post('/api/v1/auth/refresh').send({ refreshToken: 'x'.repeat(43) });
    await refresh().expect(401);
    await refresh().expect(401);
    await refresh().expect(429);
  });
});

describe('configuração', () => {
  const base = { DATABASE_URL: 'postgresql://x', JWT_SECRET: 'a'.repeat(32) };

  it('exige JWT_SECRET forte e não expõe valores no erro', () => {
    expect(() => loadConfig({ ...base, JWT_SECRET: 'curto-demais' })).toThrow(/JWT_SECRET/);
    expect(() => loadConfig({ ...base, JWT_SECRET: 'curto-demais' })).not.toThrow(/curto-demais/);
  });

  it('em produção, HTTPS é obrigatório por padrão', () => {
    expect(loadConfig({ ...base, NODE_ENV: 'production' }).requireHttps).toBe(true);
    expect(loadConfig({ ...base, NODE_ENV: 'development' }).requireHttps).toBe(false);
  });
});

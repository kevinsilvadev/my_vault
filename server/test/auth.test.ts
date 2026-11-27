import request from 'supertest';
import { describe, expect, it } from 'vitest';

import { PasswordHasher } from '../src/auth/password-hasher.js';
import { ACCOUNT_PASSWORD, bearer, buildTestApp, registerUser } from './support/test-app.js';

const device = { name: 'Notebook', platform: 'windows' };

describe('autenticação', () => {
  it('cadastra e devolve tokens sem expor o hash da senha', async () => {
    const { app, db } = buildTestApp();
    const res = await request(app)
      .post('/api/v1/auth/register')
      .send({ email: ' Pessoa@Example.com ', password: ACCOUNT_PASSWORD, device })
      .expect(201);

    expect(res.body).toMatchObject({
      accessToken: expect.any(String),
      refreshToken: expect.any(String),
      accessTokenExpiresIn: 900,
    });
    expect(JSON.stringify(res.body)).not.toContain('scrypt$');
    const [user] = [...db.users.values()];
    expect(user?.email).toBe('pessoa@example.com');
    expect(user?.passwordHash).not.toContain(ACCOUNT_PASSWORD);
  });

  it('recusa senha de conta curta e e-mail inválido', async () => {
    const { app } = buildTestApp();
    const res = await request(app)
      .post('/api/v1/auth/register')
      .send({ email: 'invalido', password: 'curta', device })
      .expect(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
    expect(JSON.stringify(res.body)).not.toContain('curta');
  });

  it('não permite cadastro duplicado', async () => {
    const { app } = buildTestApp();
    const { email } = await registerUser(app);
    await request(app)
      .post('/api/v1/auth/register')
      .send({ email, password: ACCOUNT_PASSWORD, device })
      .expect(409);
  });

  it('respeita ALLOW_REGISTRATION=false', async () => {
    const { app } = buildTestApp({ allowRegistration: false });
    const res = await request(app)
      .post('/api/v1/auth/register')
      .send({ email: 'a@example.com', password: ACCOUNT_PASSWORD, device })
      .expect(403);
    expect(res.body.error.code).toBe('REGISTRATION_DISABLED');
  });

  it('login com senha errada e com e-mail inexistente devolvem o mesmo erro', async () => {
    const { app } = buildTestApp();
    const { email } = await registerUser(app);

    const wrongPassword = await request(app)
      .post('/api/v1/auth/login')
      .send({ email, password: 'outra-senha-qualquer', device })
      .expect(401);
    const unknownEmail = await request(app)
      .post('/api/v1/auth/login')
      .send({ email: 'ninguem@example.com', password: 'outra-senha-qualquer', device })
      .expect(401);

    expect(wrongPassword.body).toEqual(unknownEmail.body);
    expect(wrongPassword.body.error.code).toBe('INVALID_CREDENTIALS');
  });

  it('login reutiliza o dispositivo informado e cria sessão nova', async () => {
    const { app, db } = buildTestApp();
    const first = await registerUser(app);
    const res = await request(app)
      .post('/api/v1/auth/login')
      .send({ email: first.email, password: ACCOUNT_PASSWORD, device: { ...device, id: first.deviceId } })
      .expect(200);
    expect(res.body.deviceId).toBe(first.deviceId);
    expect(db.devices.size).toBe(1);
    expect(db.sessions.size).toBe(2);
  });

  it('rotaciona o refresh token e invalida o anterior', async () => {
    const { app } = buildTestApp();
    const session = await registerUser(app);

    const rotated = await request(app)
      .post('/api/v1/auth/refresh')
      .send({ refreshToken: session.refreshToken })
      .expect(200);
    expect(rotated.body.refreshToken).not.toBe(session.refreshToken);

    await request(app)
      .get('/api/v1/devices')
      .set(...bearer(rotated.body))
      .expect(200);
  });

  it('reuso de refresh token revoga a sessão inteira', async () => {
    const { app } = buildTestApp();
    const session = await registerUser(app);
    const rotated = await request(app)
      .post('/api/v1/auth/refresh')
      .send({ refreshToken: session.refreshToken })
      .expect(200);

    // Um atacante reapresenta o token antigo...
    await request(app).post('/api/v1/auth/refresh').send({ refreshToken: session.refreshToken }).expect(401);
    // ...e a sessão legítima também deixa de funcionar.
    await request(app).post('/api/v1/auth/refresh').send({ refreshToken: rotated.body.refreshToken }).expect(401);
    await request(app).get('/api/v1/devices').set(...bearer(rotated.body)).expect(401);
  });

  it('logout revoga o token de acesso imediatamente', async () => {
    const { app } = buildTestApp();
    const session = await registerUser(app);
    await request(app).post('/api/v1/auth/logout').set(...bearer(session)).expect(204);
    await request(app).get('/api/v1/devices').set(...bearer(session)).expect(401);
    await request(app).post('/api/v1/auth/refresh').send({ refreshToken: session.refreshToken }).expect(401);
  });

  it('rejeita tokens ausentes, malformados ou adulterados', async () => {
    const { app } = buildTestApp();
    const session = await registerUser(app);
    await request(app).get('/api/v1/devices').expect(401);
    await request(app).get('/api/v1/devices').set('Authorization', 'Bearer x.y.z').expect(401);
    const [header, payload, signature = ''] = session.accessToken.split('.');
    const flipped = signature.startsWith('A') ? 'B' : 'A';
    const tampered = `${header}.${payload}.${flipped}${signature.slice(1)}`;
    await request(app).get('/api/v1/devices').set('Authorization', `Bearer ${tampered}`).expect(401);
  });

  it('token assinado com outro segredo não é aceito', async () => {
    const a = buildTestApp();
    const b = buildTestApp();
    const session = await registerUser(a.app);
    await request(b.app).get('/api/v1/devices').set(...bearer(session)).expect(401);
  });
});

describe('dispositivos', () => {
  it('lista e revoga dispositivos; o revogado perde acesso', async () => {
    const { app } = buildTestApp();
    const windows = await registerUser(app);
    const androidLogin = await request(app)
      .post('/api/v1/auth/login')
      .send({ email: windows.email, password: ACCOUNT_PASSWORD, device: { name: 'Celular', platform: 'android' } })
      .expect(200);
    const android = androidLogin.body;

    const list = await request(app).get('/api/v1/devices').set(...bearer(windows)).expect(200);
    expect(list.body.devices).toHaveLength(2);
    expect(list.body.devices.find((d: { current: boolean }) => d.current).id).toBe(windows.deviceId);

    await request(app).delete(`/api/v1/devices/${android.deviceId}`).set(...bearer(windows)).expect(204);
    await request(app).get('/api/v1/sync/pull').set(...bearer(android)).expect(401);
    await request(app).post('/api/v1/auth/refresh').send({ refreshToken: android.refreshToken }).expect(401);

    const after = await request(app).get('/api/v1/devices').set(...bearer(windows)).expect(200);
    expect(after.body.devices).toHaveLength(1);
  });
});

describe('PasswordHasher', () => {
  const hasher = new PasswordHasher({ N: 2 ** 10, r: 8, p: 1 });

  it('verifica a senha correta e rejeita as demais', async () => {
    const hash = await hasher.hash('senha correta');
    expect(await hasher.verify('senha correta', hash)).toBe(true);
    expect(await hasher.verify('senha errada', hash)).toBe(false);
    expect(await hasher.verify('senha correta', 'formato$invalido')).toBe(false);
  });

  it('usa salt aleatório e sinaliza rehash quando os parâmetros mudam', async () => {
    const a = await hasher.hash('mesma');
    const b = await hasher.hash('mesma');
    expect(a).not.toBe(b);
    expect(hasher.needsRehash(a)).toBe(false);
    expect(new PasswordHasher({ N: 2 ** 11, r: 8, p: 1 }).needsRehash(a)).toBe(true);
  });
});

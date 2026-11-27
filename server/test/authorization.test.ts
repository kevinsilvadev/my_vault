import { randomUUID } from 'node:crypto';

import request from 'supertest';
import { describe, expect, it } from 'vitest';

import { bearer, buildTestApp, fakeCiphertext, fakeEnvelope, registerUser } from './support/test-app.js';

/** Acesso indevido: nenhum usuário pode ler ou alterar o cofre de outro. */
describe('isolamento entre usuários', () => {
  it('pull de um usuário nunca inclui itens de outro', async () => {
    const { app } = buildTestApp();
    const alice = await registerUser(app);
    const bob = await registerUser(app);

    await request(app)
      .post('/api/v1/sync/push')
      .set(...bearer(alice))
      .send({
        changes: [
          { changeId: randomUUID(), itemId: randomUUID(), operation: 'upsert', baseVersion: 0, cryptoVersion: 1, ...fakeCiphertext() },
        ],
      })
      .expect(200);

    const res = await request(app).get('/api/v1/sync/pull').set(...bearer(bob)).expect(200);
    expect(res.body).toMatchObject({ items: [], latestRevision: 0 });
  });

  it('o mesmo itemId em outro usuário é um registro independente', async () => {
    const { app, db } = buildTestApp();
    const alice = await registerUser(app);
    const bob = await registerUser(app);
    const sharedId = randomUUID();
    const aliceData = fakeCiphertext();

    const change = (data: ReturnType<typeof fakeCiphertext>) => ({
      changes: [{ changeId: randomUUID(), itemId: sharedId, operation: 'upsert', baseVersion: 0, cryptoVersion: 1, ...data }],
    });

    await request(app).post('/api/v1/sync/push').set(...bearer(alice)).send(change(aliceData)).expect(200);
    // Bob tenta "sobrescrever" o item de Alice adivinhando o id.
    const res = await request(app).post('/api/v1/sync/push').set(...bearer(bob)).send(change(fakeCiphertext())).expect(200);
    expect(res.body.results[0].status).toBe('applied');

    expect(db.items.get(`${alice.userId}:${sharedId}`)?.encryptedData).toBe(aliceData.encryptedData);
    const alicePull = await request(app).get('/api/v1/sync/pull').set(...bearer(alice)).expect(200);
    expect(alicePull.body.items[0].encryptedData).toBe(aliceData.encryptedData);
  });

  it('o envelope da chave é visível apenas para o dono', async () => {
    const { app } = buildTestApp();
    const alice = await registerUser(app);
    const bob = await registerUser(app);

    await request(app)
      .put('/api/v1/vault/key-envelope')
      .set(...bearer(alice))
      .send({ envelope: fakeEnvelope(), baseVersion: 0 })
      .expect(200);
    await request(app).get('/api/v1/vault/key-envelope').set(...bearer(bob)).expect(404);
  });

  it('um usuário não pode revogar dispositivo de outro (e não descobre se existe)', async () => {
    const { app } = buildTestApp();
    const alice = await registerUser(app);
    const bob = await registerUser(app);

    const foreign = await request(app).delete(`/api/v1/devices/${alice.deviceId}`).set(...bearer(bob)).expect(404);
    const missing = await request(app).delete(`/api/v1/devices/${randomUUID()}`).set(...bearer(bob)).expect(404);
    expect(foreign.body).toEqual(missing.body);
    await request(app).get('/api/v1/devices').set(...bearer(alice)).expect(200);
  });

  it('rotas do cofre e da sincronização exigem autenticação', async () => {
    const { app } = buildTestApp();
    await request(app).get('/api/v1/sync/pull').expect(401);
    await request(app).post('/api/v1/sync/push').send({ changes: [] }).expect(401);
    await request(app).get('/api/v1/vault/key-envelope').expect(401);
    await request(app).put('/api/v1/vault/key-envelope').send({}).expect(401);
    await request(app).get('/api/v1/devices').expect(401);
  });
});

describe('envelope da chave do cofre', () => {
  it('cria, lê e atualiza com controle de versão', async () => {
    const { app } = buildTestApp();
    const user = await registerUser(app);
    const envelope = fakeEnvelope();

    await request(app).get('/api/v1/vault/key-envelope').set(...bearer(user)).expect(404);
    const created = await request(app)
      .put('/api/v1/vault/key-envelope')
      .set(...bearer(user))
      .send({ envelope, baseVersion: 0 })
      .expect(200);
    expect(created.body.version).toBe(1);

    const read = await request(app).get('/api/v1/vault/key-envelope').set(...bearer(user)).expect(200);
    expect(read.body).toMatchObject({ envelope, version: 1 });

    // Segundo dispositivo tentando criar outro envelope por cima.
    await request(app)
      .put('/api/v1/vault/key-envelope')
      .set(...bearer(user))
      .send({ envelope: fakeEnvelope(), baseVersion: 0 })
      .expect(409);

    await request(app)
      .put('/api/v1/vault/key-envelope')
      .set(...bearer(user))
      .send({ envelope: fakeEnvelope(), baseVersion: 1 })
      .expect(200);
  });

  it('rejeita parâmetros de KDF abaixo do piso e campos inesperados', async () => {
    const { app } = buildTestApp();
    const user = await registerUser(app);
    const weak = fakeEnvelope();
    weak.kdf.memoryKiB = 1024;
    await request(app)
      .put('/api/v1/vault/key-envelope')
      .set(...bearer(user))
      .send({ envelope: weak, baseVersion: 0 })
      .expect(400);

    await request(app)
      .put('/api/v1/vault/key-envelope')
      .set(...bearer(user))
      .send({ envelope: { ...fakeEnvelope(), masterPassword: 'nunca' }, baseVersion: 0 })
      .expect(400);
  });
});

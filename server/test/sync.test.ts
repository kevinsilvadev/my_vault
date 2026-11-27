import { randomUUID } from 'node:crypto';

import request from 'supertest';
import { beforeEach, describe, expect, it } from 'vitest';
import type { Express } from 'express';

import { bearer, buildTestApp, fakeCiphertext, registerUser, type TestSession } from './support/test-app.js';

function upsert(itemId: string, baseVersion: number, changeId: string = randomUUID()) {
  return { changeId, itemId, operation: 'upsert', baseVersion, cryptoVersion: 1, ...fakeCiphertext() };
}

function remove(itemId: string, baseVersion: number) {
  return { changeId: randomUUID(), itemId, operation: 'delete', baseVersion };
}

describe('sincronização', () => {
  let app: Express;
  let user: TestSession;

  const push = (changes: unknown[], session: TestSession = user) =>
    request(app).post('/api/v1/sync/push').set(...bearer(session)).send({ changes });
  const pull = (since = 0, limit?: number, session: TestSession = user) =>
    request(app)
      .get('/api/v1/sync/pull')
      .query(limit ? { since, limit } : { since })
      .set(...bearer(session));

  beforeEach(async () => {
    ({ app } = buildTestApp());
    user = await registerUser(app);
  });

  it('cria um item e o devolve no pull', async () => {
    const itemId = randomUUID();
    const change = upsert(itemId, 0);
    const res = await push([change]).expect(200);
    expect(res.body.results).toEqual([
      { changeId: change.changeId, itemId, status: 'applied', version: 1, revision: 1 },
    ]);

    const pulled = await pull().expect(200);
    expect(pulled.body).toMatchObject({ cursor: 1, hasMore: false, latestRevision: 1 });
    expect(pulled.body.items).toEqual([
      expect.objectContaining({
        id: itemId,
        encryptedData: change.encryptedData,
        nonce: change.nonce,
        version: 1,
        deleted: false,
      }),
    ]);
  });

  it('o servidor guarda somente ciphertext e metadados mínimos', async () => {
    await push([upsert(randomUUID(), 0)]).expect(200);
    const pulled = await pull().expect(200);
    expect(Object.keys(pulled.body.items[0]).sort()).toEqual(
      ['cryptoVersion', 'deleted', 'encryptedData', 'id', 'nonce', 'revision', 'updatedAt', 'version'].sort(),
    );
  });

  it('atualiza com a versão correta e detecta conflito com versão desatualizada', async () => {
    const itemId = randomUUID();
    await push([upsert(itemId, 0)]).expect(200);
    const second = await push([upsert(itemId, 1)]).expect(200);
    expect(second.body.results[0]).toMatchObject({ status: 'applied', version: 2 });

    const stale = await push([upsert(itemId, 1)]).expect(200);
    expect(stale.body.results[0]).toMatchObject({
      status: 'conflict',
      serverItem: { id: itemId, version: 2 },
    });
  });

  it('não sobrescreve item existente ao criar com baseVersion 0', async () => {
    const itemId = randomUUID();
    await push([upsert(itemId, 0)]).expect(200);
    const res = await push([upsert(itemId, 0)]).expect(200);
    expect(res.body.results[0].status).toBe('conflict');
  });

  it('é idempotente ao repetir o mesmo changeId', async () => {
    const change = upsert(randomUUID(), 0);
    const first = await push([change]).expect(200);
    const retry = await push([change]).expect(200);
    expect(retry.body.results).toEqual(first.body.results);
    const pulled = await pull().expect(200);
    expect(pulled.body.items).toHaveLength(1);
    expect(pulled.body.latestRevision).toBe(1);
  });

  it('rejeita reuso de changeId para outro item', async () => {
    const change = upsert(randomUUID(), 0);
    await push([change]).expect(200);
    const res = await push([{ ...change, itemId: randomUUID() }]).expect(200);
    expect(res.body.results[0]).toMatchObject({ status: 'rejected', reason: 'change_id_reused' });
  });

  it('rejeita baseVersion de item desconhecido', async () => {
    const res = await push([upsert(randomUUID(), 5)]).expect(200);
    expect(res.body.results[0]).toMatchObject({ status: 'rejected', reason: 'base_version_not_found' });
  });

  it('exclusão vira tombstone sem conteúdo', async () => {
    const itemId = randomUUID();
    await push([upsert(itemId, 0)]).expect(200);
    await push([remove(itemId, 1)]).expect(200);

    const pulled = await pull(1).expect(200);
    expect(pulled.body.items).toEqual([
      expect.objectContaining({ id: itemId, deleted: true, encryptedData: null, nonce: null, version: 2 }),
    ]);
  });

  it('exclusão sobre versão desatualizada é conflito', async () => {
    const itemId = randomUUID();
    await push([upsert(itemId, 0)]).expect(200);
    await push([upsert(itemId, 1)]).expect(200);
    const res = await push([remove(itemId, 1)]).expect(200);
    expect(res.body.results[0].status).toBe('conflict');
  });

  it('processa lotes com resultados independentes', async () => {
    const existing = randomUUID();
    await push([upsert(existing, 0)]).expect(200);
    const res = await push([upsert(randomUUID(), 0), upsert(existing, 0), upsert(randomUUID(), 0)]).expect(200);
    expect(res.body.results.map((r: { status: string }) => r.status)).toEqual([
      'applied',
      'conflict',
      'applied',
    ]);
  });

  it('pagina o pull pelo cursor de revisão', async () => {
    for (let i = 0; i < 5; i++) await push([upsert(randomUUID(), 0)]).expect(200);

    const first = await pull(0, 2).expect(200);
    expect(first.body).toMatchObject({ cursor: 2, hasMore: true });
    const second = await pull(first.body.cursor, 2).expect(200);
    expect(second.body).toMatchObject({ cursor: 4, hasMore: true });
    const third = await pull(second.body.cursor, 2).expect(200);
    expect(third.body).toMatchObject({ cursor: 5, hasMore: false });
    const empty = await pull(third.body.cursor, 2).expect(200);
    expect(empty.body).toMatchObject({ items: [], cursor: 5, hasMore: false });
  });

  it('pushes concorrentes do mesmo usuário recebem revisões únicas', async () => {
    const responses = await Promise.all(
      Array.from({ length: 10 }, () => push([upsert(randomUUID(), 0)]).expect(200)),
    );
    const revisions = responses.map((r) => r.body.results[0].revision as number).sort((a, b) => a - b);
    expect(revisions).toEqual([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
  });

  describe('validação', () => {
    it.each([
      ['lista vazia', []],
      ['nonce com tamanho errado', [{ ...upsert(randomUUID(), 0), nonce: 'AAAA' }]],
      ['base64 inválido', [{ ...upsert(randomUUID(), 0), encryptedData: '***' }]],
      ['id que não é UUID', [{ ...upsert(randomUUID(), 0), itemId: '../../etc' }]],
      ['campo desconhecido', [{ ...upsert(randomUUID(), 0), title: 'vazado' }]],
      ['delete com conteúdo', [{ ...remove(randomUUID(), 0), encryptedData: 'AAAA' }]],
      ['versão negativa', [upsert(randomUUID(), -1)]],
    ])('rejeita %s', async (_label, changes) => {
      const res = await push(changes).expect(400);
      expect(res.body.error.code).toBe('VALIDATION_ERROR');
    });

    it('rejeita changeId duplicado no mesmo envio', async () => {
      const change = upsert(randomUUID(), 0);
      await push([change, { ...change, itemId: randomUUID() }]).expect(400);
    });

    it('rejeita mais de 100 alterações por envio', async () => {
      const changes = Array.from({ length: 101 }, () => upsert(randomUUID(), 0));
      await push(changes).expect(400);
    });

    it('rejeita parâmetros de pull inválidos', async () => {
      await pull(-1).expect(400);
      await request(app).get('/api/v1/sync/pull?limit=10000').set(...bearer(user)).expect(400);
    });
  });
});

import { randomBytes, randomUUID } from 'node:crypto';

import request from 'supertest';
import type { Express } from 'express';

import { createApp } from '../../src/app.js';
import { PasswordHasher } from '../../src/auth/password-hasher.js';
import type { AppConfig } from '../../src/config/env.js';
import { createLogger } from '../../src/shared/logger.js';
import {
  InMemoryDatabase,
  InMemoryDeviceRepository,
  InMemoryKeyEnvelopeRepository,
  InMemorySessionRepository,
  InMemorySyncRepository,
  InMemoryUserRepository,
} from './in-memory-repositories.js';

export const ACCOUNT_PASSWORD = 'senha-da-conta-de-teste';

export function testConfig(overrides: Partial<AppConfig> = {}): AppConfig {
  return {
    env: 'test',
    port: 0,
    databaseUrl: 'postgresql://unused',
    jwtSecret: randomBytes(48).toString('base64url'),
    accessTokenTtlSeconds: 900,
    refreshTokenTtlDays: 30,
    corsOrigins: [],
    trustProxy: false,
    requireHttps: false,
    allowRegistration: true,
    logLevel: 'silent',
    rateLimit: { windowMs: 60_000, authPerIp: 1000, failedLoginsPerAccount: 1000, globalPerIp: 10_000 },
    ...overrides,
  };
}

// Parâmetros baratos SOMENTE para testes.
const fastHasher = new PasswordHasher({ N: 2 ** 10, r: 8, p: 1 });

export function buildTestApp(overrides: Partial<AppConfig> = {}): { app: Express; db: InMemoryDatabase } {
  const db = new InMemoryDatabase();
  const config = testConfig(overrides);
  const app = createApp({
    config,
    logger: createLogger(config.logLevel),
    passwordHasher: fastHasher,
    repositories: {
      users: new InMemoryUserRepository(db),
      devices: new InMemoryDeviceRepository(db),
      sessions: new InMemorySessionRepository(db),
      envelopes: new InMemoryKeyEnvelopeRepository(db),
      sync: new InMemorySyncRepository(db),
    },
  });
  return { app, db };
}

export interface TestSession {
  userId: string;
  deviceId: string;
  accessToken: string;
  refreshToken: string;
}

export async function registerUser(
  app: Express,
  email = `user-${randomUUID()}@example.com`,
  platform: 'android' | 'windows' = 'windows',
): Promise<TestSession & { email: string }> {
  const res = await request(app)
    .post('/api/v1/auth/register')
    .send({ email, password: ACCOUNT_PASSWORD, device: { name: 'Teste', platform } })
    .expect(201);
  return { email, ...(res.body as TestSession) };
}

export function bearer(session: { accessToken: string }): [string, string] {
  return ['Authorization', `Bearer ${session.accessToken}`];
}

/** Payload cifrado sintético (o servidor não interpreta o conteúdo). */
export function fakeCiphertext(): { encryptedData: string; nonce: string } {
  return {
    encryptedData: randomBytes(64).toString('base64'),
    nonce: randomBytes(12).toString('base64'),
  };
}

export function fakeEnvelope() {
  return {
    formatVersion: 1,
    kdf: {
      algorithm: 'argon2id',
      memoryKiB: 65536,
      iterations: 3,
      parallelism: 4,
      salt: randomBytes(16).toString('base64'),
    },
    wrappedKey: {
      nonce: randomBytes(12).toString('base64'),
      ciphertext: randomBytes(48).toString('base64'),
    },
    createdAt: new Date().toISOString(),
  };
}

import { randomUUID } from 'node:crypto';

import {
  EmailAlreadyRegisteredError,
  type DeviceRecord,
  type DeviceRepository,
  type RefreshTokenRecord,
  type SessionRecord,
  type SessionRepository,
  type UserRecord,
  type UserRepository,
} from '../../src/auth/auth.ports.js';
import type {
  AppliedChangeRecord,
  StoredItem,
  SyncRepository,
  SyncTransaction,
} from '../../src/sync/sync.ports.js';
import type {
  KeyEnvelopeRepository,
  PutEnvelopeResult,
  StoredKeyEnvelope,
} from '../../src/vault/vault.ports.js';
import type { KeyEnvelope } from '../../src/vault/vault.schemas.js';

interface StoredUser extends UserRecord {
  revisionCounter: number;
}

interface StoredSession {
  id: string;
  userId: string;
  deviceId: string;
  revokedAt: Date | null;
  revokedReason: string | null;
}

interface StoredRefreshToken {
  id: string;
  sessionId: string;
  tokenHash: string;
  expiresAt: Date;
  consumedAt: Date | null;
}

/** Banco em memória com a mesma semântica dos repositórios Prisma. */
export class InMemoryDatabase {
  readonly users = new Map<string, StoredUser>();
  readonly devices = new Map<string, DeviceRecord>();
  readonly sessions = new Map<string, StoredSession>();
  readonly refreshTokens = new Map<string, StoredRefreshToken>();
  readonly envelopes = new Map<string, StoredKeyEnvelope>();
  readonly items = new Map<string, StoredItem>();
  readonly appliedChanges = new Map<string, AppliedChangeRecord>();
  private readonly locks = new Map<string, Promise<void>>();

  async withLock<T>(key: string, work: () => Promise<T>): Promise<T> {
    const previous = this.locks.get(key) ?? Promise.resolve();
    let release!: () => void;
    const current = new Promise<void>((resolve) => (release = resolve));
    this.locks.set(key, previous.then(() => current));
    await previous;
    try {
      return await work();
    } finally {
      release();
    }
  }

  sessionRecord(session: StoredSession): SessionRecord {
    return {
      id: session.id,
      userId: session.userId,
      deviceId: session.deviceId,
      revokedAt: session.revokedAt,
      deviceRevokedAt: this.devices.get(session.deviceId)?.revokedAt ?? null,
    };
  }
}

export class InMemoryUserRepository implements UserRepository {
  constructor(private readonly db: InMemoryDatabase) {}

  async findByEmail(email: string): Promise<UserRecord | null> {
    const user = [...this.db.users.values()].find((u) => u.email === email);
    return user ? { id: user.id, email: user.email, passwordHash: user.passwordHash } : null;
  }

  async create(data: { email: string; passwordHash: string }): Promise<UserRecord> {
    if (await this.findByEmail(data.email)) throw new EmailAlreadyRegisteredError();
    const user = { id: randomUUID(), revisionCounter: 0, ...data };
    this.db.users.set(user.id, user);
    return { id: user.id, email: user.email, passwordHash: user.passwordHash };
  }

  async updatePasswordHash(userId: string, passwordHash: string): Promise<void> {
    const user = this.db.users.get(userId);
    if (user) user.passwordHash = passwordHash;
  }
}

export class InMemoryDeviceRepository implements DeviceRepository {
  constructor(private readonly db: InMemoryDatabase) {}

  async create(data: { userId: string; name: string; platform: string }): Promise<DeviceRecord> {
    const now = new Date();
    const device: DeviceRecord = {
      id: randomUUID(),
      ...data,
      createdAt: now,
      lastSeenAt: now,
      revokedAt: null,
    };
    this.db.devices.set(device.id, device);
    return { ...device };
  }

  async findForUser(userId: string, deviceId: string): Promise<DeviceRecord | null> {
    const device = this.db.devices.get(deviceId);
    return device && device.userId === userId ? { ...device } : null;
  }

  async listForUser(userId: string): Promise<DeviceRecord[]> {
    return [...this.db.devices.values()].filter((d) => d.userId === userId).map((d) => ({ ...d }));
  }

  async touch(deviceId: string, at: Date): Promise<void> {
    const device = this.db.devices.get(deviceId);
    if (device) device.lastSeenAt = at;
  }

  async revoke(userId: string, deviceId: string, at: Date): Promise<boolean> {
    const device = this.db.devices.get(deviceId);
    if (!device || device.userId !== userId || device.revokedAt) return false;
    device.revokedAt = at;
    return true;
  }
}

export class InMemorySessionRepository implements SessionRepository {
  constructor(private readonly db: InMemoryDatabase) {}

  async create(data: {
    userId: string;
    deviceId: string;
    refreshTokenHash: string;
    refreshExpiresAt: Date;
  }): Promise<SessionRecord> {
    const session: StoredSession = {
      id: randomUUID(),
      userId: data.userId,
      deviceId: data.deviceId,
      revokedAt: null,
      revokedReason: null,
    };
    this.db.sessions.set(session.id, session);
    this.addToken(session.id, data.refreshTokenHash, data.refreshExpiresAt);
    return this.db.sessionRecord(session);
  }

  async findById(sessionId: string): Promise<SessionRecord | null> {
    const session = this.db.sessions.get(sessionId);
    return session ? this.db.sessionRecord(session) : null;
  }

  async findRefreshToken(tokenHash: string): Promise<RefreshTokenRecord | null> {
    const token = [...this.db.refreshTokens.values()].find((t) => t.tokenHash === tokenHash);
    const session = token && this.db.sessions.get(token.sessionId);
    if (!token || !session) return null;
    return {
      id: token.id,
      sessionId: token.sessionId,
      expiresAt: token.expiresAt,
      consumedAt: token.consumedAt,
      session: this.db.sessionRecord(session),
    };
  }

  async rotateRefreshToken(data: {
    tokenId: string;
    sessionId: string;
    newTokenHash: string;
    newExpiresAt: Date;
    at: Date;
  }): Promise<boolean> {
    const token = this.db.refreshTokens.get(data.tokenId);
    if (!token || token.consumedAt) return false;
    token.consumedAt = data.at;
    this.addToken(data.sessionId, data.newTokenHash, data.newExpiresAt);
    return true;
  }

  async revoke(sessionId: string, reason: string, at: Date): Promise<void> {
    const session = this.db.sessions.get(sessionId);
    if (session && !session.revokedAt) {
      session.revokedAt = at;
      session.revokedReason = reason;
    }
  }

  async revokeAllForDevice(deviceId: string, reason: string, at: Date): Promise<void> {
    for (const session of this.db.sessions.values()) {
      if (session.deviceId === deviceId) await this.revoke(session.id, reason, at);
    }
  }

  private addToken(sessionId: string, tokenHash: string, expiresAt: Date): void {
    const id = randomUUID();
    this.db.refreshTokens.set(id, { id, sessionId, tokenHash, expiresAt, consumedAt: null });
  }
}

export class InMemoryKeyEnvelopeRepository implements KeyEnvelopeRepository {
  constructor(private readonly db: InMemoryDatabase) {}

  async get(userId: string): Promise<StoredKeyEnvelope | null> {
    return this.db.envelopes.get(userId) ?? null;
  }

  async put(userId: string, envelope: KeyEnvelope, expectedVersion: number): Promise<PutEnvelopeResult> {
    const current = this.db.envelopes.get(userId) ?? null;
    if ((current?.version ?? 0) !== expectedVersion) return { status: 'conflict', current };
    const version = expectedVersion + 1;
    this.db.envelopes.set(userId, { envelope, version, updatedAt: new Date() });
    return { status: 'ok', version };
  }
}

export class InMemorySyncRepository implements SyncRepository {
  constructor(private readonly db: InMemoryDatabase) {}

  withUserLock<T>(userId: string, work: (tx: SyncTransaction) => Promise<T>): Promise<T> {
    const db = this.db;
    const key = (id: string) => `${userId}:${id}`;
    return db.withLock(userId, () =>
      work({
        async findItem(itemId) {
          const item = db.items.get(key(itemId));
          return item ? { ...item } : null;
        },
        async findAppliedChange(changeId) {
          return db.appliedChanges.get(key(changeId)) ?? null;
        },
        async nextRevision() {
          const user = db.users.get(userId);
          if (!user) throw new Error('usuário inexistente');
          user.revisionCounter += 1;
          return user.revisionCounter;
        },
        async saveItem(item) {
          db.items.set(key(item.id), { ...item });
        },
        async recordAppliedChange(change) {
          db.appliedChanges.set(key(change.changeId), { ...change });
        },
      }),
    );
  }

  async listChangedSince(userId: string, since: number, limit: number): Promise<StoredItem[]> {
    return [...this.db.items.values()]
      .filter((item) => item.userId === userId && item.revision > since)
      .sort((a, b) => a.revision - b.revision)
      .slice(0, limit)
      .map((item) => ({ ...item }));
  }

  async latestRevision(userId: string): Promise<number> {
    return this.db.users.get(userId)?.revisionCounter ?? 0;
  }
}

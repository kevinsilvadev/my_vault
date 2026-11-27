import { Prisma, type PrismaClient } from '@prisma/client';

import {
  EmailAlreadyRegisteredError,
  type DeviceRecord,
  type DeviceRepository,
  type RefreshTokenRecord,
  type SessionRecord,
  type SessionRepository,
  type UserRecord,
  type UserRepository,
} from '../../auth/auth.ports.js';
import type {
  AppliedChangeRecord,
  StoredItem,
  SyncRepository,
  SyncTransaction,
} from '../../sync/sync.ports.js';
import type { KeyEnvelopeRepository, PutEnvelopeResult } from '../../vault/vault.ports.js';
import { KeyEnvelopeSchema, type KeyEnvelope } from '../../vault/vault.schemas.js';

type Tx = Prisma.TransactionClient;

const isUniqueViolation = (error: unknown): boolean =>
  error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002';

export class PrismaUserRepository implements UserRepository {
  constructor(private readonly db: PrismaClient) {}

  async findByEmail(email: string): Promise<UserRecord | null> {
    return this.db.user.findUnique({
      where: { email },
      select: { id: true, email: true, passwordHash: true },
    });
  }

  async create(data: { email: string; passwordHash: string }): Promise<UserRecord> {
    try {
      return await this.db.user.create({
        data,
        select: { id: true, email: true, passwordHash: true },
      });
    } catch (error) {
      if (isUniqueViolation(error)) throw new EmailAlreadyRegisteredError();
      throw error;
    }
  }

  async updatePasswordHash(userId: string, passwordHash: string): Promise<void> {
    await this.db.user.update({ where: { id: userId }, data: { passwordHash } });
  }
}

export class PrismaDeviceRepository implements DeviceRepository {
  constructor(private readonly db: PrismaClient) {}

  create(data: { userId: string; name: string; platform: string }): Promise<DeviceRecord> {
    return this.db.device.create({ data });
  }

  findForUser(userId: string, deviceId: string): Promise<DeviceRecord | null> {
    return this.db.device.findFirst({ where: { id: deviceId, userId } });
  }

  listForUser(userId: string): Promise<DeviceRecord[]> {
    return this.db.device.findMany({ where: { userId }, orderBy: { createdAt: 'asc' } });
  }

  async touch(deviceId: string, at: Date): Promise<void> {
    await this.db.device.update({ where: { id: deviceId }, data: { lastSeenAt: at } });
  }

  async revoke(userId: string, deviceId: string, at: Date): Promise<boolean> {
    const { count } = await this.db.device.updateMany({
      where: { id: deviceId, userId, revokedAt: null },
      data: { revokedAt: at },
    });
    return count === 1;
  }
}

const sessionSelect = {
  id: true,
  userId: true,
  deviceId: true,
  revokedAt: true,
  device: { select: { revokedAt: true } },
} as const;

type SessionRow = Prisma.SessionGetPayload<{ select: typeof sessionSelect }>;

const toSessionRecord = (row: SessionRow): SessionRecord => ({
  id: row.id,
  userId: row.userId,
  deviceId: row.deviceId,
  revokedAt: row.revokedAt,
  deviceRevokedAt: row.device.revokedAt,
});

export class PrismaSessionRepository implements SessionRepository {
  constructor(private readonly db: PrismaClient) {}

  async create(data: {
    userId: string;
    deviceId: string;
    refreshTokenHash: string;
    refreshExpiresAt: Date;
  }): Promise<SessionRecord> {
    const row = await this.db.session.create({
      data: {
        userId: data.userId,
        deviceId: data.deviceId,
        refreshTokens: {
          create: { tokenHash: data.refreshTokenHash, expiresAt: data.refreshExpiresAt },
        },
      },
      select: sessionSelect,
    });
    return toSessionRecord(row);
  }

  async findById(sessionId: string): Promise<SessionRecord | null> {
    const row = await this.db.session.findUnique({
      where: { id: sessionId },
      select: sessionSelect,
    });
    return row ? toSessionRecord(row) : null;
  }

  async findRefreshToken(tokenHash: string): Promise<RefreshTokenRecord | null> {
    const row = await this.db.refreshToken.findUnique({
      where: { tokenHash },
      select: {
        id: true,
        sessionId: true,
        expiresAt: true,
        consumedAt: true,
        session: { select: sessionSelect },
      },
    });
    if (!row) return null;
    return {
      id: row.id,
      sessionId: row.sessionId,
      expiresAt: row.expiresAt,
      consumedAt: row.consumedAt,
      session: toSessionRecord(row.session),
    };
  }

  async rotateRefreshToken(data: {
    tokenId: string;
    sessionId: string;
    newTokenHash: string;
    newExpiresAt: Date;
    at: Date;
  }): Promise<boolean> {
    return this.db.$transaction(async (tx) => {
      // Consumo condicional: só uma requisição concorrente vence.
      const { count } = await tx.refreshToken.updateMany({
        where: { id: data.tokenId, consumedAt: null },
        data: { consumedAt: data.at },
      });
      if (count !== 1) return false;
      await tx.refreshToken.create({
        data: {
          sessionId: data.sessionId,
          tokenHash: data.newTokenHash,
          expiresAt: data.newExpiresAt,
        },
      });
      return true;
    });
  }

  async revoke(sessionId: string, reason: string, at: Date): Promise<void> {
    await this.db.session.updateMany({
      where: { id: sessionId, revokedAt: null },
      data: { revokedAt: at, revokedReason: reason },
    });
  }

  async revokeAllForDevice(deviceId: string, reason: string, at: Date): Promise<void> {
    await this.db.session.updateMany({
      where: { deviceId, revokedAt: null },
      data: { revokedAt: at, revokedReason: reason },
    });
  }
}

export class PrismaKeyEnvelopeRepository implements KeyEnvelopeRepository {
  constructor(private readonly db: PrismaClient) {}

  async get(userId: string) {
    const row = await this.db.keyEnvelope.findUnique({ where: { userId } });
    if (!row) return null;
    return {
      envelope: KeyEnvelopeSchema.parse(row.envelope),
      version: row.version,
      updatedAt: row.updatedAt,
    };
  }

  async put(
    userId: string,
    value: KeyEnvelope,
    expectedVersion: number,
  ): Promise<PutEnvelopeResult> {
    const envelope: Prisma.InputJsonObject = value;
    if (expectedVersion === 0) {
      try {
        await this.db.keyEnvelope.create({ data: { userId, envelope, version: 1 } });
        return { status: 'ok', version: 1 };
      } catch (error) {
        if (isUniqueViolation(error)) return { status: 'conflict', current: await this.get(userId) };
        throw error;
      }
    }
    const { count } = await this.db.keyEnvelope.updateMany({
      where: { userId, version: expectedVersion },
      data: { envelope, version: { increment: 1 } },
    });
    if (count !== 1) return { status: 'conflict', current: await this.get(userId) };
    return { status: 'ok', version: expectedVersion + 1 };
  }
}

class PrismaSyncTransaction implements SyncTransaction {
  constructor(
    private readonly tx: Tx,
    private readonly userId: string,
  ) {}

  findItem(itemId: string): Promise<StoredItem | null> {
    return this.tx.vaultItem.findUnique({
      where: { userId_id: { userId: this.userId, id: itemId } },
    });
  }

  findAppliedChange(changeId: string): Promise<AppliedChangeRecord | null> {
    return this.tx.appliedChange.findUnique({
      where: { userId_changeId: { userId: this.userId, changeId } },
      select: { changeId: true, itemId: true, version: true, revision: true },
    });
  }

  async nextRevision(): Promise<number> {
    const user = await this.tx.user.update({
      where: { id: this.userId },
      data: { revisionCounter: { increment: 1 } },
      select: { revisionCounter: true },
    });
    return user.revisionCounter;
  }

  async saveItem(item: StoredItem): Promise<void> {
    const { userId, id, ...fields } = item;
    await this.tx.vaultItem.upsert({
      where: { userId_id: { userId, id } },
      create: { userId, id, ...fields },
      update: {
        encryptedData: fields.encryptedData,
        nonce: fields.nonce,
        cryptoVersion: fields.cryptoVersion,
        version: fields.version,
        revision: fields.revision,
        deleted: fields.deleted,
        updatedAt: fields.updatedAt,
      },
    });
  }

  async recordAppliedChange(change: AppliedChangeRecord): Promise<void> {
    await this.tx.appliedChange.create({ data: { userId: this.userId, ...change } });
  }
}

export class PrismaSyncRepository implements SyncRepository {
  constructor(private readonly db: PrismaClient) {}

  withUserLock<T>(userId: string, work: (tx: SyncTransaction) => Promise<T>): Promise<T> {
    return this.db.$transaction(
      async (tx) => {
        // Serializa alterações do mesmo usuário; revisões ficam monotônicas e
        // nenhuma leitura de `pull` vê uma revisão maior antes de uma menor.
        await tx.$queryRaw`SELECT id FROM users WHERE id = ${userId}::uuid FOR UPDATE`;
        return work(new PrismaSyncTransaction(tx, userId));
      },
      { timeout: 10_000 },
    );
  }

  listChangedSince(userId: string, since: number, limit: number): Promise<StoredItem[]> {
    return this.db.vaultItem.findMany({
      where: { userId, revision: { gt: since } },
      orderBy: { revision: 'asc' },
      take: limit,
    });
  }

  async latestRevision(userId: string): Promise<number> {
    const user = await this.db.user.findUnique({
      where: { id: userId },
      select: { revisionCounter: true },
    });
    return user?.revisionCounter ?? 0;
  }
}

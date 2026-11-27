/**
 * Portas de persistência do módulo de autenticação. Implementadas com Prisma
 * em produção (`infra/prisma`) e em memória nos testes.
 */

export interface UserRecord {
  id: string;
  email: string;
  passwordHash: string;
}

export interface DeviceRecord {
  id: string;
  userId: string;
  name: string;
  platform: string;
  createdAt: Date;
  lastSeenAt: Date;
  revokedAt: Date | null;
}

export interface SessionRecord {
  id: string;
  userId: string;
  deviceId: string;
  revokedAt: Date | null;
  deviceRevokedAt: Date | null;
}

export interface RefreshTokenRecord {
  id: string;
  sessionId: string;
  expiresAt: Date;
  consumedAt: Date | null;
  session: SessionRecord;
}

export interface UserRepository {
  findByEmail(email: string): Promise<UserRecord | null>;
  /** Lança `EmailAlreadyRegisteredError` se o e-mail já existir. */
  create(data: { email: string; passwordHash: string }): Promise<UserRecord>;
  updatePasswordHash(userId: string, passwordHash: string): Promise<void>;
}

export interface DeviceRepository {
  create(data: { userId: string; name: string; platform: string }): Promise<DeviceRecord>;
  findForUser(userId: string, deviceId: string): Promise<DeviceRecord | null>;
  listForUser(userId: string): Promise<DeviceRecord[]>;
  touch(deviceId: string, at: Date): Promise<void>;
  /** Retorna `false` se o dispositivo não pertence ao usuário. */
  revoke(userId: string, deviceId: string, at: Date): Promise<boolean>;
}

export interface SessionRepository {
  create(data: {
    userId: string;
    deviceId: string;
    refreshTokenHash: string;
    refreshExpiresAt: Date;
  }): Promise<SessionRecord>;
  findById(sessionId: string): Promise<SessionRecord | null>;
  findRefreshToken(tokenHash: string): Promise<RefreshTokenRecord | null>;
  /**
   * Consome o token atual e emite o próximo, atomicamente. Retorna `false`
   * se o token já tiver sido consumido por outra requisição.
   */
  rotateRefreshToken(data: {
    tokenId: string;
    sessionId: string;
    newTokenHash: string;
    newExpiresAt: Date;
    at: Date;
  }): Promise<boolean>;
  revoke(sessionId: string, reason: string, at: Date): Promise<void>;
  revokeAllForDevice(deviceId: string, reason: string, at: Date): Promise<void>;
}

export class EmailAlreadyRegisteredError extends Error {
  constructor() {
    super('E-mail já cadastrado.');
    this.name = 'EmailAlreadyRegisteredError';
  }
}

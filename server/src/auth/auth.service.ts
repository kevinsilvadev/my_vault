import type { Clock } from '../shared/clock.js';
import { randomToken, sha256Hex } from '../shared/crypto.js';
import { ConflictError, ForbiddenError, NotFoundError, UnauthorizedError } from '../shared/errors.js';
import type { AccessTokenService } from './access-token.service.js';
import {
  EmailAlreadyRegisteredError,
  type DeviceRecord,
  type DeviceRepository,
  type SessionRepository,
  type UserRecord,
  type UserRepository,
} from './auth.ports.js';
import type { PasswordHasher } from './password-hasher.js';

export interface AuthContext {
  userId: string;
  sessionId: string;
  deviceId: string;
}

export interface DeviceInput {
  name: string;
  platform: string;
  /** Identificador de um dispositivo já autorizado, para reutilizá-lo. */
  id?: string | undefined;
}

export interface AuthTokens {
  userId: string;
  deviceId: string;
  accessToken: string;
  accessTokenExpiresIn: number;
  refreshToken: string;
}

export interface DeviceView {
  id: string;
  name: string;
  platform: string;
  createdAt: string;
  lastSeenAt: string;
  current: boolean;
}

export interface AuthServiceDeps {
  users: UserRepository;
  devices: DeviceRepository;
  sessions: SessionRepository;
  hasher: PasswordHasher;
  accessTokens: AccessTokenService;
  refreshTokenTtlDays: number;
  allowRegistration: boolean;
  clock: Clock;
}

const invalidCredentials = () =>
  new UnauthorizedError('INVALID_CREDENTIALS', 'E-mail ou senha inválidos.');
const invalidRefreshToken = () =>
  new UnauthorizedError('INVALID_REFRESH_TOKEN', 'Sessão expirada. Entre novamente.');

/**
 * Autenticação da conta/dispositivo — separada da senha mestre.
 *
 * Autorizar a sincronização não desbloqueia o cofre: o servidor nunca recebe a
 * senha mestre nem a chave do cofre.
 */
export class AuthService {
  constructor(private readonly deps: AuthServiceDeps) {}

  async register(input: { email: string; password: string; device: DeviceInput }): Promise<AuthTokens> {
    if (!this.deps.allowRegistration) {
      throw new ForbiddenError('REGISTRATION_DISABLED', 'O cadastro de novas contas está desativado.');
    }
    const passwordHash = await this.deps.hasher.hash(input.password);
    let user: UserRecord;
    try {
      user = await this.deps.users.create({ email: input.email, passwordHash });
    } catch (error) {
      if (error instanceof EmailAlreadyRegisteredError) {
        throw new ConflictError('EMAIL_UNAVAILABLE', 'Não foi possível criar a conta com este e-mail.');
      }
      throw error;
    }
    const device = await this.deps.devices.create({
      userId: user.id,
      name: input.device.name,
      platform: input.device.platform,
    });
    return this.startSession(user.id, device.id);
  }

  async login(input: { email: string; password: string; device: DeviceInput }): Promise<AuthTokens> {
    const user = await this.deps.users.findByEmail(input.email);
    if (!user) {
      await this.deps.hasher.verifyDummy(input.password);
      throw invalidCredentials();
    }
    const valid = await this.deps.hasher.verify(input.password, user.passwordHash);
    if (!valid) throw invalidCredentials();

    if (this.deps.hasher.needsRehash(user.passwordHash)) {
      await this.deps.users.updatePasswordHash(user.id, await this.deps.hasher.hash(input.password));
    }

    const device = await this.resolveDevice(user.id, input.device);
    return this.startSession(user.id, device.id);
  }

  /**
   * Rotaciona o refresh token. Reapresentar um token já consumido indica
   * roubo/replay: a sessão inteira é revogada.
   */
  async refresh(refreshToken: string): Promise<AuthTokens> {
    const now = this.deps.clock();
    const record = await this.deps.sessions.findRefreshToken(sha256Hex(refreshToken));
    if (!record) throw invalidRefreshToken();
    const { session } = record;

    if (session.revokedAt || session.deviceRevokedAt) throw invalidRefreshToken();
    if (record.consumedAt) {
      await this.deps.sessions.revoke(session.id, 'refresh_token_reuse', now);
      throw invalidRefreshToken();
    }
    if (record.expiresAt <= now) throw invalidRefreshToken();

    const nextToken = randomToken();
    const rotated = await this.deps.sessions.rotateRefreshToken({
      tokenId: record.id,
      sessionId: session.id,
      newTokenHash: sha256Hex(nextToken),
      newExpiresAt: this.refreshExpiry(now),
      at: now,
    });
    if (!rotated) {
      // Outra requisição consumiu o mesmo token ao mesmo tempo.
      await this.deps.sessions.revoke(session.id, 'refresh_token_reuse', now);
      throw invalidRefreshToken();
    }
    await this.deps.devices.touch(session.deviceId, now);
    return this.tokensFor(session.userId, session.id, session.deviceId, nextToken);
  }

  async logout(auth: AuthContext): Promise<void> {
    await this.deps.sessions.revoke(auth.sessionId, 'logout', this.deps.clock());
  }

  /** Valida o token de acesso e confirma que a sessão e o dispositivo seguem ativos. */
  async authenticate(accessToken: string): Promise<AuthContext> {
    const claims = await this.deps.accessTokens.verify(accessToken);
    if (!claims) throw new UnauthorizedError();
    const session = await this.deps.sessions.findById(claims.sessionId);
    if (
      !session ||
      session.userId !== claims.userId ||
      session.deviceId !== claims.deviceId ||
      session.revokedAt ||
      session.deviceRevokedAt
    ) {
      throw new UnauthorizedError();
    }
    return claims;
  }

  async listDevices(auth: AuthContext): Promise<DeviceView[]> {
    const devices = await this.deps.devices.listForUser(auth.userId);
    return devices
      .filter((device) => !device.revokedAt)
      .map((device) => ({
        id: device.id,
        name: device.name,
        platform: device.platform,
        createdAt: device.createdAt.toISOString(),
        lastSeenAt: device.lastSeenAt.toISOString(),
        current: device.id === auth.deviceId,
      }));
  }

  /** Revoga um dispositivo (ex.: perdido) e todas as suas sessões. */
  async revokeDevice(auth: AuthContext, deviceId: string): Promise<void> {
    const now = this.deps.clock();
    const revoked = await this.deps.devices.revoke(auth.userId, deviceId, now);
    // Mesmo erro para "não existe" e "é de outro usuário".
    if (!revoked) throw new NotFoundError('Dispositivo não encontrado.');
    await this.deps.sessions.revokeAllForDevice(deviceId, 'device_revoked', now);
  }

  private async resolveDevice(userId: string, input: DeviceInput): Promise<DeviceRecord> {
    if (input.id) {
      const existing = await this.deps.devices.findForUser(userId, input.id);
      if (existing && !existing.revokedAt) return existing;
    }
    return this.deps.devices.create({ userId, name: input.name, platform: input.platform });
  }

  private async startSession(userId: string, deviceId: string): Promise<AuthTokens> {
    const now = this.deps.clock();
    const refreshToken = randomToken();
    const session = await this.deps.sessions.create({
      userId,
      deviceId,
      refreshTokenHash: sha256Hex(refreshToken),
      refreshExpiresAt: this.refreshExpiry(now),
    });
    await this.deps.devices.touch(deviceId, now);
    return this.tokensFor(userId, session.id, deviceId, refreshToken);
  }

  private async tokensFor(
    userId: string,
    sessionId: string,
    deviceId: string,
    refreshToken: string,
  ): Promise<AuthTokens> {
    const accessToken = await this.deps.accessTokens.issue({ userId, sessionId, deviceId });
    return {
      userId,
      deviceId,
      accessToken,
      accessTokenExpiresIn: this.deps.accessTokens.ttlSeconds,
      refreshToken,
    };
  }

  private refreshExpiry(now: Date): Date {
    return new Date(now.getTime() + this.deps.refreshTokenTtlDays * 24 * 60 * 60 * 1000);
  }
}

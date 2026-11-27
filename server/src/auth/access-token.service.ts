import { jwtVerify, SignJWT } from 'jose';
import { z } from 'zod';

const ISSUER = 'myvault-api';
const AUDIENCE = 'myvault-clients';

const ClaimsSchema = z.object({
  sub: z.uuid(),
  sid: z.uuid(),
  did: z.uuid(),
});

export interface AccessTokenClaims {
  userId: string;
  sessionId: string;
  deviceId: string;
}

/** Tokens de acesso JWT (HS256) de curta duração. */
export class AccessTokenService {
  private readonly key: Uint8Array;

  constructor(
    secret: string,
    readonly ttlSeconds: number,
  ) {
    this.key = new TextEncoder().encode(secret);
  }

  issue(claims: AccessTokenClaims): Promise<string> {
    return new SignJWT({ sid: claims.sessionId, did: claims.deviceId })
      .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
      .setSubject(claims.userId)
      .setIssuer(ISSUER)
      .setAudience(AUDIENCE)
      .setIssuedAt()
      .setExpirationTime(`${this.ttlSeconds}s`)
      .sign(this.key);
  }

  /** Retorna `null` para qualquer token inválido, expirado ou adulterado. */
  async verify(token: string): Promise<AccessTokenClaims | null> {
    try {
      const { payload } = await jwtVerify(token, this.key, {
        algorithms: ['HS256'],
        issuer: ISSUER,
        audience: AUDIENCE,
      });
      const claims = ClaimsSchema.safeParse(payload);
      if (!claims.success) return null;
      return {
        userId: claims.data.sub,
        sessionId: claims.data.sid,
        deviceId: claims.data.did,
      };
    } catch {
      return null;
    }
  }
}

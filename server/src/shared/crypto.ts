import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';

/** Token opaco de 256 bits, seguro para URLs. */
export function randomToken(bytes = 32): string {
  return randomBytes(bytes).toString('base64url');
}

/** SHA-256 em hex. Usado para armazenar refresh tokens (alta entropia). */
export function sha256Hex(value: string): string {
  return createHash('sha256').update(value, 'utf8').digest('hex');
}

export function safeEqual(a: Buffer, b: Buffer): boolean {
  return a.length === b.length && timingSafeEqual(a, b);
}

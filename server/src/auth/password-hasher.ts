import { randomBytes, scrypt, type ScryptOptions } from 'node:crypto';

import { safeEqual } from '../shared/crypto.js';

export interface ScryptParams {
  /** Custo de CPU/memória (potência de 2). */
  N: number;
  r: number;
  p: number;
}

/**
 * Parâmetros recomendados pela OWASP para scrypt (N=2^17, r=8, p=1), ~128 MiB.
 *
 * Esta é a senha da CONTA, usada só para autenticar a sincronização. A senha
 * mestre nunca chega ao servidor.
 */
export const DEFAULT_SCRYPT_PARAMS: ScryptParams = { N: 2 ** 17, r: 8, p: 1 };

const KEY_LENGTH = 32;
const SALT_LENGTH = 16;

function deriveScrypt(password: string, salt: Buffer, params: ScryptParams): Promise<Buffer> {
  const options: ScryptOptions = {
    N: params.N,
    r: params.r,
    p: params.p,
    maxmem: 128 * params.N * params.r * 2,
  };
  return new Promise((resolve, reject) => {
    scrypt(password.normalize('NFC'), salt, KEY_LENGTH, options, (error, key) => {
      if (error) reject(error);
      else resolve(key);
    });
  });
}

/**
 * Hash de senha com scrypt (embutido no Node, sem dependência nativa).
 * Formato: `scrypt$N$r$p$salt(base64)$hash(base64)`.
 */
export class PasswordHasher {
  private readonly dummyHash: Promise<string>;

  constructor(private readonly params: ScryptParams = DEFAULT_SCRYPT_PARAMS) {
    // Usado para equalizar o tempo de resposta quando o e-mail não existe.
    this.dummyHash = this.hash(randomBytes(16).toString('hex'));
  }

  async hash(password: string): Promise<string> {
    const salt = randomBytes(SALT_LENGTH);
    const key = await deriveScrypt(password, salt, this.params);
    const { N, r, p } = this.params;
    return ['scrypt', N, r, p, salt.toString('base64'), key.toString('base64')].join('$');
  }

  async verify(password: string, encoded: string): Promise<boolean> {
    const parts = encoded.split('$');
    if (parts.length !== 6 || parts[0] !== 'scrypt') return false;
    const [, n, r, p, salt, hash] = parts as [string, string, string, string, string, string];
    const params = { N: Number(n), r: Number(r), p: Number(p) };
    if (![params.N, params.r, params.p].every(Number.isSafeInteger)) return false;
    const expected = Buffer.from(hash, 'base64');
    const actual = await deriveScrypt(password, Buffer.from(salt, 'base64'), params);
    return safeEqual(actual, expected);
  }

  /** Executa um hash descartável para não revelar, pelo tempo, se a conta existe. */
  async verifyDummy(password: string): Promise<void> {
    await this.verify(password, await this.dummyHash);
  }

  needsRehash(encoded: string): boolean {
    const [, n, r, p] = encoded.split('$');
    return (
      Number(n) !== this.params.N || Number(r) !== this.params.r || Number(p) !== this.params.p
    );
  }
}

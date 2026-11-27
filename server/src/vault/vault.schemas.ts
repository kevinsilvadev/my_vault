import { z } from 'zod';

/** Base64 que decodifica para exatamente `bytes` bytes. */
export const base64OfLength = (bytes: number) => z.base64().length(Math.ceil(bytes / 3) * 4);

/**
 * Formato do envelope da chave do cofre (ver packages/vault_core,
 * `VaultKeyEnvelope`). O servidor valida apenas a estrutura e os limites dos
 * parâmetros; o conteúdo é opaco e cifrado.
 */
export const KeyEnvelopeSchema = z
  .object({
    formatVersion: z.literal(1),
    kdf: z
      .object({
        algorithm: z.literal('argon2id'),
        // Piso OWASP e teto anti-DoS, iguais aos do cliente.
        memoryKiB: z.number().int().min(19_456).max(1_048_576),
        iterations: z.number().int().min(2).max(20),
        parallelism: z.number().int().min(1).max(16),
        salt: z.base64().min(24).max(88),
      })
      .strict(),
    wrappedKey: z
      .object({
        nonce: base64OfLength(12),
        // 32 bytes de chave + 16 de tag.
        ciphertext: base64OfLength(48),
      })
      .strict(),
    createdAt: z.string().max(64),
  })
  .strict();

export type KeyEnvelope = z.infer<typeof KeyEnvelopeSchema>;

export const PutKeyEnvelopeSchema = z
  .object({
    envelope: KeyEnvelopeSchema,
    /** Versão atual conhecida pelo cliente (0 = ainda não existe). */
    baseVersion: z.number().int().min(0),
  })
  .strict();

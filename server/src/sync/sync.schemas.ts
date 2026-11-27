import { z } from 'zod';

import { base64OfLength } from '../vault/vault.schemas.js';

/** Limite de tamanho de um registro cifrado (~64 KiB de ciphertext). */
export const MAX_ENCRYPTED_DATA_LENGTH = 87_384;
export const MAX_CHANGES_PER_PUSH = 100;
export const MAX_PULL_LIMIT = 500;

const ChangeBase = {
  changeId: z.uuid(),
  itemId: z.uuid(),
  baseVersion: z.number().int().min(0),
};

const UpsertChangeSchema = z
  .object({
    ...ChangeBase,
    operation: z.literal('upsert'),
    cryptoVersion: z.number().int().min(1).max(1000),
    // Pelo menos 1 byte de conteúdo + 16 de tag.
    encryptedData: z.base64().min(24).max(MAX_ENCRYPTED_DATA_LENGTH),
    nonce: base64OfLength(12),
  })
  .strict();

const DeleteChangeSchema = z
  .object({
    ...ChangeBase,
    operation: z.literal('delete'),
  })
  .strict();

export const PushChangeSchema = z.discriminatedUnion('operation', [
  UpsertChangeSchema,
  DeleteChangeSchema,
]);

export type PushChange = z.infer<typeof PushChangeSchema>;

export const PushRequestSchema = z
  .object({
    changes: z.array(PushChangeSchema).min(1).max(MAX_CHANGES_PER_PUSH),
  })
  .strict()
  .refine(
    ({ changes }) => new Set(changes.map((c) => c.changeId)).size === changes.length,
    { message: 'changeId duplicado no mesmo envio.', path: ['changes'] },
  );

export const PullQuerySchema = z.object({
  since: z.coerce.number().int().min(0).default(0),
  limit: z.coerce.number().int().min(1).max(MAX_PULL_LIMIT).default(200),
});

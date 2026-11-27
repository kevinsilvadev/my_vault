import type { z } from 'zod';

import { ValidationError } from './errors.js';

/** Valida `input` com `schema` ou lança `ValidationError` (HTTP 400). */
export function parseOrThrow<T extends z.ZodType>(schema: T, input: unknown): z.output<T> {
  const result = schema.safeParse(input);
  if (!result.success) throw ValidationError.fromZod(result.error);
  return result.data;
}

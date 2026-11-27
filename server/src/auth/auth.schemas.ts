import { z } from 'zod';

export const EmailSchema = z
  .string()
  .trim()
  .max(254)
  .pipe(z.email('E-mail inválido.'))
  .transform((email) => email.toLowerCase());

/** Senha da conta (não é a senha mestre). */
const AccountPasswordSchema = z
  .string()
  .min(12, 'A senha da conta deve ter pelo menos 12 caracteres.')
  .max(256, 'A senha da conta deve ter no máximo 256 caracteres.');

const DeviceSchema = z
  .object({
    id: z.uuid().optional(),
    name: z.string().trim().min(1).max(100),
    platform: z.enum(['android', 'windows', 'other']),
  })
  .strict();

export const RegisterSchema = z
  .object({ email: EmailSchema, password: AccountPasswordSchema, device: DeviceSchema })
  .strict();

export const LoginSchema = z
  .object({
    email: EmailSchema,
    // No login não aplicamos a política de tamanho mínimo, apenas limites.
    password: z.string().min(1).max(256),
    device: DeviceSchema,
  })
  .strict();

export const RefreshSchema = z
  .object({ refreshToken: z.string().min(20).max(200) })
  .strict();

export const DeviceIdParamsSchema = z.object({ deviceId: z.uuid() });

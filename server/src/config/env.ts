import { z } from 'zod';

const booleanString = z.enum(['true', 'false']).transform((value) => value === 'true');

const EnvSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),
  DATABASE_URL: z.string().min(1),
  JWT_SECRET: z.string().min(32, 'JWT_SECRET deve ter pelo menos 32 caracteres'),
  ACCESS_TOKEN_TTL_SECONDS: z.coerce.number().int().min(60).max(3600).default(900),
  REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().min(1).max(90).default(30),
  CORS_ORIGINS: z.string().default(''),
  TRUST_PROXY: z.string().default('false'),
  REQUIRE_HTTPS: booleanString.optional(),
  ALLOW_REGISTRATION: booleanString.default(true),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent']).default('info'),
});

export interface AppConfig {
  env: 'development' | 'test' | 'production';
  port: number;
  databaseUrl: string;
  jwtSecret: string;
  accessTokenTtlSeconds: number;
  refreshTokenTtlDays: number;
  corsOrigins: string[];
  trustProxy: boolean | number;
  requireHttps: boolean;
  allowRegistration: boolean;
  logLevel: string;
  rateLimit: {
    windowMs: number;
    /** Requisições por IP em rotas de autenticação. */
    authPerIp: number;
    /** Tentativas de login com falha por e-mail. */
    failedLoginsPerAccount: number;
    /** Requisições por IP no restante da API. */
    globalPerIp: number;
  };
}

function parseTrustProxy(raw: string): boolean | number {
  if (raw === 'true') return true;
  if (raw === 'false') return false;
  const hops = Number(raw);
  if (Number.isInteger(hops) && hops >= 0) return hops;
  throw new Error('TRUST_PROXY deve ser true, false ou um número de proxies');
}

/**
 * Lê e valida as variáveis de ambiente. Falha cedo, listando apenas os nomes
 * das variáveis inválidas (nunca os valores).
 */
export function loadConfig(source: NodeJS.ProcessEnv = process.env): AppConfig {
  const parsed = EnvSchema.safeParse(source);
  if (!parsed.success) {
    const fields = parsed.error.issues.map((issue) => issue.path.join('.')).join(', ');
    throw new Error(`Configuração inválida: ${fields}`);
  }
  const env = parsed.data;
  return {
    env: env.NODE_ENV,
    port: env.PORT,
    databaseUrl: env.DATABASE_URL,
    jwtSecret: env.JWT_SECRET,
    accessTokenTtlSeconds: env.ACCESS_TOKEN_TTL_SECONDS,
    refreshTokenTtlDays: env.REFRESH_TOKEN_TTL_DAYS,
    corsOrigins: env.CORS_ORIGINS.split(',')
      .map((origin) => origin.trim())
      .filter(Boolean),
    trustProxy: parseTrustProxy(env.TRUST_PROXY),
    requireHttps: env.REQUIRE_HTTPS ?? env.NODE_ENV === 'production',
    allowRegistration: env.ALLOW_REGISTRATION,
    logLevel: env.LOG_LEVEL,
    rateLimit: {
      windowMs: 15 * 60 * 1000,
      authPerIp: 30,
      failedLoginsPerAccount: 10,
      globalPerIp: 600,
    },
  };
}

import cors from 'cors';
import express, {
  type ErrorRequestHandler,
  type Express,
  type Request,
  type RequestHandler,
} from 'express';
import { rateLimit } from 'express-rate-limit';
import helmet from 'helmet';
import { pinoHttp } from 'pino-http';

import { AccessTokenService } from './auth/access-token.service.js';
import { requireAuth } from './auth/auth.middleware.js';
import type { DeviceRepository, SessionRepository, UserRepository } from './auth/auth.ports.js';
import { authRouter } from './auth/auth.routes.js';
import { AuthService } from './auth/auth.service.js';
import { PasswordHasher } from './auth/password-hasher.js';
import type { AppConfig } from './config/env.js';
import { systemClock, type Clock } from './shared/clock.js';
import { AppError } from './shared/errors.js';
import type { Logger } from './shared/logger.js';
import type { SyncRepository } from './sync/sync.ports.js';
import { syncRouter } from './sync/sync.routes.js';
import { SyncService } from './sync/sync.service.js';
import type { KeyEnvelopeRepository } from './vault/vault.ports.js';
import { vaultRouter } from './vault/vault.routes.js';

export interface AppDependencies {
  config: AppConfig;
  logger: Logger;
  repositories: {
    users: UserRepository;
    devices: DeviceRepository;
    sessions: SessionRepository;
    envelopes: KeyEnvelopeRepository;
    sync: SyncRepository;
  };
  /** Verificação de prontidão (ex.: ping no banco). */
  readinessCheck?: () => Promise<void>;
  passwordHasher?: PasswordHasher;
  clock?: Clock;
}

function errorBody(code: string, message: string, details?: unknown) {
  return { error: details ? { code, message, details } : { code, message } };
}

const tooManyRequests: RequestHandler = (_req, res) => {
  res
    .status(429)
    .json(errorBody('RATE_LIMITED', 'Muitas tentativas. Aguarde e tente novamente.'));
};

/** Monta a aplicação Express. Não abre portas nem conexões. */
export function createApp(deps: AppDependencies): Express {
  const { config, logger, repositories } = deps;
  const clock = deps.clock ?? systemClock;

  const auth = new AuthService({
    users: repositories.users,
    devices: repositories.devices,
    sessions: repositories.sessions,
    hasher: deps.passwordHasher ?? new PasswordHasher(),
    accessTokens: new AccessTokenService(config.jwtSecret, config.accessTokenTtlSeconds),
    refreshTokenTtlDays: config.refreshTokenTtlDays,
    allowRegistration: config.allowRegistration,
    clock,
  });
  const sync = new SyncService(repositories.sync, clock);
  const authenticated = requireAuth(auth);

  const app = express();
  app.set('trust proxy', config.trustProxy);
  app.disable('x-powered-by');

  // Logs mínimos: método, caminho, status e duração. Sem cabeçalhos ou corpo.
  app.use(
    pinoHttp({
      logger,
      serializers: {
        req: (req: Request) => ({ method: req.method, url: req.url?.split('?')[0] }),
        res: (res: { statusCode: number }) => ({ statusCode: res.statusCode }),
      },
    }),
  );

  app.use(helmet());
  app.use((_req, res, next) => {
    // Respostas da API nunca devem ser armazenadas em cache.
    res.setHeader('Cache-Control', 'no-store');
    next();
  });
  // CORS fechado por padrão; apps nativos não usam CORS.
  app.use(cors({ origin: config.corsOrigins.length > 0 ? config.corsOrigins : false }));

  if (config.requireHttps) {
    app.use((req, res, next) => {
      if (req.secure) return next();
      res.status(403).json(errorBody('HTTPS_REQUIRED', 'HTTPS é obrigatório.'));
    });
  }

  app.use(express.json({ limit: '2mb' }));

  app.get('/health', (_req, res) => {
    res.json({ status: 'ok' });
  });
  app.get('/health/ready', async (_req, res) => {
    try {
      await deps.readinessCheck?.();
      res.json({ status: 'ready' });
    } catch {
      res.status(503).json({ status: 'unavailable' });
    }
  });

  const { rateLimit: limits } = config;
  const globalLimiter = rateLimit({
    windowMs: limits.windowMs,
    limit: limits.globalPerIp,
    standardHeaders: 'draft-8',
    legacyHeaders: false,
    handler: tooManyRequests,
  });
  const authLimiter = rateLimit({
    windowMs: limits.windowMs,
    limit: limits.authPerIp,
    standardHeaders: 'draft-8',
    legacyHeaders: false,
    handler: tooManyRequests,
  });
  // Protege cada conta contra tentativas repetidas, mesmo vindas de vários IPs.
  const loginLimiter = rateLimit({
    windowMs: limits.windowMs,
    limit: limits.failedLoginsPerAccount,
    skipSuccessfulRequests: true,
    standardHeaders: 'draft-8',
    legacyHeaders: false,
    keyGenerator: (req) => {
      const email: unknown = (req.body as { email?: unknown } | undefined)?.email;
      return `login:${typeof email === 'string' ? email.trim().toLowerCase().slice(0, 254) : ''}`;
    },
    handler: tooManyRequests,
  });

  const api = express.Router();
  api.use(globalLimiter);
  api.use(authRouter({ auth, requireAuth: authenticated, authLimiter, loginLimiter }));
  api.use(vaultRouter({ envelopes: repositories.envelopes, requireAuth: authenticated }));
  api.use(syncRouter({ sync, requireAuth: authenticated }));
  app.use('/api/v1', api);

  app.use((_req, res) => {
    res.status(404).json(errorBody('NOT_FOUND', 'Rota não encontrada.'));
  });

  const errorHandler: ErrorRequestHandler = (error: unknown, req, res, _next) => {
    if (error instanceof AppError) {
      res.status(error.status).json(errorBody(error.code, error.message, error.details));
      return;
    }
    // Erros do body-parser (JSON malformado, corpo grande demais).
    const status = (error as { status?: unknown }).status;
    const type = (error as { type?: unknown }).type;
    if (type === 'entity.parse.failed') {
      res.status(400).json(errorBody('INVALID_JSON', 'JSON malformado.'));
      return;
    }
    if (type === 'entity.too.large') {
      res.status(413).json(errorBody('PAYLOAD_TOO_LARGE', 'Requisição grande demais.'));
      return;
    }
    if (typeof status === 'number' && status >= 400 && status < 500) {
      res.status(status).json(errorBody('BAD_REQUEST', 'Requisição inválida.'));
      return;
    }
    // Apenas nome e pilha; a mensagem de erros de terceiros pode conter dados.
    req.log.error({ errName: (error as Error)?.name, stack: (error as Error)?.stack }, 'erro não tratado');
    res.status(500).json(errorBody('INTERNAL_ERROR', 'Erro interno.'));
  };
  app.use(errorHandler);

  return app;
}

import { PrismaClient } from '@prisma/client';

import { createApp } from './app.js';
import { loadConfig } from './config/env.js';
import {
  PrismaDeviceRepository,
  PrismaKeyEnvelopeRepository,
  PrismaSessionRepository,
  PrismaSyncRepository,
  PrismaUserRepository,
} from './infra/prisma/prisma-repositories.js';
import { createLogger } from './shared/logger.js';

async function main(): Promise<void> {
  const config = loadConfig();
  const logger = createLogger(config.logLevel);
  const prisma = new PrismaClient({ datasourceUrl: config.databaseUrl });
  await prisma.$connect();

  const app = createApp({
    config,
    logger,
    repositories: {
      users: new PrismaUserRepository(prisma),
      devices: new PrismaDeviceRepository(prisma),
      sessions: new PrismaSessionRepository(prisma),
      envelopes: new PrismaKeyEnvelopeRepository(prisma),
      sync: new PrismaSyncRepository(prisma),
    },
    readinessCheck: async () => {
      await prisma.$queryRaw`SELECT 1`;
    },
  });

  const server = app.listen(config.port, () => {
    logger.info({ port: config.port, env: config.env }, 'MyVault API iniciada');
  });

  const shutdown = (signal: string) => {
    logger.info({ signal }, 'encerrando');
    server.close(() => {
      void prisma.$disconnect().finally(() => process.exit(0));
    });
    setTimeout(() => process.exit(1), 10_000).unref();
  };
  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));
}

main().catch((error: unknown) => {
  // Logger ainda pode não existir; registra só o essencial.
  process.stderr.write(`Falha ao iniciar: ${error instanceof Error ? error.message : 'erro desconhecido'}\n`);
  process.exit(1);
});

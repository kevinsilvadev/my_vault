import { pino, type Logger } from 'pino';

/**
 * Logger estruturado.
 *
 * Política: nunca registrar corpo de requisições/respostas, cabeçalhos de
 * autenticação, tokens, senhas ou conteúdo do cofre. As rotas registram apenas
 * método, caminho, status e duração (ver `app.ts`). O `redact` abaixo é uma
 * segunda linha de defesa caso algum objeto sensível chegue ao logger.
 */
export function createLogger(level: string): Logger {
  return pino({
    level,
    redact: {
      paths: [
        'req.headers.authorization',
        'req.headers.cookie',
        '*.password',
        '*.refreshToken',
        '*.accessToken',
        '*.encryptedData',
        '*.envelope',
      ],
      censor: '[REDACTED]',
    },
  });
}

export type { Logger };

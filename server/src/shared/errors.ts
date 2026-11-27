import type { ZodError } from 'zod';

export interface ErrorDetail {
  path: string;
  message: string;
}

/**
 * Erro de aplicação com status HTTP e código estável.
 *
 * A mensagem é exibida ao cliente; nunca deve conter segredos, tokens ou
 * conteúdo enviado pelo usuário.
 */
export class AppError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly details?: ErrorDetail[],
  ) {
    super(message);
    this.name = new.target.name;
  }
}

export class ValidationError extends AppError {
  constructor(details: ErrorDetail[]) {
    super(400, 'VALIDATION_ERROR', 'Dados inválidos.', details);
  }

  /** Converte issues do Zod sem ecoar os valores recebidos. */
  static fromZod(error: ZodError): ValidationError {
    return new ValidationError(
      error.issues.map((issue) => ({
        path: issue.path.map(String).join('.'),
        message: issue.message,
      })),
    );
  }
}

export class UnauthorizedError extends AppError {
  constructor(code = 'UNAUTHORIZED', message = 'Não autorizado.') {
    super(401, code, message);
  }
}

export class ForbiddenError extends AppError {
  constructor(code = 'FORBIDDEN', message = 'Operação não permitida.') {
    super(403, code, message);
  }
}

export class NotFoundError extends AppError {
  constructor(message = 'Recurso não encontrado.') {
    super(404, 'NOT_FOUND', message);
  }
}

export class ConflictError extends AppError {
  constructor(code: string, message: string) {
    super(409, code, message);
  }
}

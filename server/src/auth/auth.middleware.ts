import type { NextFunction, Request, RequestHandler, Response } from 'express';

import { UnauthorizedError } from '../shared/errors.js';
import type { AuthContext, AuthService } from './auth.service.js';

declare module 'express-serve-static-core' {
  interface Request {
    auth?: AuthContext;
  }
}

const BEARER = /^Bearer ([A-Za-z0-9\-_.]+)$/;

/** Exige um token de acesso válido de uma sessão e dispositivo ativos. */
export function requireAuth(auth: AuthService): RequestHandler {
  return async (req: Request, _res: Response, next: NextFunction) => {
    const match = BEARER.exec(req.get('authorization') ?? '');
    if (!match?.[1]) throw new UnauthorizedError();
    req.auth = await auth.authenticate(match[1]);
    next();
  };
}

/** Contexto autenticado da requisição (após `requireAuth`). */
export function authOf(req: Request): AuthContext {
  if (!req.auth) throw new UnauthorizedError();
  return req.auth;
}

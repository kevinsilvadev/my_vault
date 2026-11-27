import { Router, type RequestHandler } from 'express';

import { parseOrThrow } from '../shared/validation.js';
import { authOf } from './auth.middleware.js';
import { DeviceIdParamsSchema, LoginSchema, RefreshSchema, RegisterSchema } from './auth.schemas.js';
import type { AuthService } from './auth.service.js';

export interface AuthRouterOptions {
  auth: AuthService;
  requireAuth: RequestHandler;
  /** Limite por IP aplicado a todas as rotas públicas de autenticação. */
  authLimiter: RequestHandler;
  /** Limite de falhas por conta aplicado ao login. */
  loginLimiter: RequestHandler;
}

export function authRouter({ auth, requireAuth, authLimiter, loginLimiter }: AuthRouterOptions): Router {
  const router = Router();

  router.post('/auth/register', authLimiter, async (req, res) => {
    const input = parseOrThrow(RegisterSchema, req.body);
    res.status(201).json(await auth.register(input));
  });

  router.post('/auth/login', authLimiter, loginLimiter, async (req, res) => {
    const input = parseOrThrow(LoginSchema, req.body);
    res.json(await auth.login(input));
  });

  router.post('/auth/refresh', authLimiter, async (req, res) => {
    const { refreshToken } = parseOrThrow(RefreshSchema, req.body);
    res.json(await auth.refresh(refreshToken));
  });

  router.post('/auth/logout', requireAuth, async (req, res) => {
    await auth.logout(authOf(req));
    res.status(204).end();
  });

  router.get('/devices', requireAuth, async (req, res) => {
    res.json({ devices: await auth.listDevices(authOf(req)) });
  });

  router.delete('/devices/:deviceId', requireAuth, async (req, res) => {
    const { deviceId } = parseOrThrow(DeviceIdParamsSchema, req.params);
    await auth.revokeDevice(authOf(req), deviceId);
    res.status(204).end();
  });

  return router;
}

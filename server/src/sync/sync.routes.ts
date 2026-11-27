import { Router, type RequestHandler } from 'express';

import { authOf } from '../auth/auth.middleware.js';
import { parseOrThrow } from '../shared/validation.js';
import { PullQuerySchema, PushRequestSchema } from './sync.schemas.js';
import type { SyncService } from './sync.service.js';

export function syncRouter(deps: { sync: SyncService; requireAuth: RequestHandler }): Router {
  const router = Router();
  router.use('/sync', deps.requireAuth);

  router.post('/sync/push', async (req, res) => {
    const { changes } = parseOrThrow(PushRequestSchema, req.body);
    res.json({ results: await deps.sync.push(authOf(req).userId, changes) });
  });

  router.get('/sync/pull', async (req, res) => {
    const { since, limit } = parseOrThrow(PullQuerySchema, req.query);
    res.json(await deps.sync.pull(authOf(req).userId, since, limit));
  });

  return router;
}

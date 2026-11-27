import { Router, type RequestHandler } from 'express';

import { authOf } from '../auth/auth.middleware.js';
import { ConflictError, NotFoundError } from '../shared/errors.js';
import { parseOrThrow } from '../shared/validation.js';
import type { KeyEnvelopeRepository } from './vault.ports.js';
import { PutKeyEnvelopeSchema } from './vault.schemas.js';

/**
 * Envelope da chave do cofre. Permite que um novo dispositivo desbloqueie o
 * cofre com a senha mestre; o servidor não consegue abri-lo.
 */
export function vaultRouter(deps: {
  envelopes: KeyEnvelopeRepository;
  requireAuth: RequestHandler;
}): Router {
  const router = Router();
  router.use('/vault', deps.requireAuth);

  router.get('/vault/key-envelope', async (req, res) => {
    const stored = await deps.envelopes.get(authOf(req).userId);
    if (!stored) throw new NotFoundError('O cofre desta conta ainda não foi configurado.');
    res.json({
      envelope: stored.envelope,
      version: stored.version,
      updatedAt: stored.updatedAt.toISOString(),
    });
  });

  router.put('/vault/key-envelope', async (req, res) => {
    const { envelope, baseVersion } = parseOrThrow(PutKeyEnvelopeSchema, req.body);
    const result = await deps.envelopes.put(authOf(req).userId, envelope, baseVersion);
    if (result.status === 'conflict') {
      throw new ConflictError(
        'ENVELOPE_VERSION_CONFLICT',
        'O envelope do cofre foi alterado por outro dispositivo.',
      );
    }
    res.json({ version: result.version });
  });

  return router;
}

import type { KeyEnvelope } from './vault.schemas.js';

export interface StoredKeyEnvelope {
  envelope: KeyEnvelope;
  version: number;
  updatedAt: Date;
}

export type PutEnvelopeResult =
  | { status: 'ok'; version: number }
  | { status: 'conflict'; current: StoredKeyEnvelope | null };

export interface KeyEnvelopeRepository {
  get(userId: string): Promise<StoredKeyEnvelope | null>;
  /**
   * Grava com concorrência otimista: só aplica se a versão atual for
   * `expectedVersion` (0 = criação).
   */
  put(userId: string, envelope: KeyEnvelope, expectedVersion: number): Promise<PutEnvelopeResult>;
}

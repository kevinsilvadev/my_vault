import type { Clock } from '../shared/clock.js';
import type { PushChange } from './sync.schemas.js';
import type { StoredItem, SyncRepository } from './sync.ports.js';

export interface ItemDto {
  id: string;
  encryptedData: string | null;
  nonce: string | null;
  cryptoVersion: number;
  version: number;
  revision: number;
  deleted: boolean;
  updatedAt: string;
}

export type PushResult =
  | { changeId: string; itemId: string; status: 'applied'; version: number; revision: number }
  | { changeId: string; itemId: string; status: 'conflict'; serverItem: ItemDto }
  | {
      changeId: string;
      itemId: string;
      status: 'rejected';
      reason: 'base_version_not_found' | 'change_id_reused';
    };

export interface PullResult {
  items: ItemDto[];
  cursor: number;
  hasMore: boolean;
  latestRevision: number;
}

export function toItemDto(item: StoredItem): ItemDto {
  return {
    id: item.id,
    encryptedData: item.encryptedData,
    nonce: item.nonce,
    cryptoVersion: item.cryptoVersion,
    version: item.version,
    revision: item.revision,
    deleted: item.deleted,
    updatedAt: item.updatedAt.toISOString(),
  };
}

/**
 * Sincronização de registros cifrados.
 *
 * - Concorrência otimista: a alteração só é aplicada se `baseVersion` for a
 *   versão atual. Caso contrário, devolve `conflict` com a versão do servidor
 *   — nunca sobrescreve silenciosamente.
 * - Idempotência: `changeId` já aplicado devolve o mesmo resultado.
 * - Tombstones: exclusões mantêm o registro com `deleted = true` e sem
 *   conteúdo, para que todos os dispositivos as recebam.
 * - Cursor: cada alteração recebe uma revisão monotônica por usuário.
 */
export class SyncService {
  constructor(
    private readonly repository: SyncRepository,
    private readonly clock: Clock,
  ) {}

  async push(userId: string, changes: PushChange[]): Promise<PushResult[]> {
    const results: PushResult[] = [];
    // Cada alteração em sua própria transação: falhas parciais não bloqueiam
    // as demais, e o cliente reenvia apenas o que não foi confirmado.
    for (const change of changes) {
      results.push(await this.applyChange(userId, change));
    }
    return results;
  }

  async pull(userId: string, since: number, limit: number): Promise<PullResult> {
    const rows = await this.repository.listChangedSince(userId, since, limit + 1);
    const items = rows.slice(0, limit);
    const last = items.at(-1);
    return {
      items: items.map(toItemDto),
      cursor: last ? last.revision : since,
      hasMore: rows.length > limit,
      latestRevision: await this.repository.latestRevision(userId),
    };
  }

  private applyChange(userId: string, change: PushChange): Promise<PushResult> {
    const { changeId, itemId } = change;
    return this.repository.withUserLock(userId, async (tx): Promise<PushResult> => {
      const replay = await tx.findAppliedChange(changeId);
      if (replay) {
        if (replay.itemId !== itemId) {
          return { changeId, itemId, status: 'rejected', reason: 'change_id_reused' };
        }
        return {
          changeId,
          itemId,
          status: 'applied',
          version: replay.version,
          revision: replay.revision,
        };
      }

      const current = await tx.findItem(itemId);
      if (!current && change.baseVersion > 0) {
        return { changeId, itemId, status: 'rejected', reason: 'base_version_not_found' };
      }
      if (current && current.version !== change.baseVersion) {
        return { changeId, itemId, status: 'conflict', serverItem: toItemDto(current) };
      }

      const now = this.clock();
      const revision = await tx.nextRevision();
      const version = (current?.version ?? 0) + 1;
      const base = {
        id: itemId,
        userId,
        version,
        revision,
        createdAt: current?.createdAt ?? now,
        updatedAt: now,
      };
      const item: StoredItem =
        change.operation === 'upsert'
          ? {
              ...base,
              encryptedData: change.encryptedData,
              nonce: change.nonce,
              cryptoVersion: change.cryptoVersion,
              deleted: false,
            }
          : {
              ...base,
              encryptedData: null,
              nonce: null,
              cryptoVersion: current?.cryptoVersion ?? 1,
              deleted: true,
            };

      await tx.saveItem(item);
      await tx.recordAppliedChange({ changeId, itemId, version, revision });
      return { changeId, itemId, status: 'applied', version, revision };
    });
  }
}

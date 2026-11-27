export interface StoredItem {
  id: string;
  userId: string;
  encryptedData: string | null;
  nonce: string | null;
  cryptoVersion: number;
  version: number;
  revision: number;
  deleted: boolean;
  createdAt: Date;
  updatedAt: Date;
}

export interface AppliedChangeRecord {
  changeId: string;
  itemId: string;
  version: number;
  revision: number;
}

/**
 * Operações executadas dentro de uma transação que detém o bloqueio do
 * usuário. Todas as leituras e escritas são restritas a esse usuário.
 */
export interface SyncTransaction {
  findItem(itemId: string): Promise<StoredItem | null>;
  findAppliedChange(changeId: string): Promise<AppliedChangeRecord | null>;
  /** Incrementa e retorna o contador de revisões do usuário. */
  nextRevision(): Promise<number>;
  saveItem(item: StoredItem): Promise<void>;
  recordAppliedChange(change: AppliedChangeRecord): Promise<void>;
}

export interface SyncRepository {
  /**
   * Executa `work` em uma transação serializada por usuário (no PostgreSQL,
   * `SELECT ... FOR UPDATE` na linha do usuário).
   */
  withUserLock<T>(userId: string, work: (tx: SyncTransaction) => Promise<T>): Promise<T>;
  listChangedSince(userId: string, since: number, limit: number): Promise<StoredItem[]>;
  latestRevision(userId: string): Promise<number>;
}

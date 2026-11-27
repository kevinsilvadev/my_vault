import 'package:sqflite/sqflite.dart';

/// Banco SQLite local. Armazena somente ciphertext e metadados — nenhum campo
/// do cofre em texto puro.
abstract final class LocalDatabase {
  static const int schemaVersion = 1;

  static Future<Database> open(DatabaseFactory factory, String path) {
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) => _migrate(db, 0, version),
        onUpgrade: _migrate,
      ),
    );
  }

  /// Migrações incrementais: cada versão aplica apenas o seu passo.
  static Future<void> _migrate(Database db, int from, int to) async {
    final batch = db.batch();
    if (from < 1) {
      batch
        ..execute('''
          CREATE TABLE meta (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL
          )''')
        ..execute('''
          CREATE TABLE records (
            id TEXT PRIMARY KEY NOT NULL,
            encrypted_data TEXT,
            nonce TEXT,
            crypto_version INTEGER NOT NULL,
            server_version INTEGER NOT NULL DEFAULT 0,
            deleted INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT NOT NULL,
            pending_change_id TEXT,
            pending_operation TEXT
          )''')
        ..execute(
            'CREATE INDEX idx_records_pending ON records(pending_change_id) '
            'WHERE pending_change_id IS NOT NULL')
        ..execute('''
          CREATE TABLE conflicts (
            id TEXT PRIMARY KEY NOT NULL,
            item_id TEXT NOT NULL,
            local_encrypted_data TEXT,
            local_nonce TEXT,
            local_crypto_version INTEGER NOT NULL,
            local_deleted INTEGER NOT NULL,
            detected_at TEXT NOT NULL
          )''');
    }
    await batch.commit(noResult: true);
  }
}

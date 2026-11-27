import 'package:meta/meta.dart';

import '../json_reader.dart';

/// Operação pendente de envio ao servidor.
enum PendingOperation {
  upsert,
  delete;

  static PendingOperation parse(String value) => switch (value) {
        'upsert' => PendingOperation.upsert,
        'delete' => PendingOperation.delete,
        _ => throw FormatException('Operação desconhecida: $value'),
      };
}

/// Registro como o servidor o conhece: apenas ciphertext e metadados mínimos.
@immutable
final class RemoteRecord {
  const RemoteRecord({
    required this.id,
    required this.encryptedData,
    required this.nonce,
    required this.cryptoVersion,
    required this.version,
    required this.revision,
    required this.deleted,
    required this.updatedAt,
  });

  factory RemoteRecord.fromJson(JsonReader json) => RemoteRecord(
        id: json.string('id'),
        encryptedData: json.nullableString('encryptedData'),
        nonce: json.nullableString('nonce'),
        cryptoVersion: json.integer('cryptoVersion'),
        version: json.integer('version'),
        revision: json.integer('revision'),
        deleted: json.boolean('deleted'),
        updatedAt: json.dateTime('updatedAt'),
      );

  final String id;

  /// `null` em tombstones (exclusões).
  final String? encryptedData;
  final String? nonce;
  final int cryptoVersion;

  /// Versão do registro (controle de concorrência otimista).
  final int version;

  /// Revisão global do usuário (cursor de sincronização).
  final int revision;
  final bool deleted;
  final DateTime updatedAt;
}

/// Alteração enviada ao servidor. [changeId] torna o envio idempotente:
/// reenviar a mesma alteração após uma falha de rede não a aplica duas vezes.
@immutable
final class PushChange {
  const PushChange({
    required this.changeId,
    required this.itemId,
    required this.operation,
    required this.baseVersion,
    this.encryptedData,
    this.nonce,
    this.cryptoVersion,
  });

  final String changeId;
  final String itemId;
  final PendingOperation operation;

  /// Versão do servidor sobre a qual a alteração foi feita (0 = item novo).
  final int baseVersion;
  final String? encryptedData;
  final String? nonce;
  final int? cryptoVersion;

  Map<String, Object?> toJson() => switch (operation) {
        PendingOperation.upsert => {
            'changeId': changeId,
            'itemId': itemId,
            'operation': 'upsert',
            'baseVersion': baseVersion,
            'cryptoVersion': cryptoVersion,
            'encryptedData': encryptedData,
            'nonce': nonce,
          },
        PendingOperation.delete => {
            'changeId': changeId,
            'itemId': itemId,
            'operation': 'delete',
            'baseVersion': baseVersion,
          },
      };
}

enum PushStatus { applied, conflict, rejected }

/// Motivos de rejeição definidos pela API.
abstract final class PushRejection {
  /// O cliente enviou `baseVersion > 0` para um item que o servidor não tem
  /// (ex.: servidor restaurado de backup). O cliente deve reenviar como novo.
  static const String baseVersionNotFound = 'base_version_not_found';

  /// O `changeId` já foi usado para outro item. O cliente deve gerar outro.
  static const String changeIdReused = 'change_id_reused';
}

@immutable
final class PushResult {
  const PushResult({
    required this.changeId,
    required this.itemId,
    required this.status,
    this.version,
    this.revision,
    this.serverItem,
    this.reason,
  });

  factory PushResult.fromJson(JsonReader json) {
    final status = switch (json.string('status')) {
      'applied' => PushStatus.applied,
      'conflict' => PushStatus.conflict,
      'rejected' => PushStatus.rejected,
      final other => throw FormatException('Status desconhecido: $other'),
    };
    final serverItem = json.json['serverItem'];
    return PushResult(
      changeId: json.string('changeId'),
      itemId: json.string('itemId'),
      status: status,
      version: json.json['version'] as int?,
      revision: json.json['revision'] as int?,
      serverItem: serverItem is Map<String, Object?>
          ? RemoteRecord.fromJson(JsonReader(serverItem))
          : null,
      reason: json.nullableString('reason'),
    );
  }

  final String changeId;
  final String itemId;
  final PushStatus status;

  /// Presentes quando [status] é [PushStatus.applied].
  final int? version;
  final int? revision;

  /// Versão atual no servidor quando [status] é [PushStatus.conflict].
  final RemoteRecord? serverItem;

  /// Motivo quando [status] é [PushStatus.rejected] (ver [PushRejection]).
  final String? reason;
}

@immutable
final class PullPage {
  const PullPage({
    required this.items,
    required this.cursor,
    required this.hasMore,
    required this.latestRevision,
  });

  factory PullPage.fromJson(JsonReader json) => PullPage(
        items: [
          for (final item in json.objectList('items')) RemoteRecord.fromJson(item),
        ],
        cursor: json.integer('cursor'),
        hasMore: json.boolean('hasMore'),
        latestRevision: json.integer('latestRevision'),
      );

  final List<RemoteRecord> items;

  /// Revisão do último item desta página; usar como `since` na próxima.
  final int cursor;
  final bool hasMore;

  /// Maior revisão existente para o usuário. Se o cursor local for maior,
  /// o servidor foi restaurado e o cliente deve ressincronizar do zero.
  final int latestRevision;
}

/// Porta para a API de sincronização (implementada pelo app via HTTP).
abstract interface class RemoteSyncApi {
  Future<List<PushResult>> push(List<PushChange> changes);

  Future<PullPage> pull({required int since, required int limit});
}

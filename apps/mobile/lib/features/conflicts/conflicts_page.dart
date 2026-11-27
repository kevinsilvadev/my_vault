import 'package:flutter/material.dart';
import 'package:vault_core/vault_core.dart';

import '../../app/app_scope.dart';
import '../../shared/widgets.dart';

/// Conflitos de sincronização. Nenhuma versão é descartada sem confirmação.
class ConflictsPage extends StatelessWidget {
  const ConflictsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final vault = AppScope.of(context).vault;
    return Scaffold(
      appBar: AppBar(title: const Text('Conflitos')),
      body: ListenableBuilder(
        listenable: vault,
        builder: (context, _) {
          final conflicts = vault.conflicts;
          if (conflicts.isEmpty) {
            return const Center(child: Text('Nenhum conflito pendente.'));
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'Estes itens foram alterados em outro dispositivo enquanto você também '
                  'os alterava aqui. Escolha qual versão manter.',
                ),
              ),
              for (final conflict in conflicts) _ConflictCard(conflict: conflict),
            ],
          );
        },
      ),
    );
  }
}

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({required this.conflict});

  final ConflictView conflict;

  Future<void> _resolve(BuildContext context, ConflictResolution resolution) async {
    final vault = AppScope.of(context).vault;
    final (title, message) = switch (resolution) {
      ConflictResolution.keepLocal => (
          'Manter a versão deste dispositivo?',
          'A versão do outro dispositivo será substituída em todos os dispositivos.'
        ),
      ConflictResolution.keepRemote => (
          'Manter a versão do outro dispositivo?',
          'As alterações feitas neste dispositivo serão descartadas.'
        ),
      ConflictResolution.keepBoth => (
          'Manter as duas versões?',
          'A versão deste dispositivo será salva como uma nova credencial.'
        ),
    };
    final confirmed = await confirmAction(
      context,
      title: title,
      message: message,
      destructive: resolution != ConflictResolution.keepBoth,
    );
    if (!confirmed) return;
    try {
      await vault.resolveConflict(conflict.conflictId, resolution);
    } on VaultException catch (error) {
      if (context.mounted) showMessage(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canKeepBoth = !conflict.localDeleted && conflict.local != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _VersionSummary(
              label: 'Este dispositivo',
              item: conflict.local,
              deleted: conflict.localDeleted,
            ),
            const Divider(),
            _VersionSummary(
              label: 'Outro dispositivo',
              item: conflict.remote,
              deleted: conflict.remoteDeleted,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => _resolve(context, ConflictResolution.keepRemote),
                  child: const Text('Manter a outra'),
                ),
                OutlinedButton(
                  onPressed: () => _resolve(context, ConflictResolution.keepLocal),
                  child: const Text('Manter esta'),
                ),
                if (canKeepBoth)
                  FilledButton(
                    onPressed: () => _resolve(context, ConflictResolution.keepBoth),
                    child: const Text('Manter ambas'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VersionSummary extends StatelessWidget {
  const _VersionSummary({required this.label, required this.item, required this.deleted});

  final String label;
  final VaultItem? item;
  final bool deleted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = deleted
        ? 'Excluída'
        : item == null
            ? 'Não foi possível ler esta versão'
            : [item!.title, if (item!.username.isNotEmpty) item!.username].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: theme.textTheme.labelMedium),
      subtitle: Text(description),
      trailing: item == null || deleted
          ? null
          : Text(
              'alterada em\n${item!.updatedAt.toLocal().toString().substring(0, 16)}',
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall,
            ),
    );
  }
}

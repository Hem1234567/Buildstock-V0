import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buildstock/app/theme/app_theme.dart';
import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/database/database_provider.dart';
import 'package:buildstock/core/domain/enums.dart';
import 'package:buildstock/core/sync/sync_controller.dart';
import 'package:buildstock/core/utils/dates.dart';
import 'package:buildstock/core/widgets/async_view.dart';

import 'package:buildstock/core/widgets/section_card.dart';

final syncQueueProvider = StreamProvider<List<SyncQueueRow>>(
  (ref) => ref.watch(outboxProvider).watchQueue(),
);

final lastSyncProvider = FutureProvider<String?>(
  (ref) => ref.watch(databaseProvider).getSetting('last_sync_at'),
);

class SyncCenterScreen extends ConsumerWidget {
  const SyncCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(syncControllerProvider);
    final queue = ref.watch(syncQueueProvider);
    final runtime = ref.watch(firebaseRuntimeProvider);
    final identity = ref.watch(identityProvider);
    final lastSync = ref.watch(lastSyncProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Sync Center')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      runtime.isReady
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_off_outlined,
                      size: 20,
                      color: runtime.isReady
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        runtime.isReady ? 'Cloud configured' : 'Offline mode',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    StatusPill.sync(
                      state.lastReport?.isSuccess == true
                          ? 'synced'
                          : 'pending',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  runtime.isReady
                      ? (runtime.isSignedIn
                            ? 'Signed in as ${runtime.uid} · shop ${identity.shopId}'
                            : 'Sign in from Settings to sync this shop.')
                      : (runtime.unavailableReason ??
                            'Firebase is not configured on this build.'),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  lastSync.maybeWhen(
                    data: (value) => value == null
                        ? 'Never synchronized'
                        : 'Last attempt ${AppDate.displayLong(DateTime.parse(value))} ${AppDate.time(DateTime.parse(value))}',
                    orElse: () => 'Last sync unavailable',
                  ),
                  style: theme.textTheme.bodySmall,
                ),
                if (state.error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    state.error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.danger,
                    ),
                  ),
                ],
                if (state.lastReport != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Pushed ${state.lastReport!.pushed} · Pulled ${state.lastReport!.pulled} · '
                    'Failed ${state.lastReport!.failed} · Conflicts ${state.lastReport!.conflicts}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: state.running
                            ? null
                            : () async {
                                await ref
                                    .read(syncControllerProvider.notifier)
                                    .run();
                                ref.invalidate(lastSyncProvider);
                                ref.invalidate(syncQueueProvider);
                              },
                        child: state.running
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Sync now'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: state.running
                            ? null
                            : () async {
                                await ref
                                    .read(syncControllerProvider.notifier)
                                    .retryFailed();
                                ref.invalidate(syncQueueProvider);
                              },
                        child: const Text('Retry failed'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AsyncView(
            value: queue,
            builder: (rows) {
              final pending = rows
                  .where((row) => row.status == SyncStatus.pending)
                  .length;
              final failed = rows
                  .where((row) => row.status == SyncStatus.failed)
                  .length;
              final conflicts = rows
                  .where((row) => row.status == SyncStatus.conflict)
                  .length;
              final synced = rows
                  .where((row) => row.status == SyncStatus.synced)
                  .length;
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _Count(
                          label: 'Pending',
                          value: pending,
                          color: AppColors.info,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _Count(
                          label: 'Failed',
                          value: failed,
                          color: AppColors.danger,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _Count(
                          label: 'Conflicts',
                          value: conflicts,
                          color: AppColors.warning,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _Count(
                          label: 'Synced',
                          value: synced,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (rows.isEmpty)
                    const SectionCard(
                      child: EmptyState(
                        title: 'Everything is up to date',
                        message: 'New local changes will appear here until the cloud confirms them.',
                        icon: Icons.cloud_done_outlined,
                        compact: true,
                      ),
                    )
                  else
                    SectionCard(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          for (final row in rows.take(50))
                            ListTile(
                              dense: true,
                              leading: Icon(
                                row.status == SyncStatus.conflict
                                    ? Icons.compare_arrows
                                    : row.status == SyncStatus.failed
                                    ? Icons.error_outline
                                    : Icons.cloud_upload_outlined,
                                size: 18,
                                color: row.status == SyncStatus.conflict
                                    ? AppColors.warning
                                    : row.status == SyncStatus.failed
                                    ? AppColors.danger
                                    : AppColors.info,
                              ),
                              title: Text(
                                '${row.entityType} · ${row.operation}',
                              ),
                              subtitle: Text(
                                row.lastError ??
                                    'Attempts ${row.attempts} · ${AppDate.display(row.updatedAt)}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: StatusPill.sync(row.status),
                            ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            'A record is only marked synced after Firestore confirms the write. '
            'Failed operations stay queued and retry with exponential backoff. '
            'Records with local changes that conflict with a cloud version are '
            'never silently overwritten.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(
            '$value',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

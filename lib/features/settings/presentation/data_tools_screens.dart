import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buildstock/app/theme/app_theme.dart';
import 'package:buildstock/core/backup/backup_service.dart';
import 'package:buildstock/core/database/database_provider.dart';
import 'package:buildstock/core/media/image_host.dart';
import 'package:buildstock/core/media/image_service.dart';
import 'package:buildstock/core/notifications/low_stock_notifier.dart';
import 'package:buildstock/core/utils/dates.dart';
import 'package:buildstock/core/widgets/feedback.dart';
import 'package:buildstock/core/widgets/section_card.dart';
import 'package:buildstock/features/business/data/business_repository.dart';

String _size(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Backup and restore of the whole local database.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;
  bool _auto = true;
  String? _lastBackup;
  List<BackupFileInfo> _files = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final service = ref.read(backupServiceProvider);
    final db = ref.read(databaseProvider);
    final files = await service.localBackups();
    final last = await db.getSetting('last_backup_at');
    final auto = await db.getSetting('auto_backup');
    if (!mounted) return;
    setState(() {
      _files = files;
      _lastBackup = last;
      _auto = auto != 'false';
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) showActionMessage(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  Future<void> _export() => _run(() async {
    final bytes = await ref.read(backupServiceProvider).createBackup();
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Save backup',
      fileName: BackupService.fileName(),
      mimeType: 'application/octet-stream',
      bytes: bytes,
    );
    if (mounted && uri != null) {
      showActionMessage(context, 'Backup saved (${_size(bytes.length)})');
    }
  });

  Future<void> _restoreFromBytes(List<int> bytes) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: const Text(
          'This replaces all business data on this device with the backup. '
          'A safety copy of the current data is saved first. '
          'Invoice numbers never go backwards.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      final summary = await ref
          .read(backupServiceProvider)
          .restore(Uint8List.fromList(bytes));
      if (mounted) {
        showActionMessage(
          context,
          'Restored ${summary.rows} records from ${summary.tables} tables',
        );
      }
    });
  }

  Future<void> _pickAndRestore() async {
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      withData: true,
    );
    final file = result?.files.single;
    if (file == null) return;
    final bytes = file.bytes;
    if (bytes == null) {
      if (mounted) showActionMessage(context, 'Could not read that file');
      return;
    }
    await _restoreFromBytes(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = DateTime.tryParse(_lastBackup ?? '');
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & restore')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your data', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  last == null
                      ? 'No backup has been made yet.'
                      : 'Last backup: ${AppDate.displayLong(last)} ${AppDate.time(last)}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _busy ? null : _export,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Create backup file'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickAndRestore,
                  icon: const Icon(Icons.restore),
                  label: const Text('Restore from a backup file'),
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Automatic daily backup'),
              subtitle: const Text('Keeps the last 7 backups inside the app.'),
              value: _auto,
              activeTrackColor: AppColors.accent,
              onChanged: (value) async {
                setState(() => _auto = value);
                await ref
                    .read(databaseProvider)
                    .setSetting('auto_backup', '$value');
              },
            ),
          ),
          const SizedBox(height: 16),
          const SectionHeader(title: 'Backups kept on this device'),
          if (_files.isEmpty)
            const EmptyState(
              title: 'None yet',
              message: 'Automatic and safety backups appear here.',
              icon: Icons.history,
              compact: true,
            )
          else
            SectionCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final file in _files)
                    ListTile(
                      leading: const Icon(Icons.inventory_outlined),
                      title: Text(file.name),
                      subtitle: Text(
                        '${AppDate.display(file.modified)} ${AppDate.time(file.modified)} · ${_size(file.sizeBytes)}',
                      ),
                      trailing: TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                final bytes = await ref
                                    .read(backupServiceProvider)
                                    .readLocal(file.path);
                                await _restoreFromBytes(bytes);
                              },
                        child: const Text('Restore'),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'Backups contain your business records only. Keep copies away from '
            'this phone (Drive, email, a computer). Cloud sync is separate and '
            'shares data between devices.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Where compressed photos are uploaded.
class PhotoHostingScreen extends ConsumerStatefulWidget {
  const PhotoHostingScreen({super.key});

  @override
  ConsumerState<PhotoHostingScreen> createState() => _PhotoHostingScreenState();
}

class _PhotoHostingScreenState extends ConsumerState<PhotoHostingScreen> {
  final _imgbb = TextEditingController();
  final _cloud = TextEditingController();
  final _preset = TextEditingController();
  ImageHostProvider _provider = ImageHostProvider.imgbb;
  bool _loaded = false;
  bool _busy = false;
  int _waiting = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _imgbb.dispose();
    _cloud.dispose();
    _preset.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final service = ref.read(imageServiceProvider);
    final config = await service.loadConfig();
    final pending = await ref
        .read(databaseProvider)
        .customSelect(
          "SELECT COUNT(*) AS c FROM image_metadata "
          "WHERE upload_status != 'uploaded' AND deleted_at IS NULL",
        )
        .getSingle();
    if (!mounted) return;
    setState(() {
      _provider = config.provider;
      _imgbb.text = config.imgbbApiKey;
      _cloud.text = config.cloudinaryCloudName;
      _preset.text = config.cloudinaryUploadPreset;
      _waiting = pending.read<int>('c');
      _loaded = true;
    });
  }

  Future<void> _save({bool upload = false}) async {
    setState(() => _busy = true);
    try {
      final repository = ref.read(businessRepositoryProvider);
      await repository.putSetting(ImageHostKeys.provider, _provider.name);
      await repository.putSetting(ImageHostKeys.imgbbKey, _imgbb.text.trim());
      await repository.putSetting(ImageHostKeys.cloudName, _cloud.text.trim());
      await repository.putSetting(
        ImageHostKeys.uploadPreset,
        _preset.text.trim(),
      );
      var message = 'Photo hosting saved';
      if (upload) {
        final count = await ref.read(imageServiceProvider).uploadPending();
        message = count == 0
            ? 'Nothing was uploaded. Check the keys and your connection.'
            : 'Uploaded $count photo(s)';
      }
      if (mounted) showActionMessage(context, message);
      await _load();
    } catch (error) {
      if (mounted) showActionMessage(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('Photo hosting')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Photo hosting')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            'Photos are compressed on the phone and uploaded to a free image '
            'host, so they appear on every device. Without a host, photos stay '
            'on this phone only. Firebase Storage is not used.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          SectionCard(
            child: Column(
              children: [
                DropdownButtonFormField<ImageHostProvider>(
                  initialValue: _provider,
                  decoration: const InputDecoration(labelText: 'Host'),
                  items: const [
                    DropdownMenuItem(
                      value: ImageHostProvider.imgbb,
                      child: Text('ImgBB'),
                    ),
                    DropdownMenuItem(
                      value: ImageHostProvider.cloudinary,
                      child: Text('Cloudinary'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _provider = value ?? _provider),
                ),
                const SizedBox(height: 12),
                if (_provider == ImageHostProvider.imgbb)
                  TextField(
                    controller: _imgbb,
                    decoration: const InputDecoration(
                      labelText: 'ImgBB API key',
                      helperText: 'Free key from api.imgbb.com',
                    ),
                  )
                else ...[
                  TextField(
                    controller: _cloud,
                    decoration: const InputDecoration(
                      labelText: 'Cloudinary cloud name',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _preset,
                    decoration: const InputDecoration(
                      labelText: 'Unsigned upload preset',
                      helperText:
                          'Create an unsigned preset in Cloudinary settings',
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _waiting == 0
                ? 'All photos are uploaded.'
                : '$_waiting photo(s) waiting to upload.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _save(upload: true),
                  child: const Text('Save & upload now'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _save,
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Low-stock notification switch and a manual check.
class LowStockAlertsScreen extends ConsumerStatefulWidget {
  const LowStockAlertsScreen({super.key});

  @override
  ConsumerState<LowStockAlertsScreen> createState() =>
      _LowStockAlertsScreenState();
}

class _LowStockAlertsScreenState extends ConsumerState<LowStockAlertsScreen> {
  bool _enabled = true;
  List<LowStockItem> _items = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await ref
        .read(databaseProvider)
        .getSetting(LowStockSettings.enabled);
    final items = await ref.read(lowStockNotifierProvider).lowStock();
    if (!mounted) return;
    setState(() {
      _enabled = enabled != 'false';
      _items = items;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Low stock alerts')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                SectionCard(
                  child: Column(
                    children: [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Notify me about low stock'),
                        subtitle: const Text(
                          'A notification when a product reaches its minimum stock. At most once a day.',
                        ),
                        value: _enabled,
                        activeTrackColor: AppColors.accent,
                        onChanged: (value) async {
                          setState(() => _enabled = value);
                          await ref
                              .read(databaseProvider)
                              .setSetting(LowStockSettings.enabled, '$value');
                          if (value) {
                            await ref
                                .read(lowStockNotifierProvider)
                                .check(force: true);
                          }
                        },
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final count = await ref
                                .read(lowStockNotifierProvider)
                                .check(force: true);
                            if (context.mounted) {
                              showActionMessage(
                                context,
                                count == 0
                                    ? 'Nothing is low on stock'
                                    : '$count product(s) are low',
                              );
                            }
                          },
                          icon: const Icon(Icons.notifications_active_outlined),
                          label: const Text('Check now'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const SectionHeader(title: 'Currently low'),
                if (_items.isEmpty)
                  const EmptyState(
                    title: 'All good',
                    message: 'No product is at or below its minimum stock.',
                    icon: Icons.check_circle_outline,
                    compact: true,
                  )
                else
                  SectionCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final item in _items)
                          ListTile(
                            title: Text(item.name),
                            subtitle: Text(
                              'Stock ${item.stockMilli / 1000} · minimum ${item.minStockMilli / 1000}',
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

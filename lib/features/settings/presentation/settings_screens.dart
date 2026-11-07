import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:buildstock/app/preferences.dart';
import 'package:buildstock/app/theme/app_theme.dart';

import 'package:buildstock/core/database/database_provider.dart';
import 'package:buildstock/core/session/session_service.dart';
import 'package:buildstock/core/widgets/app_form.dart';
import 'package:buildstock/core/widgets/async_view.dart';
import 'package:buildstock/core/widgets/feedback.dart';
import 'package:buildstock/core/widgets/section_card.dart';
import 'package:buildstock/features/business/data/business_repository.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(identityProvider);
    final runtime = ref.watch(firebaseRuntimeProvider);
    final prefs = ref.watch(preferencesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          SectionCard(
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.accentSoft,
                  child: Icon(Icons.business, color: AppColors.accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        identity.displayName ?? 'Local business owner',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        identity.isLocalOnly
                            ? 'Offline mode · ${identity.deviceName}'
                            : 'Signed in · ${identity.deviceCode}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                StatusPill(
                  label: identity.isLocalOnly ? 'Local' : 'Cloud',
                  color: identity.isLocalOnly
                      ? AppColors.warning
                      : AppColors.success,
                  background: identity.isLocalOnly
                      ? AppColors.warningSoft
                      : AppColors.successSoft,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionHeader(title: 'Business'),
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                _tile(
                  context,
                  Icons.storefront_outlined,
                  'Business profile',
                  'Name, address, GSTIN, UPI and invoice prefix',
                  () => context.push('/settings/business'),
                ),
                _tile(
                  context,
                  Icons.palette_outlined,
                  'Appearance',
                  prefs.themeMode.name,
                  () => _pickTheme(context, ref),
                ),
                _tile(
                  context,
                  Icons.translate_outlined,
                  'Language',
                  prefs.locale.languageCode == 'ta' ? 'Tamil' : 'English',
                  () => _pickLanguage(context, ref),
                ),
                _tile(
                  context,
                  Icons.print_outlined,
                  'Printer & paper',
                  'A4, 58 mm and 80 mm thermal',
                  () => context.push('/settings/printer'),
                ),
                _tile(
                  context,
                  Icons.photo_library_outlined,
                  'Photo hosting',
                  'Where product, logo and proof photos are uploaded',
                  () => context.push('/settings/photos'),
                ),
                _tile(
                  context,
                  Icons.notifications_active_outlined,
                  'Low stock alerts',
                  'Notify when stock reaches the minimum',
                  () => context.push('/settings/low-stock'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionHeader(title: 'Data'),
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                _tile(
                  context,
                  Icons.cloud_outlined,
                  'Sync Center',
                  identity.isLocalOnly
                      ? 'Connect to sync across devices'
                      : 'Outbox, retries and conflicts',
                  () => context.push('/sync'),
                ),
                _tile(
                  context,
                  Icons.backup_outlined,
                  'Backup & restore',
                  'Save and restore all business data',
                  () => context.push('/settings/backup'),
                ),
                _tile(
                  context,
                  Icons.groups_outlined,
                  'Team & devices',
                  'Invite users, set roles, manage devices',
                  () => context.push('/settings/team'),
                ),
                _tile(
                  context,
                  Icons.group_add_outlined,
                  'Join a shop',
                  'Redeem an invite code from the owner',
                  () => context.push('/settings/join'),
                ),
                _tile(
                  context,
                  Icons.devices_outlined,
                  'This device',
                  '${identity.deviceName} · ${identity.deviceCode}',
                  null,
                ),
                _tile(
                  context,
                  Icons.info_outline,
                  'About BuildStock',
                  'Version 1.0.0',
                  () => context.push('/settings/about'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionHeader(title: 'Cloud account'),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  runtime.isReady
                      ? 'Firebase project: ${runtime.app?.options.projectId ?? 'configured'}'
                      : (runtime.unavailableReason ??
                            'Firebase is not configured for this build.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (runtime.isReady && !runtime.isSignedIn)
                  FilledButton(
                    onPressed: () => _signIn(context, ref),
                    child: const Text('Sign in for cloud sync'),
                  ),
                if (runtime.isReady && runtime.isSignedIn)
                  OutlinedButton(
                    onPressed: () => _signOut(context, ref),
                    child: const Text('Sign out'),
                  ),
                if (!runtime.isReady)
                  Text(
                    'The app remains fully usable offline. See the README to '
                    'register an Android app and run flutterfire configure.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    VoidCallback? onTap,
  ) {
    return ListTile(
      leading: Icon(icon, size: 20),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: onTap == null
          ? null
          : const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }

  Future<void> _pickTheme(BuildContext context, WidgetRef ref) async {
    final current = ref.read(preferencesProvider).themeMode;
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in ThemeMode.values)
              ListTile(
                title: Text(switch (mode) {
                  ThemeMode.light => 'Light',
                  ThemeMode.dark => 'Dark',
                  ThemeMode.system => 'System',
                }),
                trailing: current == mode
                    ? const Icon(Icons.check, size: 20)
                    : null,
                onTap: () async {
                  await ref
                      .read(preferencesProvider.notifier)
                      .setThemeMode(mode);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickLanguage(BuildContext context, WidgetRef ref) async {
    final current = ref.read(preferencesProvider).locale;
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('English'),
              trailing: current.languageCode == 'en'
                  ? const Icon(Icons.check, size: 20)
                  : null,
              onTap: () async {
                await ref
                    .read(preferencesProvider.notifier)
                    .setLocale(const Locale('en'));
                if (context.mounted) Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('தமிழ் (Tamil)'),
              trailing: current.languageCode == 'ta'
                  ? const Icon(Icons.check, size: 20)
                  : null,
              onTap: () async {
                await ref
                    .read(preferencesProvider.notifier)
                    .setLocale(const Locale('ta'));
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _signIn(BuildContext context, WidgetRef ref) async {
    final email = TextEditingController();
    final password = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign in'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final services = ref.read(servicesProvider);
    try {
      await services.auth.signIn(email: email.text, password: password.text);
      final identity = await SessionService(
        services.db,
        services.runtime,
      ).load();
      await services.updateIdentity(identity);
      ref.invalidate(identityProvider);
      ref.invalidate(businessProfileProvider);
      if (context.mounted) {
        showActionMessage(context, 'Signed in. Run a sync to share data.');
      }
    } catch (error) {
      if (context.mounted) showActionMessage(context, error.toString());
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final services = ref.read(servicesProvider);
    await services.auth.signOut();
    final identity = await SessionService(services.db, services.runtime).load();
    await services.updateIdentity(identity);
    ref.invalidate(identityProvider);
    if (context.mounted) {
      showActionMessage(
        context,
        'Signed out. Local data stays on this device.',
      );
    }
  }
}

class BusinessProfileSettingsScreen extends ConsumerWidget {
  const BusinessProfileSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(businessProfileProvider).value;
    return AppFormScreen(
      title: 'Business profile',
      saveLabel: 'Save business profile',
      subtitle:
          'These values are copied into every invoice as a seller snapshot. '
          'Editing them never changes already-issued bills.',
      fields: [
        AppField(
          key: 'name',
          label: 'Business name',
          required: true,
          initial: profile?.name,
        ),
        AppField(
          key: 'ownerName',
          label: 'Owner name',
          initial: profile?.ownerName,
        ),
        AppField(
          key: 'phone',
          label: 'Primary phone',
          type: AppFieldType.phone,
          initial: profile?.phone,
        ),
        AppField(
          key: 'altPhone',
          label: 'Alternate phone',
          type: AppFieldType.phone,
          initial: profile?.altPhone,
        ),
        AppField(
          key: 'email',
          label: 'Email',
          type: AppFieldType.email,
          initial: profile?.email,
        ),
        AppField(
          key: 'address',
          label: 'Address',
          type: AppFieldType.multiline,
          initial: profile?.address,
        ),
        AppField(key: 'area', label: 'Area', initial: profile?.area),
        AppField(key: 'city', label: 'City', initial: profile?.city),
        AppField(
          key: 'district',
          label: 'District',
          initial: profile?.district,
        ),
        AppField(
          key: 'state',
          label: 'State',
          initial: profile?.state ?? 'Tamil Nadu',
        ),
        AppField(key: 'pin', label: 'PIN code', initial: profile?.pinCode),
        AppField(key: 'gstin', label: 'GSTIN', initial: profile?.gstin),
        AppField(key: 'pan', label: 'PAN', initial: profile?.pan),
        AppField(
          key: 'stateCode',
          label: 'GST state code',
          initial: profile?.stateCode ?? '33',
        ),
        AppField(
          key: 'description',
          label: 'Invoice description',
          type: AppFieldType.multiline,
          initial: profile?.description,
          helper: 'Printed below the business name, e.g. DEALERS IN CEMENT...',
        ),
        AppField(
          key: 'upi',
          label: 'UPI ID',
          initial: profile?.upiId,
          helper: 'Used only to build a UPI QR. No gateway is involved.',
        ),
        AppField(
          key: 'upiName',
          label: 'UPI payee name',
          initial: profile?.upiPayeeName,
        ),
        AppField(
          key: 'bankName',
          label: 'Bank name',
          initial: profile?.bankName,
        ),
        AppField(
          key: 'bankAccount',
          label: 'Bank account number',
          initial: profile?.bankAccountNumber,
        ),
        AppField(key: 'ifsc', label: 'IFSC', initial: profile?.ifsc),
        AppField(
          key: 'prefix',
          label: 'Invoice number prefix',
          initial: profile?.invoicePrefix ?? 'VBA',
        ),
        AppField(
          key: 'logo',
          label: 'Business logo',
          type: AppFieldType.photo,
          photoOwner: 'business',
          initial: profile?.logoRef,
        ),
        AppField(
          key: 'signature',
          label: 'Authorised signature',
          type: AppFieldType.photo,
          photoOwner: 'business',
          initial: profile?.signatureRef,
        ),
        AppField(
          key: 'stamp',
          label: 'Business stamp',
          type: AppFieldType.photo,
          photoOwner: 'business',
          initial: profile?.stampRef,
        ),
      ],
      onSave: (values) async {
        await ref
            .read(businessRepositoryProvider)
            .saveProfile(
              BusinessProfileInput(
                name: values['name'] as String? ?? '',
                ownerName: values['ownerName'] as String? ?? '',
                phone: values['phone'] as String? ?? '',
                altPhone: values['altPhone'] as String? ?? '',
                email: values['email'] as String? ?? '',
                address: values['address'] as String? ?? '',
                area: values['area'] as String? ?? '',
                city: values['city'] as String? ?? '',
                district: values['district'] as String? ?? '',
                state: values['state'] as String? ?? 'Tamil Nadu',
                pinCode: values['pin'] as String? ?? '',
                gstin: values['gstin'] as String? ?? '',
                pan: values['pan'] as String? ?? '',
                stateCode: values['stateCode'] as String? ?? '33',
                description: values['description'] as String? ?? '',
                upiId: values['upi'] as String? ?? '',
                upiPayeeName: values['upiName'] as String? ?? '',
                bankName: values['bankName'] as String? ?? '',
                bankAccountNumber: values['bankAccount'] as String? ?? '',
                ifsc: values['ifsc'] as String? ?? '',
                invoicePrefix: values['prefix'] as String? ?? 'VBA',
                logoRef: values['logo'] as String?,
                signatureRef: values['signature'] as String?,
                stampRef: values['stamp'] as String?,
                isGstRegistered: (values['gstin'] as String? ?? '').isNotEmpty,
              ),
            );
        ref.invalidate(businessProfileProvider);
      },
    );
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.apartment_rounded,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Text('BuildStock', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(
            'Offline-first business management for Vijay Balaji Agency.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          const SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What this build does'),
                SizedBox(height: 8),
                Text(
                  '• All records live in SQLite on this device.\n'
                  '• Every write is queued in a durable outbox.\n'
                  '• Firebase is used only for sharing and backup, never as the '
                  'operational source.\n'
                  '• Invoices are rendered from stored snapshots, so old bills '
                  'never change.\n'
                  '• No payment gateway: UPI QR only, with manual confirmation.\n'
                  '• No sample products, customers or transactions are included.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Version 1.0.0 · Schema 1 · Template 1',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

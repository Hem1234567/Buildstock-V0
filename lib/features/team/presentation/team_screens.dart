import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:buildstock/app/theme/app_theme.dart';
import 'package:buildstock/core/database/database_provider.dart';
import 'package:buildstock/core/domain/enums.dart';
import 'package:buildstock/core/security/permissions.dart';
import 'package:buildstock/core/utils/dates.dart';
import 'package:buildstock/core/widgets/async_view.dart';
import 'package:buildstock/core/widgets/feedback.dart';
import 'package:buildstock/core/widgets/section_card.dart';
import 'package:buildstock/features/team/data/team_repository.dart';

String _humanize(String key) {
  final text = key.replaceAll('_', ' ');
  return text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
}

/// Manage the people and devices that can use this shop.
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(identityProvider);
    final team = ref.watch(teamRepositoryProvider);

    if (!team.isAvailable) {
      return Scaffold(
        appBar: AppBar(title: const Text('Team & devices')),
        body: EmptyState(
          title: 'Sign in to manage your team',
          message: 'Team members and devices are stored in your cloud shop. Sign in on the Sync screen, or join a shop with an invite code.',
          icon: Icons.group_outlined,
          actionLabel: 'Join a shop with an invite',
          onAction: () => context.push('/settings/join'),
        ),
      );
    }
    if (!identity.can(Permissions.manageUsers)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Team & devices')),
        body: const EmptyState(
          title: 'Not allowed',
          message: 'Only the owner or an admin can manage users and devices.',
          icon: Icons.lock_outline,
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Team & devices'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Members'),
              Tab(text: 'Invites'),
              Tab(text: 'Devices'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_MembersTab(), _InvitesTab(), _DevicesTab()],
        ),
      ),
    );
  }
}

class _MembersTab extends ConsumerWidget {
  const _MembersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(teamMembersProvider);
    return AsyncView(
      value: members,
      builder: (rows) {
        if (rows.isEmpty) {
          return const EmptyState(
            title: 'No members yet',
            message: 'Invite someone from the Invites tab.',
            icon: Icons.group_outlined,
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final member = rows[index];
            return SectionCard(
              onTap: member.isOwner ? null : () => _edit(context, ref, member),
              child: Row(
                children: [
                  CircleAvatar(
                    child: Text(
                      member.displayName.isEmpty
                          ? '?'
                          : member.displayName[0].toUpperCase(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.displayName.isEmpty
                              ? member.email
                              : member.displayName,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        if (member.email.isNotEmpty)
                          Text(
                            member.email,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  StatusPill(
                    label: member.active ? _humanize(member.role) : 'Disabled',
                    color: member.active ? AppColors.info : AppColors.danger,
                    background: member.active
                        ? AppColors.infoSoft
                        : AppColors.dangerSoft,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    TeamMember member,
  ) async {
    var role = UserRole.assignable.contains(member.role)
        ? member.role
        : UserRole.staff;
    var active = member.active;
    var permissions = {
      ...(member.permissions.isEmpty
          ? RolePermissions.forRole(role)
          : member.permissions),
    };
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.85,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.displayName.isEmpty
                              ? member.email
                              : member.displayName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: role,
                          decoration: const InputDecoration(labelText: 'Role'),
                          items: [
                            for (final item in UserRole.assignable)
                              DropdownMenuItem(
                                value: item,
                                child: Text(_humanize(item)),
                              ),
                          ],
                          onChanged: (value) => setLocal(() {
                            role = value ?? role;
                            permissions = {...RolePermissions.forRole(role)};
                          }),
                        ),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Account active'),
                          value: active,
                          onChanged: (value) => setLocal(() => active = value),
                          activeTrackColor: AppColors.accent,
                        ),
                        Text(
                          'Permissions',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (final permission in Permissions.all)
                          CheckboxListTile(
                            dense: true,
                            title: Text(_humanize(permission)),
                            value: permissions.contains(permission),
                            onChanged: (value) => setLocal(() {
                              if (value == true) {
                                permissions.add(permission);
                              } else {
                                permissions.remove(permission);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Save'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (saved != true) return;
    try {
      await ref
          .read(teamRepositoryProvider)
          .updateMember(
            member.uid,
            role: role,
            active: active,
            permissions: permissions.toList()..sort(),
          );
      if (context.mounted) showActionMessage(context, 'Member updated');
    } catch (error) {
      if (context.mounted) showActionMessage(context, error.toString());
    }
  }
}

class _InvitesTab extends ConsumerWidget {
  const _InvitesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invites = ref.watch(teamInvitesProvider);
    return Stack(
      children: [
        AsyncView(
          value: invites,
          builder: (rows) {
            if (rows.isEmpty) {
              return const EmptyState(
                title: 'No invites',
                message: 'Invite a cashier, manager or driver by email. They sign in with that email and enter the code you share.',
                icon: Icons.mail_outline,
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final invite = rows[index];
                final status = invite.used
                    ? 'Used'
                    : (invite.expired ? 'Expired' : 'Pending');
                return SectionCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              invite.email,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              '${_humanize(invite.role)} · code ${invite.code}'
                              '${invite.expiresAt == null ? '' : ' · until ${AppDate.display(invite.expiresAt!)}'}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      StatusPill(
                        label: status,
                        color: invite.used
                            ? AppColors.success
                            : (invite.expired
                                  ? AppColors.danger
                                  : AppColors.warning),
                      ),
                      if (!invite.used && !invite.expired)
                        IconButton(
                          tooltip: 'Copy code',
                          icon: const Icon(Icons.copy, size: 18),
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: invite.code),
                            );
                            if (context.mounted) {
                              showActionMessage(context, 'Invite code copied');
                            }
                          },
                        ),
                      IconButton(
                        tooltip: 'Delete invite',
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => ref
                            .read(teamRepositoryProvider)
                            .revokeInvite(invite.code),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: () => _invite(context, ref),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Invite'),
          ),
        ),
      ],
    );
  }

  Future<void> _invite(BuildContext context, WidgetRef ref) async {
    final email = TextEditingController();
    var role = UserRole.cashier;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Invite a team member'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Their email'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [
                  for (final item in UserRole.assignable)
                    DropdownMenuItem(value: item, child: Text(_humanize(item))),
                ],
                onChanged: (value) => setLocal(() => role = value ?? role),
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
              child: const Text('Create invite'),
            ),
          ],
        ),
      ),
    );
    final address = email.text;
    email.dispose();
    if (confirmed != true || !context.mounted) return;
    try {
      final code = await ref
          .read(teamRepositoryProvider)
          .createInvite(email: address, role: role);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Invite created'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Share this code. It works once, for that email only, for 7 days.',
              ),
              const SizedBox(height: 12),
              SelectableText(
                code,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Copy and close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (context.mounted) showActionMessage(context, error.toString());
    }
  }
}

class _DevicesTab extends ConsumerWidget {
  const _DevicesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(teamDevicesProvider);
    return AsyncView(
      value: devices,
      builder: (rows) {
        if (rows.isEmpty) {
          return const EmptyState(
            title: 'No devices registered',
            message: 'Devices appear here after their first sync.',
            icon: Icons.devices_other_outlined,
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final device = rows[index];
            return SectionCard(
              child: Row(
                children: [
                  const Icon(Icons.phone_android),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${device.name}${device.isThisDevice ? ' (this device)' : ''}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          [
                            if (device.userName.isNotEmpty) device.userName,
                            if (device.platform.isNotEmpty) device.platform,
                            if (device.lastSeenAt != null)
                              'seen ${AppDate.display(device.lastSeenAt!)} ${AppDate.time(device.lastSeenAt!)}',
                          ].join(' · '),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (!device.isThisDevice) ...[
                    Switch.adaptive(
                      value: device.active,
                      activeTrackColor: AppColors.accent,
                      onChanged: (value) async {
                        try {
                          await ref
                              .read(teamRepositoryProvider)
                              .setDeviceActive(device.id, value);
                        } catch (error) {
                          if (context.mounted) {
                            showActionMessage(context, error.toString());
                          }
                        }
                      },
                    ),
                    IconButton(
                      tooltip: 'Remove device',
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () async {
                        try {
                          await ref
                              .read(teamRepositoryProvider)
                              .removeDevice(device.id);
                        } catch (error) {
                          if (context.mounted) {
                            showActionMessage(context, error.toString());
                          }
                        }
                      },
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Redeem an invite code to join another shop as a team member.
class JoinShopScreen extends ConsumerStatefulWidget {
  const JoinShopScreen({super.key});

  @override
  ConsumerState<JoinShopScreen> createState() => _JoinShopScreenState();
}

class _JoinShopScreenState extends ConsumerState<JoinShopScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(teamRepositoryProvider).acceptInvite(_code.text);
      if (!mounted) return;
      showActionMessage(context, 'You joined the shop');
      context.go('/');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(authServiceProvider).isSignedIn;
    return Scaffold(
      appBar: AppBar(title: const Text('Join a shop')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enter the invite code from the shop owner.',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  signedIn
                      ? 'You must be signed in with the email address the owner invited.'
                      : 'Sign in first (Settings > Sync), using the email address the owner invited.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Invite code'),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy || !signedIn ? null : _join,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Join shop'),
          ),
        ],
      ),
    );
  }
}

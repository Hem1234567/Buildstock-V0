import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:buildstock/app/theme/app_theme.dart';
import 'package:buildstock/core/database/database_provider.dart';
import 'package:buildstock/core/session/session_service.dart';
import 'package:buildstock/core/utils/validators.dart';
import 'package:buildstock/core/widgets/section_card.dart';
import 'package:buildstock/features/business/data/business_repository.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController(text: 'Vijay Balaji Agency');
  final _owner = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController(text: 'Chennai');
  final _state = TextEditingController(text: 'Tamil Nadu');
  final _pin = TextEditingController(text: '600056');
  final _gstin = TextEditingController();
  final _upi = TextEditingController();
  final _prefix = TextEditingController(text: 'VBA');
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _gstRegistered = false;
  bool _saving = false;
  bool _authExpanded = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _owner,
      _phone,
      _address,
      _city,
      _state,
      _pin,
      _gstin,
      _upi,
      _prefix,
      _email,
      _password,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final runtime = ref.watch(firebaseRuntimeProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.apartment_rounded,
                      color: theme.colorScheme.onPrimary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Set up Vijay Balaji Agency',
                    style: theme.textTheme.displaySmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Enter your real business details. They appear on every '
                    'invoice and can be edited later. BuildStock never inserts '
                    'sample products, customers or transactions.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Business details',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: _name,
                          decoration: const InputDecoration(
                            labelText: 'Business name',
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Business name is required'
                              : null,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _owner,
                                decoration: const InputDecoration(
                                  labelText: 'Owner name',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _phone,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  labelText: 'Primary phone',
                                ),
                                validator: (value) => _phoneMessage(
                                  Validators.phone(value, required: true),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _address,
                          minLines: 1,
                          decoration: const InputDecoration(
                            labelText: 'Street address',
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _city,
                                decoration: const InputDecoration(
                                  labelText: 'City',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _state,
                                decoration: const InputDecoration(
                                  labelText: 'State',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _pin,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'PIN',
                                ),
                                validator: (value) =>
                                    Validators.pinCode(value) == null
                                    ? null
                                    : 'Invalid PIN',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _prefix,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Invoice prefix',
                            helperText: 'Example: VBA-2026-DEVXXX-000001',
                          ),
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? 'Prefix is required'
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tax & payments',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: _gstRegistered,
                          onChanged: (value) =>
                              setState(() => _gstRegistered = value),
                          title: const Text('GST registered'),
                          subtitle: const Text(
                            'Add your GSTIN and state code to print tax invoices.',
                          ),
                          activeTrackColor: AppColors.accent,
                        ),
                        if (_gstRegistered) ...[
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _gstin,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'GSTIN',
                            ),
                            validator: (value) =>
                                _gstRegistered &&
                                    Validators.gstin(value, required: true) !=
                                        null
                                ? 'Enter a valid 15-character GSTIN'
                                : null,
                          ),
                          const SizedBox(height: 10),
                        ],
                        TextFormField(
                          controller: _upi,
                          decoration: const InputDecoration(
                            labelText: 'UPI ID (for payment QR)',
                            hintText: 'businessname@bank',
                            helperText: 'Used only to generate a UPI QR. No payment gateway is involved.',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () =>
                              setState(() => _authExpanded = !_authExpanded),
                          child: Row(
                            children: [
                              Icon(
                                runtime.isReady
                                    ? Icons.cloud_done_outlined
                                    : Icons.cloud_off_outlined,
                                size: 18,
                                color: runtime.isReady
                                    ? AppColors.success
                                    : AppColors.warning,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  runtime.isReady
                                      ? 'Cloud sync (optional)'
                                      : 'Offline mode',
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                              Icon(
                                _authExpanded
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          runtime.isReady
                              ? 'Sign in to share this shop across devices. '
                                    'The app works fully offline without signing in.'
                              : (runtime.unavailableReason ??
                                    'Firebase is not configured on this build. '
                                        'All business features work offline.'),
                          style: theme.textTheme.bodySmall,
                        ),
                        if (runtime.isReady && _authExpanded) ...[
                          const SizedBox(height: AppSpacing.md),
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _password,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Password',
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _saving ? null : _signIn,
                                  child: const Text('Sign in'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _saving ? null : _signUp,
                                  child: const Text('Create account'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Start using BuildStock'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'By continuing you confirm these details are accurate. '
                    'Amounts are stored in paise and quantities to three decimals.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _phoneMessage(String? code) =>
      code == null ? null : 'Enter a valid 10-digit mobile number';

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repository = ref.read(businessRepositoryProvider);
      await repository.saveProfile(
        BusinessProfileInput(
          name: _name.text.trim(),
          ownerName: _owner.text.trim(),
          phone: _phone.text.trim(),
          email: _email.text.trim(),
          address: _address.text.trim(),
          city: _city.text.trim(),
          state: _state.text.trim(),
          pinCode: _pin.text.trim(),
          gstin: _gstRegistered ? _gstin.text.trim().toUpperCase() : '',
          upiId: _upi.text.trim(),
          upiPayeeName: _name.text.trim(),
          invoicePrefix: _prefix.text.trim(),
          description: 'DEALERS IN CEMENT, BRICKS, SAND, JELLY AND GRAVEL',
          isGstRegistered: _gstRegistered,
        ),
      );
      ref.invalidate(businessProfileProvider);
      if (mounted) context.go('/');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendly(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signIn() async {
    await _authenticate(create: false);
  }

  Future<void> _signUp() async {
    await _authenticate(create: true);
  }

  Future<void> _authenticate({required bool create}) async {
    if (_email.text.trim().isEmpty || _password.text.length < 6) {
      setState(
        () => _error = 'Enter an email and a password of 6+ characters.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final services = ref.read(servicesProvider);
      final auth = services.auth;
      if (create) {
        await auth.signUp(
          email: _email.text,
          password: _password.text,
          displayName: _owner.text.trim().isEmpty
              ? _name.text.trim()
              : _owner.text.trim(),
        );
      } else {
        await auth.signIn(email: _email.text, password: _password.text);
      }
      final identity = await SessionService(
        services.db,
        services.runtime,
      ).load();
      await services.updateIdentity(identity);
      ref.invalidate(identityProvider);
      ref.invalidate(businessProfileProvider);
      setState(() => _authExpanded = false);
    } catch (error) {
      if (mounted) setState(() => _error = _friendly(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _friendly(Object error) {
    final text = error.toString();
    if (text.contains('email-already-in-use')) {
      return 'That email already has an account. Sign in instead.';
    }
    if (text.contains('wrong-password') ||
        text.contains('invalid-credential')) {
      return 'Email or password is incorrect.';
    }
    if (text.contains('network')) {
      return 'Network unavailable. You can continue offline.';
    }
    return text.replaceFirst('Exception: ', '');
  }
}

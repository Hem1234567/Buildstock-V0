import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:buildstock/app/theme/app_theme.dart';
import 'package:buildstock/core/utils/money.dart';
import 'package:buildstock/core/utils/quantity.dart';
import 'package:buildstock/core/utils/validators.dart';
import 'package:buildstock/core/scanner/barcode_scanner_screen.dart';
import 'package:buildstock/core/widgets/photo_field.dart';
import 'package:buildstock/core/widgets/section_card.dart';

enum AppFieldType {
  text,
  multiline,
  phone,
  email,
  money,
  quantity,
  number,
  percent,
  date,
  dropdown,
  toggle,
  photo,
}

class AppFieldOption {
  const AppFieldOption(this.value, this.label);
  final String value;
  final String label;
}

/// Declarative field used by the shared form screen. Keeping field definitions
/// next to the entity screen avoids duplicating validation and formatting code
/// across a dozen master-data forms.
class AppField {
  const AppField({
    required this.key,
    required this.label,
    this.type = AppFieldType.text,
    this.required = false,
    this.initial,
    this.hint,
    this.helper,
    this.options = const [],
    this.enabled = true,
    this.minLines = 3,
    this.maxLength,
    this.photoOwner = 'general',
    this.scannable = false,
  });

  final String key;
  final String label;
  final AppFieldType type;
  final bool required;
  final Object? initial;
  final String? hint;
  final String? helper;
  final List<AppFieldOption> options;
  final bool enabled;
  final int minLines;
  final int? maxLength;

  /// For [AppFieldType.photo]: the kind of record the photo belongs to.
  final String photoOwner;

  /// Shows a camera button that fills the text field with a scanned code.
  final bool scannable;
}

class AppFormScreen extends StatefulWidget {
  const AppFormScreen({
    super.key,
    required this.title,
    required this.fields,
    required this.onSave,
    this.subtitle,
    this.saveLabel = 'Save',
    this.onDelete,
    this.deleteLabel = 'Delete',
    this.header,
  });

  final String title;
  final String? subtitle;
  final List<AppField> fields;
  final Future<void> Function(Map<String, Object?> values) onSave;
  final String saveLabel;
  final Future<void> Function()? onDelete;
  final String deleteLabel;
  final Widget? header;

  @override
  State<AppFormScreen> createState() => _AppFormScreenState();
}

class _AppFormScreenState extends State<AppFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String?> _dropdowns = {};
  final Map<String, bool> _toggles = {};
  final Map<String, DateTime?> _dates = {};
  final Map<String, String?> _photos = {};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final field in widget.fields) {
      switch (field.type) {
        case AppFieldType.toggle:
          _toggles[field.key] = field.initial == true;
        case AppFieldType.photo:
          _photos[field.key] = field.initial?.toString();
        case AppFieldType.dropdown:
          _dropdowns[field.key] = field.initial?.toString();
        case AppFieldType.date:
          _dates[field.key] = field.initial is DateTime
              ? field.initial as DateTime
              : null;
        case AppFieldType.money:
          final paise = field.initial is int ? field.initial as int : 0;
          _controllers[field.key] = TextEditingController(
            text: paise == 0 ? '' : (paise / 100).toStringAsFixed(2),
          );
        case AppFieldType.quantity:
          final milli = field.initial is int ? field.initial as int : 0;
          _controllers[field.key] = TextEditingController(
            text: milli == 0 ? '' : Quantity.format(milli),
          );
        case AppFieldType.percent:
          final bps = field.initial is int ? field.initial as int : 0;
          _controllers[field.key] = TextEditingController(
            text: bps == 0 ? '' : (bps / 100).toString(),
          );
        default:
          _controllers[field.key] = TextEditingController(
            text: field.initial?.toString() ?? '',
          );
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.onDelete != null)
            IconButton(
              tooltip: widget.deleteLabel,
              onPressed: _saving ? null : _confirmDelete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final sidePad = constraints.maxWidth > 800
                ? (constraints.maxWidth - 760) / 2
                : 20.0;
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(sidePad, 8, sidePad, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.header != null) ...[
                      widget.header!,
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    if (widget.subtitle != null) ...[
                      Text(widget.subtitle!, style: theme.textTheme.bodySmall),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    for (final field in widget.fields) ...[
                      _buildField(field),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _error!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(
                      onPressed: _saving ? null : _submit,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(widget.saveLabel),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildField(AppField field) {
    switch (field.type) {
      case AppFieldType.photo:
        return PhotoPickerField(
          label: field.label,
          helper: field.helper,
          ownerType: field.photoOwner,
          role: field.key,
          enabled: field.enabled,
          initialRef: _photos[field.key],
          onChanged: (value) => _photos[field.key] = value,
        );
      case AppFieldType.toggle:
        return SectionCard(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          child: SwitchListTile.adaptive(
            value: _toggles[field.key] ?? false,
            onChanged: field.enabled
                ? (value) => setState(() => _toggles[field.key] = value)
                : null,
            title: Text(field.label),
            subtitle: field.helper == null ? null : Text(field.helper!),
            activeTrackColor: AppColors.accent,
          ),
        );
      case AppFieldType.dropdown:
        return DropdownButtonFormField<String>(
          initialValue: _dropdowns[field.key],
          isExpanded: true,
          decoration: InputDecoration(
            labelText: field.label,
            helperText: field.helper,
            helperMaxLines: 2,
          ),
          items: field.options
              .map(
                (option) => DropdownMenuItem(
                  value: option.value,
                  child: Text(option.label, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: field.enabled
              ? (value) => setState(() => _dropdowns[field.key] = value)
              : null,
          validator: (value) {
            if (field.required && (value == null || value.isEmpty)) {
              return 'This field is required';
            }
            return null;
          },
        );
      case AppFieldType.date:
        return InkWell(
          borderRadius: BorderRadius.circular(AppRadius.field),
          onTap: field.enabled ? () => _pickDate(field) : null,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: field.label,
              helperText: field.helper,
              suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
            ),
            child: Text(
              _dates[field.key] == null
                  ? 'Select date'
                  : _formatDate(_dates[field.key]!),
              style: TextStyle(
                color: _dates[field.key] == null
                    ? Theme.of(context).hintColor
                    : null,
              ),
            ),
          ),
        );
      default:
        final keyboardType = switch (field.type) {
          AppFieldType.phone || AppFieldType.number => TextInputType.number,
          AppFieldType.money || AppFieldType.quantity || AppFieldType.percent =>
            const TextInputType.numberWithOptions(decimal: true),
          AppFieldType.email => TextInputType.emailAddress,
          AppFieldType.multiline => TextInputType.multiline,
          _ => TextInputType.text,
        };
        final prefix = switch (field.type) {
          AppFieldType.money => '₹ ',
          AppFieldType.percent => null,
          _ => null,
        };
        final suffix = switch (field.type) {
          AppFieldType.percent => '%',
          AppFieldType.quantity => 'units',
          _ => null,
        };
        return TextFormField(
          controller: _controllers[field.key],
          enabled: field.enabled,
          keyboardType: keyboardType,
          minLines: field.type == AppFieldType.multiline ? field.minLines : 1,
          maxLines: field.type == AppFieldType.multiline ? 5 : 1,
          maxLength: field.maxLength,
          textCapitalization: field.type == AppFieldType.email
              ? TextCapitalization.none
              : TextCapitalization.sentences,
          inputFormatters: [
            if (field.type == AppFieldType.phone)
              FilteringTextInputFormatter.digitsOnly,
            if (field.type == AppFieldType.phone)
              LengthLimitingTextInputFormatter(10),
            if (field.type == AppFieldType.money ||
                field.type == AppFieldType.quantity ||
                field.type == AppFieldType.percent)
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          decoration: InputDecoration(
            labelText: field.label,
            hintText: field.hint,
            helperText: field.helper,
            prefixText: prefix,
            suffixText: suffix,
            suffixIcon: field.scannable
                ? IconButton(
                    tooltip: 'Scan',
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: () async {
                      final code = await BarcodeScannerScreen.open(context);
                      if (code != null) {
                        _controllers[field.key]?.text = code;
                      }
                    },
                  )
                : null,
          ),
          validator: (value) => _validate(field, value),
        );
    }
  }

  String? _validate(AppField field, String? value) {
    switch (field.type) {
      case AppFieldType.phone:
        final error = Validators.phone(value, required: field.required);
        return _message(error);
      case AppFieldType.email:
        final error = Validators.email(value, required: field.required);
        return _message(error);
      case AppFieldType.money:
        final error = Validators.amount(value, allowZero: !field.required);
        return _message(error);
      case AppFieldType.quantity:
        final error = Validators.quantity(value, allowZero: !field.required);
        return _message(error);
      case AppFieldType.percent:
        return _message(Validators.percentage(value));
      case AppFieldType.number:
        if ((value ?? '').trim().isEmpty) {
          return field.required ? 'This field is required' : null;
        }
        if (int.tryParse(value!.trim()) == null) return 'Enter a valid number';
        return null;
      default:
        if (field.required && (value ?? '').trim().isEmpty) {
          return 'This field is required';
        }
        return null;
    }
  }

  String? _message(String? code) => switch (code) {
    null => null,
    'required' => 'This field is required',
    'invalid_phone' => 'Enter a valid 10-digit mobile number',
    'invalid_email' => 'Enter a valid email address',
    'invalid_number' => 'Enter a valid number',
    'negative' => 'Value cannot be negative',
    'zero' => 'Value must be greater than zero',
    'out_of_range' => 'Enter a value between 0 and 100',
    _ => 'Check this field',
  };

  Future<void> _pickDate(AppField field) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dates[field.key] ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 15),
    );
    if (picked != null) {
      setState(() => _dates[field.key] = picked);
    }
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  Map<String, Object?> _collect() {
    final values = <String, Object?>{};
    for (final field in widget.fields) {
      switch (field.type) {
        case AppFieldType.toggle:
          values[field.key] = _toggles[field.key] ?? false;
        case AppFieldType.photo:
          values[field.key] = _photos[field.key];
        case AppFieldType.dropdown:
          values[field.key] = _dropdowns[field.key];
        case AppFieldType.date:
          values[field.key] = _dates[field.key];
        case AppFieldType.money:
          values[field.key] = Money.tryParseRupees(
            _controllers[field.key]?.text,
          );
        case AppFieldType.quantity:
          values[field.key] = Quantity.tryParseMilli(
            _controllers[field.key]?.text,
          );
        case AppFieldType.percent:
          final percent =
              double.tryParse(_controllers[field.key]?.text ?? '') ?? 0;
          values[field.key] = (percent * 100).round();
        case AppFieldType.number:
          values[field.key] = int.tryParse(
            _controllers[field.key]?.text.trim() ?? '',
          );
        case AppFieldType.phone:
          values[field.key] = _controllers[field.key]?.text.replaceAll(
            RegExp(r'\s'),
            '',
          );
        default:
          values[field.key] = _controllers[field.key]?.text.trim();
      }
    }
    return values;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_collect());
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.deleteLabel),
        content: const Text(
          'This record is archived, not erased, so historical documents remain '
          'intact. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.onDelete!();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }
}

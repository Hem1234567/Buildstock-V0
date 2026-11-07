import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:buildstock/app/theme/app_theme.dart';
import 'package:buildstock/core/media/image_service.dart';
import 'package:buildstock/core/widgets/business_image.dart';

/// Camera / gallery photo picker used by forms (products, customers, staff,
/// logo, signature, stamp and so on). The value is a local file path until the
/// photo is uploaded, after which the stored reference becomes its public URL.
class PhotoPickerField extends ConsumerStatefulWidget {
  const PhotoPickerField({
    super.key,
    required this.label,
    required this.ownerType,
    required this.onChanged,
    this.initialRef,
    this.role = 'primary',
    this.helper,
    this.enabled = true,
  });

  final String label;
  final String ownerType;
  final String role;
  final String? initialRef;
  final String? helper;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  ConsumerState<PhotoPickerField> createState() => _PhotoPickerFieldState();
}

class _PhotoPickerFieldState extends ConsumerState<PhotoPickerField> {
  String? _ref;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialRef?.trim();
    _ref = (initial == null || initial.isEmpty) ? null : initial;
  }

  Future<void> _pick(ImageSource source) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final image = await ref
          .read(imageServiceProvider)
          .pick(source: source, ownerType: widget.ownerType, role: widget.role);
      if (image != null && mounted) {
        setState(() => _ref = image.path);
        widget.onChanged(image.path);
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not get the photo: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _remove() {
    setState(() => _ref = null);
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = businessImage(_ref, fit: BoxFit.cover);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 84,
              height: 84,
              color: theme.colorScheme.surfaceContainerHighest,
              child:
                  preview ??
                  Icon(
                    Icons.add_a_photo_outlined,
                    color: theme.hintColor,
                    size: 28,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.label, style: theme.textTheme.titleSmall),
                if (widget.helper != null)
                  Text(widget.helper!, style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                if (_busy)
                  const LinearProgressIndicator()
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      OutlinedButton.icon(
                        onPressed: widget.enabled
                            ? () => _pick(ImageSource.camera)
                            : null,
                        icon: const Icon(Icons.photo_camera_outlined, size: 18),
                        label: const Text('Camera'),
                      ),
                      OutlinedButton.icon(
                        onPressed: widget.enabled
                            ? () => _pick(ImageSource.gallery)
                            : null,
                        icon: const Icon(
                          Icons.photo_library_outlined,
                          size: 18,
                        ),
                        label: const Text('Gallery'),
                      ),
                      if (_ref != null)
                        TextButton(
                          onPressed: widget.enabled ? _remove : null,
                          child: const Text('Remove'),
                        ),
                    ],
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.danger,
                      ),
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

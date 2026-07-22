import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:nexgen_command/theme.dart';

/// Dark-themed text field used by every wizard step. Matches the styling
/// already used in [ZoneEditorSheet] and [ProspectInfoScreen] so the
/// wizard feels visually continuous with the rest of the sales flow.
class WizardTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final TextCapitalization textCapitalization;

  const WizardTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.icon,
    this.keyboardType,
    this.inputFormatters,
    this.maxLines = 1,
    this.onChanged,
    this.textCapitalization = TextCapitalization.sentences,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      onChanged: onChanged,
      textCapitalization: textCapitalization,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: NexGenPalette.textMedium),
        hintText: hint,
        hintStyle: TextStyle(
          color: NexGenPalette.textMedium.withValues(alpha: 0.5),
        ),
        prefixIcon:
            icon != null ? Icon(icon, color: NexGenPalette.textMedium) : null,
        filled: true,
        fillColor: NexGenPalette.gunmetal90,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: NexGenPalette.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: NexGenPalette.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: NexGenPalette.cyan),
        ),
      ),
    );
  }
}

/// A boxed section header used inside step bodies (e.g. "Channel runs",
/// "Power injection points").
class WizardSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const WizardSectionHeader({super.key, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: NexGenPalette.cyan,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}

/// A horizontal segmented selector used by Step 2 (interior/exterior)
/// and Step 3 (run direction).
class WizardSegmentedSelector<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T value) labelBuilder;
  final ValueChanged<T> onChanged;

  const WizardSegmentedSelector({
    super.key,
    required this.values,
    required this.selected,
    required this.labelBuilder,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values.map((v) {
        final isSelected = v == selected;
        return GestureDetector(
          onTap: () => onChanged(v),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? NexGenPalette.cyan.withValues(alpha: 0.15)
                  : NexGenPalette.gunmetal90,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? NexGenPalette.cyan : NexGenPalette.line,
              ),
            ),
            child: Text(
              labelBuilder(v),
              style: TextStyle(
                color: isSelected
                    ? NexGenPalette.cyan
                    : NexGenPalette.textMedium,
                fontSize: 13,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

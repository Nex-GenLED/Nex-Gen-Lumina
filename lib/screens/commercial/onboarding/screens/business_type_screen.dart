import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/screens/commercial/onboarding/commercial_onboarding_state.dart';

const _businessTypes = <_BizType>[
  _BizType('bar_nightclub', 'Bar / Nightclub', Icons.local_bar),
  _BizType('restaurant_casual', 'Restaurant Casual', Icons.restaurant),
  _BizType('restaurant_fine_dining', 'Fine Dining', Icons.dinner_dining),
  _BizType('fast_casual', 'Fast Casual / QSR', Icons.fastfood),
  _BizType('retail_boutique', 'Retail Boutique', Icons.storefront),
  _BizType('retail_chain', 'Retail Chain / Multi-Unit', Icons.store),
  _BizType('entertainment_venue', 'Entertainment Venue', Icons.theater_comedy),
  _BizType('other', 'Other', Icons.more_horiz),
];

class _BizType {
  final String key;
  final String label;
  final IconData icon;
  const _BizType(this.key, this.label, this.icon);
}

class BusinessTypeScreen extends ConsumerStatefulWidget {
  const BusinessTypeScreen({super.key, required this.onNext});
  final VoidCallback onNext;

  @override
  ConsumerState<BusinessTypeScreen> createState() => _BusinessTypeScreenState();
}

class _BusinessTypeScreenState extends ConsumerState<BusinessTypeScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _otherCtrl;
  String? _nameError;
  String? _typeError;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(commercialOnboardingProvider);
    _nameCtrl = TextEditingController(text: draft.businessName);
    _addressCtrl = TextEditingController(text: draft.primaryAddress);
    _otherCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _otherCtrl.dispose();
    super.dispose();
  }

  void _selectType(String key) {
    ref.read(commercialOnboardingProvider.notifier).update(
          (d) => d.copyWith(businessType: key),
        );
    setState(() => _typeError = null);
  }

  void _validate() {
    final draft = ref.read(commercialOnboardingProvider);
    setState(() {
      _nameError =
          _nameCtrl.text.trim().isEmpty ? 'Business name is required' : null;
      _typeError =
          draft.businessType.isEmpty ? 'Select a business type' : null;
    });
    if (_nameError != null || _typeError != null) return;

    ref.read(commercialOnboardingProvider.notifier).update(
          (d) => d.copyWith(
            businessName: _nameCtrl.text.trim(),
            primaryAddress: _addressCtrl.text.trim(),
          ),
        );
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(
      commercialOnboardingProvider.select((d) => d.businessType),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(
          'What type of business are you?',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(color: NexGenPalette.textHigh),
        ),
        const SizedBox(height: 16),

        // ── Business type grid ──────────────────────────────────────────
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: _businessTypes.map((t) {
            final isSelected = selected == t.key;
            return GestureDetector(
              onTap: () => _selectType(t.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: isSelected
                      ? NexGenPalette.cyan.withValues(alpha: 0.12)
                      : NexGenPalette.gunmetal90,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? NexGenPalette.cyan : NexGenPalette.line,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      t.icon,
                      size: 28,
                      color: isSelected
                          ? NexGenPalette.cyan
                          : NexGenPalette.textMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected
                            ? NexGenPalette.cyan
                            : NexGenPalette.textHigh,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),

        if (_typeError != null) ...[
          const SizedBox(height: 6),
          Text(_typeError!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
        ],

        // ── "Other" descriptor ──────────────────────────────────────────
        if (selected == 'other') ...[
          const SizedBox(height: 12),
          TextField(
            controller: _otherCtrl,
            style: const TextStyle(color: NexGenPalette.textHigh),
            decoration: _inputDecoration('Describe your business'),
          ),
        ],

        const SizedBox(height: 24),

        // ── Business Name ───────────────────────────────────────────────
        TextField(
          controller: _nameCtrl,
          style: const TextStyle(color: NexGenPalette.textHigh),
          decoration: _inputDecoration('Business Name').copyWith(
            errorText: _nameError,
          ),
          onChanged: (_) => setState(() => _nameError = null),
        ),
        const SizedBox(height: 16),

        // ── Primary Address ─────────────────────────────────────────────
        TextField(
          controller: _addressCtrl,
          style: const TextStyle(color: NexGenPalette.textHigh),
          decoration: _inputDecoration('Primary Address').copyWith(
            helperText: 'Used to suggest your local sports teams',
            helperStyle: TextStyle(
              color: NexGenPalette.textMedium.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(height: 32),

        // ── Next button ─────────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _validate,
            style: ElevatedButton.styleFrom(
              backgroundColor: NexGenPalette.cyan,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Next', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: NexGenPalette.textMedium),
      filled: true,
      fillColor: NexGenPalette.gunmetal90,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: NexGenPalette.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: NexGenPalette.cyan),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    );
  }
}

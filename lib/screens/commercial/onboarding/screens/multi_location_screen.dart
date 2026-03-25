import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/screens/commercial/onboarding/commercial_onboarding_state.dart';

class MultiLocationScreen extends ConsumerStatefulWidget {
  const MultiLocationScreen({super.key, required this.onNext});
  final VoidCallback onNext;

  @override
  ConsumerState<MultiLocationScreen> createState() =>
      _MultiLocationScreenState();
}

class _MultiLocationScreenState extends ConsumerState<MultiLocationScreen> {
  late final TextEditingController _orgNameCtrl;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(commercialOnboardingProvider);
    _orgNameCtrl = TextEditingController(text: draft.orgName.isNotEmpty ? draft.orgName : draft.businessName);
  }

  @override
  void dispose() {
    _orgNameCtrl.dispose();
    super.dispose();
  }

  bool get _shouldShow {
    final draft = ref.read(commercialOnboardingProvider);
    return draft.businessType == 'retail_chain' || draft.hasMultipleLocations;
  }

  void _addLocation() {
    ref.read(commercialOnboardingProvider.notifier).update((d) {
      return d.copyWith(
        locations: [...d.locations, const LocationDraft()],
      );
    });
  }

  void _removeLocation(int index) {
    ref.read(commercialOnboardingProvider.notifier).update((d) {
      final list = List<LocationDraft>.from(d.locations)..removeAt(index);
      return d.copyWith(locations: list);
    });
  }

  void _updateLocation(int index, LocationDraft updated) {
    ref.read(commercialOnboardingProvider.notifier).update((d) {
      final list = List<LocationDraft>.from(d.locations);
      list[index] = updated;
      return d.copyWith(locations: list);
    });
  }

  void _save() {
    ref.read(commercialOnboardingProvider.notifier).update(
          (d) => d.copyWith(orgName: _orgNameCtrl.text.trim()),
        );
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    // Auto-skip if not a multi-location business type.
    if (!_shouldShow) {
      return _SingleLocationFallback(onNext: widget.onNext);
    }

    final draft = ref.watch(commercialOnboardingProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text('Multi-Location Setup',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: NexGenPalette.textHigh)),
        const SizedBox(height: 16),

        // Org name
        TextField(
          controller: _orgNameCtrl,
          style: const TextStyle(color: NexGenPalette.textHigh),
          decoration: _inputDeco('Organization Name'),
        ),
        const SizedBox(height: 20),

        // Template checkbox
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: draft.applyTemplateToAll,
          activeColor: NexGenPalette.cyan,
          onChanged: (v) => ref
              .read(commercialOnboardingProvider.notifier)
              .update((d) => d.copyWith(applyTemplateToAll: v ?? true)),
          title: const Text(
            'Apply this setup as the template for all locations',
            style: TextStyle(color: NexGenPalette.textHigh, fontSize: 14),
          ),
          subtitle: const Text(
            'Channels, day-parts, and coverage policies will be copied. Hours can still differ per location.',
            style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
          ),
        ),
        const SizedBox(height: 16),

        // Location cards
        ...draft.locations.asMap().entries.map((e) => _LocationCard(
              index: e.key,
              location: e.value,
              useTemplate: draft.applyTemplateToAll,
              onUpdate: (loc) => _updateLocation(e.key, loc),
              onRemove: () => _removeLocation(e.key),
            )),

        // Add location
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            onPressed: _addLocation,
            icon: const Icon(Icons.add_location_alt, size: 18),
            label: const Text('Add Location'),
            style: OutlinedButton.styleFrom(
              foregroundColor: NexGenPalette.cyan,
              side: const BorderSide(color: NexGenPalette.cyan),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),

        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: NexGenPalette.cyan,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Next', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDeco(String label) => InputDecoration(
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
      );
}

// ---------------------------------------------------------------------------
// Single-location fallback
// ---------------------------------------------------------------------------

class _SingleLocationFallback extends StatelessWidget {
  const _SingleLocationFallback({required this.onNext});
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 32),
      child: Column(
        children: [
          const Icon(Icons.store, size: 48, color: NexGenPalette.textMedium),
          const SizedBox(height: 16),
          Text(
            'Single Location',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: NexGenPalette.textHigh),
          ),
          const SizedBox(height: 8),
          const Text(
            'Multi-location setup is available for Retail Chain and multi-unit businesses. You can add locations later from your commercial dashboard.',
            textAlign: TextAlign.center,
            style: TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: NexGenPalette.cyan,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Just one location for now',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Location card
// ---------------------------------------------------------------------------

class _LocationCard extends StatefulWidget {
  const _LocationCard({
    required this.index,
    required this.location,
    required this.useTemplate,
    required this.onUpdate,
    required this.onRemove,
  });
  final int index;
  final LocationDraft location;
  final bool useTemplate;
  final ValueChanged<LocationDraft> onUpdate;
  final VoidCallback onRemove;

  @override
  State<_LocationCard> createState() => _LocationCardState();
}

class _LocationCardState extends State<_LocationCard> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _addrCtrl;
  late final TextEditingController _mgrNameCtrl;
  late final TextEditingController _mgrEmailCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.location.locationName);
    _addrCtrl = TextEditingController(text: widget.location.address);
    _mgrNameCtrl = TextEditingController(text: widget.location.managerName);
    _mgrEmailCtrl = TextEditingController(text: widget.location.managerEmail);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addrCtrl.dispose();
    _mgrNameCtrl.dispose();
    _mgrEmailCtrl.dispose();
    super.dispose();
  }

  void _sync() {
    widget.onUpdate(widget.location.copyWith(
      locationName: _nameCtrl.text.trim(),
      address: _addrCtrl.text.trim(),
      managerName: _mgrNameCtrl.text.trim(),
      managerEmail: _mgrEmailCtrl.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Location ${widget.index + 1}',
                    style: const TextStyle(
                        color: NexGenPalette.textHigh,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
              ),
              if (widget.useTemplate)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: NexGenPalette.cyan.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.3)),
                  ),
                  child: const Text('Template Applied',
                      style: TextStyle(color: NexGenPalette.cyan, fontSize: 10)),
                ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: widget.onRemove,
                child: const Icon(Icons.close, size: 16, color: Colors.redAccent),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _field(_nameCtrl, 'Location Name'),
          const SizedBox(height: 8),
          _field(_addrCtrl, 'Address'),
          const SizedBox(height: 10),
          const Text('Location Manager',
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12)),
          const SizedBox(height: 6),
          _field(_mgrNameCtrl, 'Manager Name'),
          const SizedBox(height: 8),
          _field(_mgrEmailCtrl, 'Manager Email'),
          const SizedBox(height: 8),
          // Role selector
          Row(
            children: [
              const Text('Role: ', style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12)),
              ...['storeManager', 'corporateAdmin'].map((role) {
                final isActive = widget.location.managerRole == role;
                final label = role == 'storeManager' ? 'Store Manager' : 'Corporate Admin';
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(label, style: const TextStyle(fontSize: 11)),
                    selected: isActive,
                    selectedColor: NexGenPalette.cyan.withValues(alpha: 0.15),
                    backgroundColor: NexGenPalette.gunmetal,
                    labelStyle: TextStyle(
                        color: isActive ? NexGenPalette.cyan : NexGenPalette.textMedium),
                    side: BorderSide(
                        color: isActive ? NexGenPalette.cyan : NexGenPalette.line),
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) {
                      widget.onUpdate(widget.location.copyWith(managerRole: role));
                    },
                  ),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: NexGenPalette.textHigh, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: NexGenPalette.textMedium),
        isDense: true,
        filled: true,
        fillColor: NexGenPalette.matteBlack,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: NexGenPalette.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: NexGenPalette.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: NexGenPalette.cyan),
        ),
      ),
      onChanged: (_) => _sync(),
    );
  }
}

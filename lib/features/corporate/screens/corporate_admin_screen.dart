import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/corporate/models/network_announcement.dart';
import 'package:nexgen_command/features/corporate/providers/corporate_admin_providers.dart';
import 'package:nexgen_command/features/corporate/providers/corporate_providers.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';
import 'package:nexgen_command/services/commercial/brand_library_providers.dart';
import 'package:nexgen_command/theme.dart';

/// Corporate Admin tab.
///
/// Four sections: Dealer Management, Pricing Defaults, Network
/// Announcements, System PINs. Replaces the Admin tab stub on the
/// corporate dashboard.
class CorporateAdminScreen extends ConsumerWidget {
  const CorporateAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _DealerManagementSection(),
          SizedBox(height: 16),
          _BrandLibrarySection(),
          SizedBox(height: 16),
          _PricingDefaultsSection(),
          SizedBox(height: 16),
          _AnnouncementsSection(),
          SizedBox(height: 16),
          _SystemPinsSection(),
          SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SECTION SCAFFOLDING
// ═══════════════════════════════════════════════════════════════════════

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: NexGenPalette.textMedium,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SECTION 1 — DEALER MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════

class _DealerManagementSection extends ConsumerWidget {
  const _DealerManagementSection();

  void _openEditSheet(BuildContext context, WidgetRef ref, DealerInfo? dealer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NexGenPalette.gunmetal,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
        ),
        child: _DealerEditSheet(existing: dealer),
      ),
    );
  }

  Future<void> _toggleActive(
      BuildContext context, WidgetRef ref, DealerInfo dealer) async {
    try {
      await ref
          .read(corporateAdminServiceProvider)
          .setDealerActive(dealer.dealerCode, !dealer.isActive);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update dealer: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dealersAsync = ref.watch(allDealersProvider);

    return _SectionCard(
      title: 'Dealer Management',
      subtitle:
          'Activate / deactivate dealers. Tap a row to edit business info.',
      trailing: TextButton.icon(
        onPressed: () => _openEditSheet(context, ref, null),
        icon: const Icon(Icons.add, color: NexGenPalette.gold, size: 16),
        label: const Text(
          'Add',
          style: TextStyle(color: NexGenPalette.gold),
        ),
      ),
      child: dealersAsync.when(
        loading: () => const _Loader(),
        error: (e, _) => _ErrorRow(message: 'Failed to load dealers: $e'),
        data: (dealers) {
          if (dealers.isEmpty) {
            return _emptyRow('No dealers registered.');
          }
          return Column(
            children: dealers.map((d) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.companyName.isEmpty
                                ? d.dealerCode
                                : d.companyName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            d.dealerCode,
                            style: TextStyle(
                              color: NexGenPalette.textMedium,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: d.isActive,
                      activeThumbColor: NexGenPalette.gold,
                      onChanged: (_) => _toggleActive(context, ref, d),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.edit_outlined,
                        color: NexGenPalette.gold,
                        size: 18,
                      ),
                      onPressed: () => _openEditSheet(context, ref, d),
                    ),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _DealerEditSheet extends ConsumerStatefulWidget {
  const _DealerEditSheet({this.existing});
  final DealerInfo? existing;

  @override
  ConsumerState<_DealerEditSheet> createState() => _DealerEditSheetState();
}

class _DealerEditSheetState extends ConsumerState<_DealerEditSheet> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _territory;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.companyName ?? '');
    _email = TextEditingController(text: widget.existing?.email ?? '');
    _phone = TextEditingController(text: widget.existing?.phone ?? '');
    _territory = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _territory.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Business name is required.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final svc = ref.read(corporateAdminServiceProvider);
      if (widget.existing == null) {
        await svc.createDealer(
          businessName: _name.text.trim(),
          contactEmail: _email.text.trim(),
          contactPhone: _phone.text.trim(),
          territory: _territory.text.trim().isEmpty
              ? null
              : _territory.text.trim(),
        );
      } else {
        await svc.updateDealer(
          widget.existing!.dealerCode,
          businessName: _name.text.trim(),
          contactEmail: _email.text.trim(),
          contactPhone: _phone.text.trim(),
          territory: _territory.text.trim().isEmpty
              ? null
              : _territory.text.trim(),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isNew ? 'Add Dealer' : 'Edit Dealer',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          _field('Business name', _name),
          const SizedBox(height: 10),
          _field('Contact email', _email),
          const SizedBox(height: 10),
          _field('Contact phone', _phone),
          const SizedBox(height: 10),
          _field('Territory (state code)', _territory),
          const SizedBox(height: 18),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: NexGenPalette.gold,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.black,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    isNew ? 'Create dealer' : 'Save changes',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: NexGenPalette.textMedium),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c) {
    return TextField(
      controller: c,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: NexGenPalette.textMedium),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.04),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: NexGenPalette.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: NexGenPalette.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: NexGenPalette.gold.withValues(alpha: 0.6)),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SECTION 1.5 — BRAND LIBRARY (Part 9D)
// ═══════════════════════════════════════════════════════════════════════
//
// Single section card combining the entry points the spec asked for in
// Parts 9A and 9D. Shows total brand count + pending-corrections badge,
// with two action buttons that push the full BrandLibraryAdminScreen
// and BrandCorrectionReviewScreen routes (both admin-gated in-screen).
//
// The streams (allBrandsProvider + pendingBrandCorrectionsProvider)
// are read-only collection listeners — both safe to render here even
// though the corporate dashboard is reachable by any signed-in user
// who passed the corporate PIN. The full management screens enforce
// user_role == 'admin' before allowing any writes.

class _BrandLibrarySection extends ConsumerWidget {
  const _BrandLibrarySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brandsAsync = ref.watch(allBrandsProvider);
    final correctionsAsync = ref.watch(pendingBrandCorrectionsProvider);

    final totalBrands = brandsAsync.valueOrNull?.length;
    final pendingCount = correctionsAsync.valueOrNull?.length ?? 0;
    final hasPending = pendingCount > 0;

    return _SectionCard(
      title: 'Brand Library',
      subtitle:
          'Manage the global brand catalog and review installer/customer '
          'color corrections.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _CountTile(
                  icon: Icons.palette_outlined,
                  label: 'Brands in library',
                  value: totalBrands == null ? '…' : '$totalBrands',
                  highlight: false,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CountTile(
                  icon: Icons.rate_review_outlined,
                  label: 'Pending corrections',
                  value: '$pendingCount',
                  highlight: hasPending,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context
                      .push(AppRoutes.adminBrandLibrary),
                  icon: const Icon(Icons.palette, size: 18),
                  label: const Text('Manage Library'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: NexGenPalette.gold,
                    side: BorderSide(
                        color: NexGenPalette.gold.withValues(alpha: 0.6)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => context
                      .push(AppRoutes.adminBrandCorrections),
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.rate_review, size: 18),
                      if (hasPending)
                        Positioned(
                          right: -6,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: NexGenPalette.amber,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$pendingCount',
                              style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                    ],
                  ),
                  label: const Text('Review Corrections'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: hasPending
                        ? NexGenPalette.amber
                        : NexGenPalette.gold,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.highlight,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final accent = highlight ? NexGenPalette.amber : NexGenPalette.gold;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: highlight ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: accent.withValues(alpha: highlight ? 0.5 : 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: NexGenPalette.textMedium, fontSize: 11)),
                Text(value,
                    style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SECTION 2 — PRICING DEFAULTS
// ═══════════════════════════════════════════════════════════════════════

class _PricingDefaultsSection extends ConsumerStatefulWidget {
  const _PricingDefaultsSection();

  @override
  ConsumerState<_PricingDefaultsSection> createState() =>
      _PricingDefaultsSectionState();
}

class _PricingDefaultsSectionState
    extends ConsumerState<_PricingDefaultsSection> {
  final TextEditingController _pricePerFt = TextEditingController();
  final TextEditingController _laborRate = TextEditingController();
  final TextEditingController _wasteFactor = TextEditingController();
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _pricePerFt.dispose();
    _laborRate.dispose();
    _wasteFactor.dispose();
    super.dispose();
  }

  void _ensureInitialized(DealerPricing? loaded) {
    if (_initialized) return;
    _initialized = true;
    final p = loaded ?? DealerPricing.defaults();
    _pricePerFt.text = p.pricePerLinearFoot.toStringAsFixed(2);
    _laborRate.text = p.laborRatePerFoot.toStringAsFixed(2);
    _wasteFactor.text = p.wasteFactor.toStringAsFixed(2);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final defaults = DealerPricing.defaults();
      final pricing = defaults.copyWith(
        pricePerLinearFoot:
            double.tryParse(_pricePerFt.text.trim()) ?? defaults.pricePerLinearFoot,
        laborRatePerFoot:
            double.tryParse(_laborRate.text.trim()) ?? defaults.laborRatePerFoot,
        wasteFactor:
            double.tryParse(_wasteFactor.text.trim()) ?? defaults.wasteFactor,
      );
      await ref
          .read(corporateAdminServiceProvider)
          .savePricingDefaults(pricing);
      // Re-fetch the provider so other screens see the change.
      ref.invalidate(networkPricingDefaultsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pricing defaults saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pricingAsync = ref.watch(networkPricingDefaultsProvider);

    return _SectionCard(
      title: 'Pricing Defaults',
      subtitle:
          'Network-wide fallback used when a dealer has no pricing doc. Stored at app_config/pricing_defaults.',
      child: pricingAsync.when(
        loading: () => const _Loader(),
        error: (e, _) => _ErrorRow(message: 'Failed to load pricing: $e'),
        data: (loaded) {
          _ensureInitialized(loaded);
          return Column(
            children: [
              _numField('Price per linear foot (\$)', _pricePerFt),
              const SizedBox(height: 8),
              _numField('Labor rate per foot (\$)', _laborRate),
              const SizedBox(height: 8),
              _numField('Waste factor (e.g. 0.08 = 8%)', _wasteFactor),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: NexGenPalette.gold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.black,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Save defaults',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _numField(String label, TextEditingController c) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.04),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: NexGenPalette.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: NexGenPalette.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: NexGenPalette.gold.withValues(alpha: 0.6)),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SECTION 3 — NETWORK ANNOUNCEMENTS
// ═══════════════════════════════════════════════════════════════════════

class _AnnouncementsSection extends ConsumerWidget {
  const _AnnouncementsSection();

  void _openComposer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NexGenPalette.gunmetal,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
        ),
        child: const _AnnouncementComposer(),
      ),
    );
  }

  Future<void> _archive(
      BuildContext context, WidgetRef ref, NetworkAnnouncement a) async {
    try {
      await ref.read(corporateAdminServiceProvider).archiveAnnouncement(a.id);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Archive failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncAnn = ref.watch(networkAnnouncementProvider);
    return _SectionCard(
      title: 'Network Announcements',
      subtitle:
          'Push messages to dealers, installers, or sales teams. Archive removes from active list.',
      trailing: TextButton.icon(
        onPressed: () => _openComposer(context),
        icon: const Icon(Icons.add, color: NexGenPalette.gold, size: 16),
        label: const Text(
          'New',
          style: TextStyle(color: NexGenPalette.gold),
        ),
      ),
      child: asyncAnn.when(
        loading: () => const _Loader(),
        error: (e, _) => _ErrorRow(message: 'Failed to load: $e'),
        data: (items) {
          final active = items.where((i) => i.isActive).toList();
          if (active.isEmpty) {
            return _emptyRow('No active announcements.');
          }
          return Column(
            children: active.map((a) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            a.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: NexGenPalette.violet.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            a.audience.label,
                            style: TextStyle(
                              color: NexGenPalette.violet,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      a.body,
                      style: TextStyle(
                        color: NexGenPalette.textMedium,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => _archive(context, ref, a),
                        child: const Text(
                          'Archive',
                          style: TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _AnnouncementComposer extends ConsumerStatefulWidget {
  const _AnnouncementComposer();

  @override
  ConsumerState<_AnnouncementComposer> createState() =>
      _AnnouncementComposerState();
}

class _AnnouncementComposerState
    extends ConsumerState<_AnnouncementComposer> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  AnnouncementAudience _audience = AnnouncementAudience.all;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title and body are required.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final session = ref.read(corporateSessionProvider);
      await ref.read(corporateAdminServiceProvider).publishAnnouncement(
            title: _title.text.trim(),
            body: _body.text.trim(),
            audience: _audience,
            createdByUid: session?.uid ?? '',
          );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Publish failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'New Announcement',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: _decoration('Title'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _body,
            maxLines: 5,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: _decoration('Body'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<AnnouncementAudience>(
            initialValue: _audience,
            dropdownColor: NexGenPalette.gunmetal,
            decoration: _decoration('Audience'),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            items: AnnouncementAudience.values
                .map((a) => DropdownMenuItem(
                      value: a,
                      child: Text(a.label),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _audience = v);
            },
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: NexGenPalette.gold,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _saving ? null : _publish,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.black,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Publish',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: NexGenPalette.textMedium),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: NexGenPalette.textMedium),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.04),
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: NexGenPalette.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: NexGenPalette.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
            color: NexGenPalette.gold.withValues(alpha: 0.6)),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SECTION 4 — SYSTEM PINS
// ═══════════════════════════════════════════════════════════════════════

class _SystemPinsSection extends ConsumerWidget {
  const _SystemPinsSection();

  void _openChangeSheet(BuildContext context, PinSlotState slot) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NexGenPalette.gunmetal,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
        ),
        child: _ChangePinSheet(slot: slot),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSlots = ref.watch(pinSlotStatesProvider);
    return _SectionCard(
      title: 'System PINs',
      subtitle:
          'Read-only status. Change PIN flow requires verifying the current PIN before writing the new value.',
      child: asyncSlots.when(
        loading: () => const _Loader(),
        error: (e, _) => _ErrorRow(message: 'Failed to load PIN status: $e'),
        data: (slots) {
          return Column(
            children: slots.map((s) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: s.isSet
                            ? NexGenPalette.green.withValues(alpha: 0.18)
                            : Colors.red.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        s.isSet ? 'Set' : 'Not set',
                        style: TextStyle(
                          color: s.isSet
                              ? NexGenPalette.green
                              : Colors.red,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => _openChangeSheet(context, s),
                      child: const Text(
                        'Change PIN',
                        style: TextStyle(
                          color: NexGenPalette.gold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _ChangePinSheet extends ConsumerStatefulWidget {
  const _ChangePinSheet({required this.slot});
  final PinSlotState slot;

  @override
  ConsumerState<_ChangePinSheet> createState() => _ChangePinSheetState();
}

class _ChangePinSheetState extends ConsumerState<_ChangePinSheet> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _new = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);

    if (_new.text.length != 4) {
      setState(() => _error = 'New PIN must be 4 digits.');
      return;
    }
    if (_new.text != _confirm.text) {
      setState(() => _error = 'PIN confirmation does not match.');
      return;
    }

    setState(() => _saving = true);
    try {
      final svc = ref.read(corporateAdminServiceProvider);
      // Skip verification when no PIN is set yet (initial provisioning).
      if (widget.slot.isSet) {
        final ok = await svc.verifyPin(
          slotKey: widget.slot.slotKey,
          enteredPin: _current.text,
        );
        if (!ok) {
          setState(() {
            _saving = false;
            _error = 'Current PIN incorrect.';
          });
          return;
        }
      }
      final saved = await svc.setPin(
        slotKey: widget.slot.slotKey,
        newPin: _new.text,
      );
      if (!saved) {
        setState(() {
          _saving = false;
          _error = 'Failed to save new PIN.';
        });
        return;
      }
      ref.invalidate(pinSlotStatesProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.slot.label} updated.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Save failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Change ${widget.slot.label}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          if (widget.slot.isSet) ...[
            _pinField('Current PIN', _current),
            const SizedBox(height: 10),
          ],
          _pinField('New PIN', _new),
          const SizedBox(height: 10),
          _pinField('Confirm new PIN', _confirm),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: NexGenPalette.gold,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.black,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Save PIN',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: NexGenPalette.textMedium),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pinField(String label, TextEditingController c) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.number,
      maxLength: 4,
      obscureText: true,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        letterSpacing: 8,
      ),
      decoration: InputDecoration(
        counterText: '',
        labelText: label,
        labelStyle: TextStyle(color: NexGenPalette.textMedium),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.04),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: NexGenPalette.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: NexGenPalette.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: NexGenPalette.gold.withValues(alpha: 0.6)),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SHARED UI
// ═══════════════════════════════════════════════════════════════════════

class _Loader extends StatelessWidget {
  const _Loader();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            color: NexGenPalette.gold,
            strokeWidth: 2,
          ),
        ),
      ),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        message,
        style: const TextStyle(color: Colors.red, fontSize: 11),
      ),
    );
  }
}

Widget _emptyRow(String message) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Center(
      child: Text(
        message,
        style: TextStyle(
          color: NexGenPalette.textMedium,
          fontSize: 12,
        ),
      ),
    ),
  );
}

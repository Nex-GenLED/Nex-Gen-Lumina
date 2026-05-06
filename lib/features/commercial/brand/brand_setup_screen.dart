import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/models/commercial/brand_color.dart';
import 'package:nexgen_command/models/commercial/brand_correction.dart';
import 'package:nexgen_command/models/commercial/brand_custom_design.dart';
import 'package:nexgen_command/models/commercial/brand_library_entry.dart';
import 'package:nexgen_command/models/commercial/brand_signature.dart';
import 'package:nexgen_command/models/commercial/commercial_brand_profile.dart';
import 'package:nexgen_command/features/commercial/brand/brand_design_generator.dart';
import 'package:nexgen_command/services/commercial/brand_library_providers.dart';

/// Industry keys mirrored from scripts/seed_brand_library.js so the
/// dropdown picks values the seeded signatures map back to.
const _kIndustries = <String>[
  'restaurant',
  'insurance',
  'bank',
  'retail',
  'realestate',
  'fitness',
  'hotel',
  'healthcare',
  'salon',
  'auto',
];

/// Curated WLED effects offered to corporate admins when authoring a
/// custom design card. Kept short and well-tested — a full WLED effect
/// picker is out of scope here. Tuple is (effectId, displayLabel) and
/// the displayLabel is what gets stored in
/// [BrandCustomDesign.wledEffectName].
const _kCuratedCustomDesignEffects = <(int, String)>[
  (0, 'Solid'),
  (2, 'Breathe'),
  (12, 'Fade'),
  (13, 'Glitter'),
  (15, 'Running'),
  (28, 'Chase'),
  (50, 'Twinkle'),
  (74, 'Twinkle Cat'),
];

/// Mood vocabulary for custom designs. Mirrors the values
/// [BrandSignature.mood] documents so the same chip set surfaces both
/// places.
const _kCustomDesignMoods = <String>[
  'trustworthy',
  'energetic',
  'stable',
  'inviting',
  'welcoming',
  'luxurious',
  'calm',
  'elegant',
  'dynamic',
  'professional',
];

/// Brand setup / edit screen. Used in two modes:
///
///  1. Library-derived: user picked a brand on BrandSearchScreen.
///     [preSelected] is non-null; colors and signature are pre-filled.
///     If the user modifies the colors here, a "Submit color correction"
///     banner appears so the change can be sent to corporate.
///
///  2. Manual entry: user tapped "Create Brand Profile" on the empty
///     state. [preSelected] is null and [isEditing] is false. Colors
///     start empty.
///
///  3. Edit-existing: opened from the Brand tab on the commercial home
///     screen. [isEditing] is true. The screen loads the customer's
///     existing CommercialBrandProfile from
///     /users/{uid}/brand_profile/brand on first build.
///
///  4. Admin edit (Part 9): opened from BrandLibraryAdminScreen. When
///     [isAdmin] is true, save writes to /brand_library/{brandId}
///     (NOT /users/{uid}/brand_profile/brand), the correction-submission
///     UI is suppressed, and the CTA reads "Save to Library". When
///     [isAdmin] AND [createNew] are both true the brandId is derived
///     from the company name on save.
///
/// On Save (default, non-admin): writes a [CommercialBrandProfile] to
/// /users/{uid}/brand_profile/brand (snake_case via toJson()).
class BrandSetupScreen extends ConsumerStatefulWidget {
  const BrandSetupScreen({
    super.key,
    this.preSelected,
    this.isEditing = false,
    this.isAdmin = false,
    this.createNew = false,
  });

  final BrandLibraryEntry? preSelected;
  final bool isEditing;

  /// True when launched from the corporate-admin path. Save target
  /// switches to /brand_library/{brandId}; correction-submission UI is
  /// hidden; CTA reads "Save to Library".
  final bool isAdmin;

  /// True when [isAdmin] is also true and the admin is creating a new
  /// brand-library entry from scratch (vs editing an existing one).
  /// Brand id is derived from company name on save.
  final bool createNew;

  /// Resolves a [GoRouterState.extra] payload into a fully-configured
  /// [BrandSetupScreen]. Routes that push this screen pass either:
  ///   • a bare [BrandLibraryEntry] (from BrandSearchScreen → pre-select), or
  ///   • a `Map { 'preSelected': …, 'isEditing': …, 'isAdmin': …,
  ///     'createNew': … }` (from the Brand tab Edit button or the admin
  ///     library screen), or
  ///   • `null` (from the "Create Brand Profile" empty-state button).
  ///
  /// Lives on the widget itself (not the State) so the GoRouter
  /// pageBuilder can reach it without going through a state instance.
  static BrandSetupScreen fromExtra(Object? extra, {bool isEditing = false}) {
    if (extra is BrandLibraryEntry) {
      return BrandSetupScreen(preSelected: extra, isEditing: isEditing);
    }
    if (extra is Map) {
      final pre = extra['preSelected'];
      final ed = extra['isEditing'];
      final adm = extra['isAdmin'];
      final cn = extra['createNew'];
      return BrandSetupScreen(
        preSelected: pre is BrandLibraryEntry ? pre : null,
        isEditing: ed is bool ? ed : isEditing,
        isAdmin: adm is bool ? adm : false,
        createNew: cn is bool ? cn : false,
      );
    }
    return BrandSetupScreen(isEditing: isEditing);
  }

  @override
  ConsumerState<BrandSetupScreen> createState() => _BrandSetupScreenState();
}

class _BrandSetupScreenState extends ConsumerState<BrandSetupScreen> {
  late final TextEditingController _nameCtrl;
  String _industry = 'retail';
  final List<_EditableColor> _colors = [];
  late BrandSignature _signature;
  bool _isSaving = false;
  bool _signatureExpanded = false;

  /// Snapshot of the colors that came from the library entry, kept so
  /// we can detect whether the user has diverged and offer a correction.
  List<BrandColor>? _originalColors;
  String? _brandLibraryId;

  /// Per-brand custom design cards beyond the canonical five. Only
  /// surfaced + editable on the admin path. For the customer-facing
  /// path this stays empty and is never written.
  final List<BrandCustomDesign> _customDesigns = [];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.preSelected?.companyName);
    _signature = widget.preSelected?.signature ?? const BrandSignature();
    if (widget.preSelected != null) {
      _industry = widget.preSelected!.industry.isNotEmpty
          ? widget.preSelected!.industry
          : _industry;
      _brandLibraryId = widget.preSelected!.brandId;
      _originalColors = List<BrandColor>.from(widget.preSelected!.colors);
      for (final c in widget.preSelected!.colors) {
        _colors.add(_EditableColor.fromBrandColor(c));
      }
      _customDesigns.addAll(widget.preSelected!.customDesigns);
    }

    if (widget.isEditing) {
      // Load existing profile on first build.
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadExisting());
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    for (final c in _colors) {
      c.dispose();
    }
    super.dispose();
  }

  // ─── Load + save ─────────────────────────────────────────────────────────

  Future<void> _loadExisting() async {
    final profile = ref.read(commercialBrandProfileProvider).valueOrNull;
    if (profile == null || !mounted) return;
    setState(() {
      _nameCtrl.text = profile.companyName;
      _brandLibraryId = profile.brandLibraryId;
      _signature = profile.signature;
      _colors.clear();
      for (final c in profile.colors) {
        _colors.add(_EditableColor.fromBrandColor(c));
      }
    });
  }

  bool get _hasModifiedFromLibrary {
    if (_originalColors == null) return false;
    if (_colors.length != _originalColors!.length) return true;
    for (var i = 0; i < _colors.length; i++) {
      final live = _colors[i].toBrandColor();
      final orig = _originalColors![i];
      if (live.hexCode.toUpperCase() != orig.hexCode.toUpperCase()) return true;
      if (live.colorName.trim() != orig.colorName.trim()) return true;
      if (live.roleTag != orig.roleTag) return true;
    }
    return false;
  }

  Future<void> _save({required bool alsoSubmitCorrection}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError('You must be signed in to save a brand profile.');
      return;
    }
    if (_nameCtrl.text.trim().isEmpty) {
      _showError('Please enter a company name.');
      return;
    }
    if (_colors.isEmpty) {
      _showError('Add at least one brand color before saving.');
      return;
    }
    for (final c in _colors) {
      if (c.colorName.trim().isEmpty) {
        _showError('Please name every color before saving.');
        return;
      }
      if (!_isValidHex(c.hexCode)) {
        _showError('"${c.colorName}" has an invalid hex code.');
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      // Admin path: write directly to /brand_library/{brandId} and
      // skip the customer-side correction + design-generation logic.
      // The library is the source of truth for everyone — no
      // per-customer profile is created from this branch.
      if (widget.isAdmin) {
        await _saveAsAdmin();
        return;
      }

      final colorJsons =
          _colors.map((c) => c.toBrandColor().toJson()).toList(growable: false);

      final modified = _hasModifiedFromLibrary;

      final profile = CommercialBrandProfile(
        companyName: _nameCtrl.text.trim(),
        brandLibraryId: _brandLibraryId,
        colors: _colors.map((c) => c.toBrandColor()).toList(growable: false),
        customized: modified,
        customizedAt: modified ? DateTime.now() : null,
        customizedBy: modified ? user.uid : null,
        signature: _signature,
        generatedDesigns: const [],
        createdByInstaller: null,
        createdAt: DateTime.now(),
      );

      // Write to /users/{uid}/brand_profile/brand. The Part-1 rules
      // allow owner-or-isUserRoleAdmin write; this is the owner path.
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('brand_profile')
          .doc('brand');

      // Use the model's toJson() unchanged for the colors field, then
      // server-stamp the timestamps so they survive offline writes.
      final json = profile.toJson();
      json['colors'] = colorJsons;
      if (!widget.isEditing) {
        json['created_at'] = FieldValue.serverTimestamp();
      }
      if (modified) {
        json['customized_at'] = FieldValue.serverTimestamp();
      }

      await docRef.set(json, SetOptions(merge: true));

      // Submit a brand-library correction if requested. We only do this
      // when the customer derived from a library entry AND modified the
      // colors AND chose to submit.
      if (alsoSubmitCorrection &&
          modified &&
          _brandLibraryId != null &&
          _originalColors != null) {
        await _submitCorrection(user);
      }

      // Auto-generate the five canonical brand designs (Solid / Breathe
      // / Chase / Event Mode / Welcome) and save them as favorites.
      // Wrapped in its own try so a generator failure doesn't undo the
      // profile save — the user still has a saved brand even if the
      // designs need to be regenerated later. The generator updates
      // brand_profile.generated_designs as part of its run.
      List<String> generatedNames = const [];
      try {
        generatedNames = await runBrandDesignGenerator(ref, profile);
      } catch (e) {
        debugPrint('BrandSetupScreen: design generator failed — $e');
      }

      if (!mounted) return;
      final designsMsg = generatedNames.isEmpty
          ? ''
          : ' ${generatedNames.length} brand designs added to favorites.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text((alsoSubmitCorrection
                  ? 'Saved — color correction submitted for review.'
                  : 'Brand profile saved.') +
              designsMsg),
          backgroundColor: NexGenPalette.cyan,
          duration: const Duration(seconds: 4),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      _showError('Save failed: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Admin save path (Part 9): writes /brand_library/{brandId}.
  ///
  /// For [BrandSetupScreen.createNew] the brand id is slugified from
  /// the company name (matches scripts/seed_brand_library.js's
  /// toBrandId). For an existing-entry edit, [_brandLibraryId] is the
  /// pre-loaded id.
  Future<void> _saveAsAdmin() async {
    final companyName = _nameCtrl.text.trim();
    String brandId;
    if (widget.createNew) {
      brandId = _slugifyBrandId(companyName);
      if (brandId.isEmpty) {
        _showError('Could not derive a brand id from the company name.');
        return;
      }
    } else {
      brandId = _brandLibraryId ?? _slugifyBrandId(companyName);
      if (brandId.isEmpty) {
        _showError('Missing brand id for the existing library entry.');
        return;
      }
    }

    final colorJsons =
        _colors.map((c) => c.toBrandColor().toJson()).toList(growable: false);

    // Document shape mirrors what scripts/seed_brand_library.js writes
    // so the existing BrandLibraryEntry.fromFirestore deserialization
    // path works without any changes.
    final docData = <String, dynamic>{
      'brand_id': brandId,
      'company_name': companyName,
      'search_terms': _searchTermsFor(companyName),
      'industry': _industry,
      'colors': colorJsons,
      'signature': _signature.toJson(),
      'last_verified': FieldValue.serverTimestamp(),
      'status': 'verified',
      'custom_designs':
          _customDesigns.map((d) => d.toJson()).toList(growable: false),
    };
    if (widget.createNew) {
      // First write — fix the trust source. Re-saves of existing
      // entries preserve whatever verified_by + correction_count were
      // already set (handled by SetOptions(merge: true) below).
      docData['verified_by'] = 'nex-gen-manual';
      docData['correction_count'] = 0;
    }

    try {
      await FirebaseFirestore.instance
          .collection('brand_library')
          .doc(brandId)
          .set(docData, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.createNew
              ? 'Added "$companyName" to brand library.'
              : 'Saved "$companyName" to brand library.'),
          backgroundColor: NexGenPalette.cyan,
          duration: const Duration(seconds: 3),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      _showError('Save failed: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Slug rules mirror scripts/seed_brand_library.js's toBrandId so
  /// admin-created entries land at the same id pattern as seeded
  /// entries. Lowercase, alphanumerics + hyphens only, no leading or
  /// trailing hyphens, no doubled hyphens.
  String _slugifyBrandId(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '')
        .trim();
  }

  /// Search-term generation mirrors the seed script:
  /// full lowercased name, no-spaces variant, and per-word splits ≥ 3
  /// chars. De-duplicated and ≤ a handful of entries — small enough to
  /// fit Firestore's arrayContains query path.
  List<String> _searchTermsFor(String name) {
    final lower = name.toLowerCase().trim();
    if (lower.isEmpty) return const [];
    final noSpaces = lower.replaceAll(RegExp(r'\s'), '');
    final words = lower
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2)
        .toList();
    final set = <String>{lower, noSpaces, ...words};
    return set.where((t) => t.isNotEmpty).toList(growable: false);
  }

  Future<void> _submitCorrection(User user) async {
    if (_brandLibraryId == null || _originalColors == null) return;

    final reason = await _promptForReason();
    if (reason == null) return; // user cancelled

    final correction = BrandCorrection(
      brandId: _brandLibraryId!,
      companyName: _nameCtrl.text.trim(),
      submittedBy: user.uid,
      dealerCode: '',
      originalColors: _originalColors!,
      proposedColors:
          _colors.map((c) => c.toBrandColor()).toList(growable: false),
      reason: reason,
      submittedAt: DateTime.now(),
    );

    final json = correction.toJson();
    json['submitted_at'] = FieldValue.serverTimestamp();

    await FirebaseFirestore.instance
        .collection('brand_library_corrections')
        .add(json);
  }

  Future<String?> _promptForReason() async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text('Submit color correction',
            style: TextStyle(color: NexGenPalette.textHigh)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tell corporate why you changed these colors. Approved '
              'corrections update the brand library for everyone.',
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 3,
              maxLength: 280,
              style: const TextStyle(color: NexGenPalette.textHigh),
              decoration: InputDecoration(
                hintText: 'e.g. Official brand guide shows different red',
                hintStyle: const TextStyle(color: NexGenPalette.textMedium),
                filled: true,
                fillColor: NexGenPalette.gunmetal,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: NexGenPalette.line),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: NexGenPalette.textMedium)),
          ),
          ElevatedButton(
            onPressed: () {
              final text = ctrl.text.trim();
              if (text.isEmpty) return;
              Navigator.of(ctx).pop(text);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: NexGenPalette.cyan,
                foregroundColor: Colors.black),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    return reason;
  }

  // ─── Color editing ───────────────────────────────────────────────────────

  void _addColor() {
    if (_colors.length >= 6) return;
    setState(() {
      _colors.add(_EditableColor.empty(
          'bc_local_${DateTime.now().microsecondsSinceEpoch}'));
    });
  }

  void _removeColor(int index) {
    setState(() {
      _colors[index].dispose();
      _colors.removeAt(index);
    });
  }

  bool _isValidHex(String hex) {
    final cleaned = hex.replaceAll('#', '').trim();
    if (cleaned.length != 6) return false;
    return RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(cleaned);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: NexGenPalette.amber,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ─── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Correction banner is suppressed entirely on the admin path —
    // admins are editing the source of truth, not submitting a
    // correction against it.
    final showCorrectionBanner = !widget.isAdmin &&
        _hasModifiedFromLibrary &&
        _brandLibraryId != null;

    final title = widget.isAdmin
        ? (widget.createNew ? 'New Brand' : 'Edit Brand Library')
        : (widget.isEditing ? 'Edit Brand Profile' : 'Brand Profile');

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: NexGenPalette.gunmetal90,
        elevation: 0,
        title: Text(title),
        iconTheme: const IconThemeData(color: NexGenPalette.textHigh),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _buildCompanySection(),
          const SizedBox(height: 24),
          _buildColorsSection(),
          if (showCorrectionBanner) ...[
            const SizedBox(height: 12),
            _buildCorrectionBanner(),
          ],
          const SizedBox(height: 24),
          _buildPreviewSection(),
          const SizedBox(height: 24),
          _buildSignatureSection(),
          if (widget.isAdmin) ...[
            const SizedBox(height: 24),
            _buildCustomDesignsSection(),
          ],
          const SizedBox(height: 32),
          _buildActions(showCorrectionBanner),
        ],
      ),
    );
  }

  // ─── Custom designs (admin-only) ─────────────────────────────────────────

  Widget _buildCustomDesignsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionTitle('Custom Designs'),
            const SizedBox(width: 8),
            Text(
              '— optional, beyond the canonical 5',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: NexGenPalette.textMedium),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Adds extra design cards that materialize alongside Solid, '
          'Breathe, Chase, Event Mode, and Welcome whenever a customer '
          'selects this brand.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < _customDesigns.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _CustomDesignRow(
              design: _customDesigns[i],
              onEdit: () => _editCustomDesign(i),
              onDelete: () => _confirmDeleteCustomDesign(i),
            ),
          ),
        OutlinedButton.icon(
          onPressed: _addCustomDesign,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Custom Design'),
          style: OutlinedButton.styleFrom(
            foregroundColor: NexGenPalette.cyan,
            side: const BorderSide(color: NexGenPalette.cyan),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }

  Future<void> _addCustomDesign() async {
    final result = await showDialog<BrandCustomDesign>(
      context: context,
      builder: (ctx) => const _CustomDesignDialog(initial: null),
    );
    if (result == null || !mounted) return;
    if (_customDesigns.any((d) => d.designId == result.designId)) {
      _showError(
          'A custom design with id "${result.designId}" already exists.');
      return;
    }
    setState(() => _customDesigns.add(result));
  }

  Future<void> _editCustomDesign(int index) async {
    final existing = _customDesigns[index];
    final result = await showDialog<BrandCustomDesign>(
      context: context,
      builder: (ctx) => _CustomDesignDialog(initial: existing),
    );
    if (result == null || !mounted) return;
    setState(() => _customDesigns[index] = result);
  }

  Future<void> _confirmDeleteCustomDesign(int index) async {
    final design = _customDesigns[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text('Delete custom design?',
            style: TextStyle(color: NexGenPalette.textHigh)),
        content: Text(
          'Remove "${design.displayName}" from this brand? Customers who '
          'already have this design as a favorite will keep their copy '
          'until the next regenerate.',
          style: const TextStyle(color: NexGenPalette.textMedium),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: NexGenPalette.textMedium)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _customDesigns.removeAt(index));
  }

  Widget _sectionTitle(String text) {
    return Text(text, style: Theme.of(context).textTheme.titleMedium);
  }

  Widget _buildCompanySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Company Info'),
        const SizedBox(height: 12),
        TextField(
          controller: _nameCtrl,
          style: const TextStyle(color: NexGenPalette.textHigh),
          decoration: _fieldDecoration(label: 'Company name'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _kIndustries.contains(_industry) ? _industry : null,
          dropdownColor: NexGenPalette.gunmetal,
          style: const TextStyle(color: NexGenPalette.textHigh),
          decoration: _fieldDecoration(label: 'Industry'),
          items: [
            for (final i in _kIndustries)
              DropdownMenuItem(value: i, child: Text(i)),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _industry = v);
          },
        ),
      ],
    );
  }

  Widget _buildColorsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Brand Colors'),
        const SizedBox(height: 4),
        Text(
          'Add up to 6 brand colors with hex codes from the official '
          'brand guide.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < _colors.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ColorRow(
              key: ValueKey(_colors[i].id),
              editable: _colors[i],
              onChanged: () => setState(() {}),
              onRemove: () => _removeColor(i),
            ),
          ),
        if (_colors.length < 6)
          OutlinedButton.icon(
            onPressed: _addColor,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Color'),
            style: OutlinedButton.styleFrom(
              foregroundColor: NexGenPalette.cyan,
              side: const BorderSide(color: NexGenPalette.cyan),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
      ],
    );
  }

  Widget _buildCorrectionBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexGenPalette.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NexGenPalette.amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.info_outline, color: NexGenPalette.amber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'You\'ve modified the brand colors. Submit a correction '
              'so corporate can review for the brand library?',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: NexGenPalette.textHigh),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionTitle('Preview'),
            const SizedBox(width: 8),
            Text(
              '— ${_signature.mood} ${_signature.primaryEffect}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: NexGenPalette.cyan),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 56,
          decoration: BoxDecoration(
            color: NexGenPalette.matteBlack,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: NexGenPalette.line),
          ),
          padding: const EdgeInsets.all(4),
          child: _colors.isEmpty
              ? Center(
                  child: Text(
                    'Add a brand color to see a preview.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : Row(
                  children: [
                    for (final c in _colors)
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: _isValidHex(c.hexCode)
                                ? c.toBrandColor().toColor()
                                : NexGenPalette.gunmetal,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildSignatureSection() {
    return Container(
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: ExpansionTile(
        initiallyExpanded: _signatureExpanded,
        onExpansionChanged: (v) => setState(() => _signatureExpanded = v),
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        iconColor: NexGenPalette.textMedium,
        collapsedIconColor: NexGenPalette.textMedium,
        title: Text('Lighting Signature',
            style: Theme.of(context).textTheme.titleSmall),
        subtitle: Text(
          '${_signature.mood} • ${_signature.primaryEffect} • '
          '${_signature.speed} • ${_signature.intensity}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _signatureRow('Effect', _signature.primaryEffect),
          _signatureRow('Speed', _signature.speed),
          _signatureRow('Intensity', _signature.intensity),
          _signatureRow('Mood', _signature.mood),
        ],
      ),
    );
  }

  Widget _signatureRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: Theme.of(context).textTheme.bodySmall),
          ),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: NexGenPalette.textHigh)),
        ],
      ),
    );
  }

  Widget _buildActions(bool showCorrection) {
    final primaryLabel = widget.isAdmin ? 'Save to Library' : 'Save Brand Profile';
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _isSaving ? null : () => _save(alsoSubmitCorrection: false),
            style: ElevatedButton.styleFrom(
              backgroundColor: NexGenPalette.cyan,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black))
                : Text(primaryLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
        if (showCorrection) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: _isSaving
                  ? null
                  : () => _save(alsoSubmitCorrection: true),
              icon: const Icon(Icons.send_outlined, size: 18),
              label: const Text('Save & Submit Correction'),
              style: OutlinedButton.styleFrom(
                foregroundColor: NexGenPalette.amber,
                side: const BorderSide(color: NexGenPalette.amber),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  InputDecoration _fieldDecoration({required String label}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: NexGenPalette.textMedium),
      filled: true,
      fillColor: NexGenPalette.gunmetal,
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
        borderSide: const BorderSide(color: NexGenPalette.cyan, width: 1.5),
      ),
    );
  }

}

// ─── Internal: editable color row state ────────────────────────────────────

class _EditableColor {
  _EditableColor({
    required this.id,
    required this.nameCtrl,
    required this.hexCtrl,
    required this.roleTag,
    required this.activeInEngine,
  });

  factory _EditableColor.fromBrandColor(BrandColor c) {
    return _EditableColor(
      id: c.id,
      nameCtrl: TextEditingController(text: c.colorName),
      hexCtrl: TextEditingController(
          text: c.hexCode.replaceAll('#', '').toUpperCase()),
      roleTag: c.roleTag,
      activeInEngine: c.activeInEngine,
    );
  }

  factory _EditableColor.empty(String id) {
    return _EditableColor(
      id: id,
      nameCtrl: TextEditingController(),
      hexCtrl: TextEditingController(),
      roleTag: 'primary',
      activeInEngine: true,
    );
  }

  final String id;
  final TextEditingController nameCtrl;
  final TextEditingController hexCtrl;
  String roleTag;
  bool activeInEngine;

  String get colorName => nameCtrl.text;
  String get hexCode => hexCtrl.text.replaceAll('#', '').trim().toUpperCase();

  BrandColor toBrandColor() => BrandColor(
        id: id,
        colorName: nameCtrl.text.trim(),
        hexCode: hexCode,
        roleTag: roleTag,
        activeInEngine: activeInEngine,
      );

  void dispose() {
    nameCtrl.dispose();
    hexCtrl.dispose();
  }
}

// ─── Internal: single color row widget ─────────────────────────────────────

class _ColorRow extends StatefulWidget {
  const _ColorRow({
    super.key,
    required this.editable,
    required this.onChanged,
    required this.onRemove,
  });

  final _EditableColor editable;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  State<_ColorRow> createState() => _ColorRowState();
}

class _ColorRowState extends State<_ColorRow> {
  Color _swatchFor(String hex) {
    final cleaned = hex.replaceAll('#', '').trim();
    if (cleaned.length == 6 &&
        RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(cleaned)) {
      return Color(int.parse('FF$cleaned', radix: 16));
    }
    return NexGenPalette.gunmetal;
  }

  @override
  Widget build(BuildContext context) {
    final swatch = _swatchFor(widget.editable.hexCtrl.text);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: swatch,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: NexGenPalette.line),
                ),
              ),
              const SizedBox(width: 12),
              const Text('#',
                  style: TextStyle(color: NexGenPalette.textMedium)),
              SizedBox(
                width: 84,
                child: TextField(
                  controller: widget.editable.hexCtrl,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(7),
                    FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9a-fA-F#]')),
                  ],
                  style: const TextStyle(
                      color: NexGenPalette.textHigh, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'FFFFFF',
                    hintStyle: TextStyle(color: NexGenPalette.textMedium),
                    isDense: true,
                    border: InputBorder.none,
                  ),
                  onChanged: (_) {
                    setState(() {});
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: widget.editable.nameCtrl,
                  style: const TextStyle(
                      color: NexGenPalette.textHigh, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Color name',
                    hintStyle: TextStyle(color: NexGenPalette.textMedium),
                    isDense: true,
                    border: InputBorder.none,
                  ),
                  onChanged: (_) => widget.onChanged(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close,
                    color: Colors.redAccent, size: 18),
                onPressed: widget.onRemove,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              for (final tag in const ['primary', 'secondary', 'accent'])
                ChoiceChip(
                  label: Text(tag),
                  selected: widget.editable.roleTag == tag,
                  selectedColor: NexGenPalette.cyan.withValues(alpha: 0.2),
                  backgroundColor: NexGenPalette.gunmetal,
                  side: BorderSide(
                    color: widget.editable.roleTag == tag
                        ? NexGenPalette.cyan
                        : NexGenPalette.line,
                  ),
                  labelStyle: TextStyle(
                    color: widget.editable.roleTag == tag
                        ? NexGenPalette.cyan
                        : NexGenPalette.textMedium,
                    fontSize: 11,
                  ),
                  onSelected: (_) {
                    setState(() => widget.editable.roleTag = tag);
                    widget.onChanged();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Internal: custom design row + dialog (admin) ──────────────────────────

class _CustomDesignRow extends StatelessWidget {
  const _CustomDesignRow({
    required this.design,
    required this.onEdit,
    required this.onDelete,
  });

  final BrandCustomDesign design;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final params = design.effectParams;
    final paramSummary = <String>[];
    if (params['sx'] is num) paramSummary.add('sx ${params['sx']}');
    if (params['ix'] is num) paramSummary.add('ix ${params['ix']}');
    if (params['pal'] is num) paramSummary.add('pal ${params['pal']}');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(design.displayName,
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  '${design.wledEffectName} (fx=${design.wledEffectId})'
                  ' • ${design.mood}'
                  '${paramSummary.isEmpty ? '' : ' • ${paramSummary.join(', ')}'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (design.description != null &&
                    design.description!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(design.description!,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: NexGenPalette.textMedium)),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined,
                color: NexGenPalette.cyan, size: 20),
            tooltip: 'Edit',
            onPressed: onEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: Colors.redAccent, size: 20),
            tooltip: 'Delete',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _CustomDesignDialog extends StatefulWidget {
  const _CustomDesignDialog({required this.initial});

  /// Existing design when editing, or null for "add new".
  final BrandCustomDesign? initial;

  @override
  State<_CustomDesignDialog> createState() => _CustomDesignDialogState();
}

class _CustomDesignDialogState extends State<_CustomDesignDialog> {
  late final TextEditingController _displayNameCtrl;
  late final TextEditingController _descriptionCtrl;
  late int _effectId;
  late String _effectName;
  late double _speed;
  late double _intensity;
  late String _mood;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _displayNameCtrl = TextEditingController(text: i?.displayName ?? '');
    _descriptionCtrl = TextEditingController(text: i?.description ?? '');
    _effectId = i?.wledEffectId ?? _kCuratedCustomDesignEffects.first.$1;
    _effectName = i?.wledEffectName ??
        _kCuratedCustomDesignEffects.first.$2;
    _speed = (i?.effectParams['sx'] is num
            ? (i!.effectParams['sx'] as num).toDouble()
            : 128)
        .clamp(0, 255);
    _intensity = (i?.effectParams['ix'] is num
            ? (i!.effectParams['ix'] as num).toDouble()
            : 150)
        .clamp(0, 255);
    _mood = (i?.mood != null && _kCustomDesignMoods.contains(i!.mood))
        ? i.mood
        : 'professional';
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  /// Slug rules mirror the seed script's toBrandId so admin-authored
  /// designs land at predictable, URL-safe ids
  /// ("Shimmer" → "shimmer", "Wave Sync" → "wave-sync").
  String _slugifyDesignId(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '')
        .trim();
  }

  void _submit() {
    final displayName = _displayNameCtrl.text.trim();
    if (displayName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Display name is required.'),
          backgroundColor: NexGenPalette.amber,
        ),
      );
      return;
    }
    // Lock the design id once on first save so re-renames don't orphan
    // the favorites doc on the customer side.
    final designId = widget.initial?.designId.isNotEmpty == true
        ? widget.initial!.designId
        : _slugifyDesignId(displayName);
    if (designId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Could not derive a design id from the display name.'),
          backgroundColor: NexGenPalette.amber,
        ),
      );
      return;
    }

    final descriptionText = _descriptionCtrl.text.trim();
    final result = BrandCustomDesign(
      designId: designId,
      displayName: displayName,
      wledEffectName: _effectName,
      wledEffectId: _effectId,
      effectParams: {
        'sx': _speed.round(),
        'ix': _intensity.round(),
      },
      description: descriptionText.isEmpty ? null : descriptionText,
      mood: _mood,
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    return AlertDialog(
      backgroundColor: NexGenPalette.gunmetal90,
      title: Text(isEdit ? 'Edit Custom Design' : 'New Custom Design',
          style: const TextStyle(color: NexGenPalette.textHigh)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _displayNameCtrl,
              autofocus: !isEdit,
              style: const TextStyle(color: NexGenPalette.textHigh),
              decoration: _dialogFieldDecoration(label: 'Display name'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _effectId,
              dropdownColor: NexGenPalette.gunmetal,
              style: const TextStyle(color: NexGenPalette.textHigh),
              decoration: _dialogFieldDecoration(label: 'WLED effect'),
              items: [
                for (final (id, label) in _kCuratedCustomDesignEffects)
                  DropdownMenuItem(value: id, child: Text('$label  (fx=$id)')),
              ],
              onChanged: (v) {
                if (v == null) return;
                final match = _kCuratedCustomDesignEffects
                    .firstWhere((e) => e.$1 == v);
                setState(() {
                  _effectId = match.$1;
                  _effectName = match.$2;
                });
              },
            ),
            const SizedBox(height: 12),
            _sliderRow(
              label: 'Speed (sx)',
              value: _speed,
              onChanged: (v) => setState(() => _speed = v),
            ),
            _sliderRow(
              label: 'Intensity (ix)',
              value: _intensity,
              onChanged: (v) => setState(() => _intensity = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _mood,
              dropdownColor: NexGenPalette.gunmetal,
              style: const TextStyle(color: NexGenPalette.textHigh),
              decoration: _dialogFieldDecoration(label: 'Mood'),
              items: [
                for (final m in _kCustomDesignMoods)
                  DropdownMenuItem(value: m, child: Text(m)),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _mood = v);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionCtrl,
              maxLines: 2,
              maxLength: 200,
              style: const TextStyle(color: NexGenPalette.textHigh),
              decoration: _dialogFieldDecoration(
                label: 'Description (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel',
              style: TextStyle(color: NexGenPalette.textMedium)),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: NexGenPalette.cyan,
            foregroundColor: Colors.black,
          ),
          child: Text(isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }

  Widget _sliderRow({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Slider(
              min: 0,
              max: 255,
              divisions: 51,
              value: value,
              activeColor: NexGenPalette.cyan,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              value.round().toString(),
              textAlign: TextAlign.right,
              style: const TextStyle(color: NexGenPalette.textHigh),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _dialogFieldDecoration({required String label}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: NexGenPalette.textMedium),
      filled: true,
      fillColor: NexGenPalette.gunmetal,
      isDense: true,
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
        borderSide: const BorderSide(color: NexGenPalette.cyan, width: 1.5),
      ),
    );
  }
}

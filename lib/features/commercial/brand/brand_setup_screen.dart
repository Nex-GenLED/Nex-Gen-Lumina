import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/models/commercial/brand_color.dart';
import 'package:nexgen_command/models/commercial/brand_correction.dart';
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
/// On Save, writes a [CommercialBrandProfile] to
/// /users/{uid}/brand_profile/brand (snake_case via toJson()).
class BrandSetupScreen extends ConsumerStatefulWidget {
  const BrandSetupScreen({
    super.key,
    this.preSelected,
    this.isEditing = false,
  });

  final BrandLibraryEntry? preSelected;
  final bool isEditing;

  /// Resolves a [GoRouterState.extra] payload into a fully-configured
  /// [BrandSetupScreen]. Routes that push this screen pass either:
  ///   • a bare [BrandLibraryEntry] (from BrandSearchScreen → pre-select), or
  ///   • a `Map { 'preSelected': BrandLibraryEntry?, 'isEditing': bool }`
  ///     (from the Brand tab Edit button on CommercialHomeScreen), or
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
      return BrandSetupScreen(
        preSelected: pre is BrandLibraryEntry ? pre : null,
        isEditing: ed is bool ? ed : isEditing,
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
    final showCorrectionBanner =
        _hasModifiedFromLibrary && _brandLibraryId != null;

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: NexGenPalette.gunmetal90,
        elevation: 0,
        title: Text(widget.isEditing ? 'Edit Brand Profile' : 'Brand Profile'),
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
          const SizedBox(height: 32),
          _buildActions(showCorrectionBanner),
        ],
      ),
    );
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
                : const Text('Save Brand Profile',
                    style: TextStyle(fontWeight: FontWeight.w600)),
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

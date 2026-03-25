import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/app_theme.dart';
import 'package:nexgen_command/models/commercial/brand_color.dart';
import 'package:nexgen_command/models/commercial/business_hours.dart';
import 'package:nexgen_command/models/commercial/business_profile.dart';
import 'package:nexgen_command/services/commercial/commercial_providers.dart';
import 'package:nexgen_command/widgets/commercial/commercial_pro_banner.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';

class BusinessProfileEditScreen extends ConsumerStatefulWidget {
  final String locationId;
  const BusinessProfileEditScreen({super.key, required this.locationId});

  @override
  ConsumerState<BusinessProfileEditScreen> createState() =>
      _BusinessProfileEditScreenState();
}

class _BusinessProfileEditScreenState
    extends ConsumerState<BusinessProfileEditScreen> {
  bool _loading = true;
  bool _saving = false;
  BusinessProfile? _profile;

  // Editable fields
  late TextEditingController _nameCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _typeCtrl;
  List<BrandColor> _brandColors = [];
  int _preOpenBuffer = 30;
  int _postCloseBuffer = 15;
  bool _observesHolidays = true;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _addressCtrl = TextEditingController();
    _typeCtrl = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfile());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _typeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (doc.exists && doc.data()?['commercial_profile'] != null) {
        final profile = BusinessProfile.fromJson(
            doc.data()!['commercial_profile'] as Map<String, dynamic>);
        _profile = profile;
        _nameCtrl.text = profile.businessName;
        _addressCtrl.text = profile.primaryAddress;
        _typeCtrl.text = profile.businessType;
        _brandColors = List.from(profile.brandColors);
        _preOpenBuffer = profile.preOpenBufferMinutes;
        _postCloseBuffer = profile.postCloseWindDownMinutes;
        _observesHolidays = profile.observesUsHolidays;
      }
    } catch (e) {
      debugPrint('Load profile error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final updated = BusinessProfile(
        businessType: _typeCtrl.text.trim(),
        businessName: _nameCtrl.text.trim(),
        primaryAddress: _addressCtrl.text.trim(),
        addressLatLng: _profile?.addressLatLng,
        brandColors: _brandColors,
        hoursOfOperation: _profile?.hoursOfOperation ?? {},
        preOpenBufferMinutes: _preOpenBuffer,
        postCloseWindDownMinutes: _postCloseBuffer,
        customClosureDates: _profile?.customClosureDates ?? [],
        observesUsHolidays: _observesHolidays,
      );

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'commercial_profile': updated.toJson()});

      // Trigger schedule recalculation if business type changed
      try {
        final scheduler = ref.read(dayPartSchedulerServiceProvider);
        scheduler.generateScheduleFromTemplate(
          updated.businessType,
          _buildBusinessHours(),
          locationId: widget.locationId,
        );
      } catch (e) {
        debugPrint('Schedule recalculation error: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Business profile saved'),
            backgroundColor: NexGenPalette.gunmetal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  BusinessHours _buildBusinessHours() {
    return BusinessHours(
      preOpenBufferMinutes: _preOpenBuffer,
      postCloseWindDownMinutes: _postCloseBuffer,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: NexGenPalette.matteBlack,
        appBar: const GlassAppBar(title: Text('Business Profile')),
        body: const Center(
            child: CircularProgressIndicator(color: NexGenPalette.cyan)),
      );
    }

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: GlassAppBar(
        title: const Text('Business Profile',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: NexGenPalette.cyan))
                : const Text('Save',
                    style: TextStyle(
                        color: NexGenPalette.cyan,
                        fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          const CommercialProBanner(
            bannerKey: 'business_profile',
            maxShows: 3,
          ),
          const SizedBox(height: 8),
          // Business Info
          _sectionLabel('BUSINESS INFO'),
          const SizedBox(height: 8),
          _buildTextField(_nameCtrl, 'Business Name'),
          const SizedBox(height: 10),
          _buildTextField(_typeCtrl, 'Business Type'),
          const SizedBox(height: 10),
          _buildTextField(_addressCtrl, 'Primary Address'),
          const SizedBox(height: 20),
          // Brand Colors
          _sectionLabel('BRAND COLORS'),
          const SizedBox(height: 8),
          _buildBrandColorSection(),
          const SizedBox(height: 20),
          // Timing Buffers
          _sectionLabel('TIMING BUFFERS'),
          const SizedBox(height: 8),
          _buildBufferRow('Pre-Open Buffer', _preOpenBuffer, (v) {
            setState(() => _preOpenBuffer = v);
          }),
          const SizedBox(height: 8),
          _buildBufferRow('Post-Close Wind Down', _postCloseBuffer, (v) {
            setState(() => _postCloseBuffer = v);
          }),
          const SizedBox(height: 20),
          // Holidays
          _sectionLabel('HOLIDAYS'),
          const SizedBox(height: 8),
          _buildHolidayToggle(),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: NexGenPalette.textHigh),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(color: NexGenPalette.textMedium, fontSize: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: NexGenPalette.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: NexGenPalette.cyan),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _buildBrandColorSection() {
    return Column(
      children: [
        for (int i = 0; i < _brandColors.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: _brandColors[i].toColor(),
                    shape: BoxShape.circle,
                    border: Border.all(color: NexGenPalette.line),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${_brandColors[i].colorName} (${_brandColors[i].hexCode})',
                    style: const TextStyle(
                        color: NexGenPalette.textHigh, fontSize: 13),
                  ),
                ),
                if (_brandColors[i].roleTag.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: NexGenPalette.cyan.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _brandColors[i].roleTag,
                      style: const TextStyle(
                          color: NexGenPalette.cyan, fontSize: 9),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      size: 16, color: NexGenPalette.textMedium),
                  onPressed: () {
                    setState(() => _brandColors.removeAt(i));
                  },
                ),
              ],
            ),
          ),
        if (_brandColors.length < 8)
          OutlinedButton.icon(
            onPressed: _addBrandColor,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Add Color'),
            style: OutlinedButton.styleFrom(
              foregroundColor: NexGenPalette.cyan,
              side: BorderSide(
                  color: NexGenPalette.cyan.withValues(alpha: 0.3)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
          ),
      ],
    );
  }

  void _addBrandColor() {
    setState(() {
      _brandColors.add(BrandColor(
        id: 'color_${DateTime.now().millisecondsSinceEpoch}',
        colorName: 'New Color',
        hexCode: '#00D4FF',
        roleTag: '',
        activeInEngine: true,
      ));
    });
  }

  Widget _buildBufferRow(String label, int value, ValueChanged<int> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: NexGenPalette.textHigh, fontSize: 13)),
          ),
          IconButton(
            icon: const Icon(Icons.remove_rounded,
                size: 18, color: NexGenPalette.textMedium),
            onPressed: value > 0
                ? () => onChanged((value - 5).clamp(0, 120))
                : null,
          ),
          Text('$value min',
              style: const TextStyle(
                  color: NexGenPalette.cyan,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          IconButton(
            icon: const Icon(Icons.add_rounded,
                size: 18, color: NexGenPalette.textMedium),
            onPressed: value < 120
                ? () => onChanged((value + 5).clamp(0, 120))
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildHolidayToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text('Observe US Holidays',
                style:
                    TextStyle(color: NexGenPalette.textHigh, fontSize: 13)),
          ),
          Switch(
            value: _observesHolidays,
            onChanged: (v) => setState(() => _observesHolidays = v),
            activeTrackColor: NexGenPalette.cyan.withValues(alpha: 0.4),
            activeThumbColor: NexGenPalette.cyan,
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: NexGenPalette.textMedium,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}

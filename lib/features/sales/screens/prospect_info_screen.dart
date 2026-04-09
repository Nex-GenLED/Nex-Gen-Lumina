import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/referrals/services/referral_pipeline_service.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';
import 'package:nexgen_command/features/sales/sales_providers.dart';
import 'package:nexgen_command/features/sales/services/sales_job_service.dart';
import 'package:nexgen_command/features/schedule/geocoding_service.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/address_autocomplete.dart';
import 'package:go_router/go_router.dart';

/// Step 1 of 3 in the sales visit wizard: prospect information capture.
class ProspectInfoScreen extends ConsumerStatefulWidget {
  const ProspectInfoScreen({super.key});

  @override
  ConsumerState<ProspectInfoScreen> createState() => _ProspectInfoScreenState();
}

class _ProspectInfoScreenState extends ConsumerState<ProspectInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _zipCtrl = TextEditingController();
  final _referralCodeCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  // Referral validation
  String? _validatedReferrerUid;
  bool _isCheckingReferral = false;
  bool? _referralValid; // null = not checked yet
  Timer? _referralDebounce;

  // Photos
  final List<String> _photoUrls = [];
  bool _isUploadingPhoto = false;

  // Saving
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill from existing active job if resuming
    final existing = ref.read(activeJobProvider);
    if (existing != null) {
      _firstNameCtrl.text = existing.prospect.firstName;
      _lastNameCtrl.text = existing.prospect.lastName;
      _emailCtrl.text = existing.prospect.email;
      _phoneCtrl.text = existing.prospect.phone;
      _addressCtrl.text = existing.prospect.address;
      _cityCtrl.text = existing.prospect.city;
      _stateCtrl.text = existing.prospect.state;
      _zipCtrl.text = existing.prospect.zipCode;
      _referralCodeCtrl.text = existing.prospect.referralCode;
      _notesCtrl.text = existing.prospect.salespersonNotes;
      _photoUrls.addAll(existing.prospect.homePhotoUrls);
      if (existing.prospect.referrerUid.isNotEmpty) {
        _validatedReferrerUid = existing.prospect.referrerUid;
        _referralValid = true;
      }
    }
  }

  @override
  void dispose() {
    _referralDebounce?.cancel();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _zipCtrl.dispose();
    _referralCodeCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ── Referral validation ──────────────────────────────────────

  void _onReferralCodeChanged(String value) {
    _referralDebounce?.cancel();
    setState(() {
      _referralValid = null;
      _validatedReferrerUid = null;
    });
    if (value.trim().isEmpty) return;

    _referralDebounce = Timer(const Duration(milliseconds: 600), () {
      _validateReferralCode(value.trim());
    });
  }

  Future<void> _validateReferralCode(String code) async {
    setState(() => _isCheckingReferral = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('referral_codes')
          .doc(code.toUpperCase())
          .get();
      if (!mounted) return;

      if (doc.exists) {
        setState(() {
          _validatedReferrerUid = doc.data()?['uid'] as String? ?? '';
          _referralValid = true;
          _isCheckingReferral = false;
        });
      } else {
        setState(() {
          _validatedReferrerUid = null;
          _referralValid = false;
          _isCheckingReferral = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _referralValid = false;
          _isCheckingReferral = false;
        });
      }
    }
  }

  // ── Photo capture ────────────────────────────────────────────

  Future<void> _addPhoto() async {
    if (_photoUrls.length >= 6) return;

    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );
    if (image == null || !mounted) return;

    setState(() => _isUploadingPhoto = true);

    try {
      // Ensure we have a draft job
      final jobId = await _ensureDraftJob();
      final bytes = await image.readAsBytes();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance
          .ref()
          .child('sales_jobs/$jobId/prospect/photo_$timestamp.jpg');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();

      if (mounted) {
        setState(() {
          _photoUrls.add(url);
          _isUploadingPhoto = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload photo: $e')),
        );
      }
    }
  }

  void _removePhoto(int index) {
    setState(() => _photoUrls.removeAt(index));
  }

  // ── Draft job management ─────────────────────────────────────

  Future<String> _ensureDraftJob() async {
    final existing = ref.read(activeJobProvider);
    if (existing != null) return existing.id;

    final session = ref.read(currentSalesSessionProvider);
    final jobNumber = await generateJobNumber();
    final jobId = FirebaseFirestore.instance.collection('sales_jobs').doc().id;
    final now = DateTime.now();

    final job = SalesJob(
      id: jobId,
      jobNumber: jobNumber,
      dealerCode: session?.dealerCode ?? '',
      salespersonUid: session?.salespersonUid ?? '',
      prospect: SalesProspect(
        id: jobId,
        firstName: '',
        lastName: '',
        email: '',
        phone: '',
        address: '',
        city: '',
        state: '',
        zipCode: '',
        createdAt: now,
      ),
      zones: const [],
      status: SalesJobStatus.draft,
      totalPriceUsd: 0,
      createdAt: now,
      updatedAt: now,
    );

    ref.read(activeJobProvider.notifier).state = job;
    return jobId;
  }

  // ── Address autocomplete handler ─────────────────────────────

  void _onAddressSelected(AddressSuggestion suggestion) {
    _addressCtrl.text = suggestion.streetAddress;
    if (suggestion.city != null) _cityCtrl.text = suggestion.city!;
    if (suggestion.state != null) {
      final s = suggestion.state!;
      _stateCtrl.text = s.length > 2 ? s.substring(0, 2).toUpperCase() : s.toUpperCase();
    }
    if (suggestion.postcode != null) {
      final zip = suggestion.postcode!.replaceAll(RegExp(r'\D'), '');
      _zipCtrl.text = zip.length > 5 ? zip.substring(0, 5) : zip;
    }
  }

  // ── Save & continue ──────────────────────────────────────────

  Future<void> _saveAndContinue() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);
    ref.read(salesModeProvider.notifier).recordActivity();

    try {
      final jobId = await _ensureDraftJob();
      final now = DateTime.now();
      final session = ref.read(currentSalesSessionProvider);

      final prospect = SalesProspect(
        id: jobId,
        firstName: _firstNameCtrl.text.trim(),
        lastName: _lastNameCtrl.text.trim(),
        email: _emailCtrl.text.trim().toLowerCase(),
        phone: _phoneCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        city: _cityCtrl.text.trim(),
        state: _stateCtrl.text.trim().toUpperCase(),
        zipCode: _zipCtrl.text.trim(),
        referrerUid: _validatedReferrerUid ?? '',
        referralCode: _referralCodeCtrl.text.trim().toUpperCase(),
        homePhotoUrls: List.unmodifiable(_photoUrls),
        salespersonNotes: _notesCtrl.text.trim(),
        createdAt: now,
      );

      final existingJob = ref.read(activeJobProvider);
      final job = (existingJob ?? SalesJob(
        id: jobId,
        jobNumber: await generateJobNumber(),
        dealerCode: session?.dealerCode ?? '',
        salespersonUid: session?.salespersonUid ?? '',
        prospect: prospect,
        zones: const [],
        status: SalesJobStatus.draft,
        totalPriceUsd: 0,
        createdAt: now,
        updatedAt: now,
      )).copyWith(
        prospect: prospect,
        updatedAt: now,
      );

      // Save to Firestore via service
      await ref.read(salesJobServiceProvider).updateJob(job);

      ref.read(activeJobProvider.notifier).state = job;

      // Update referral pipeline if a valid code was entered
      if (_validatedReferrerUid != null && _validatedReferrerUid!.isNotEmpty) {
        try {
          await ref.read(referralPipelineServiceProvider).updateReferralStatus(
            prospectUid: _validatedReferrerUid!,
            newStatus: 'visitScheduled',
            jobId: jobId,
          );
        } catch (_) {
          // Non-blocking — don't prevent navigation
        }
      }

      if (mounted) {
        context.push(AppRoutes.salesZones);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('New Visit'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Column(
        children: [
          // Step indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Step 1 of 3 — Customer info',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: 0.33,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    color: NexGenPalette.cyan,
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),

          // Form
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name row
                    Row(
                      children: [
                        Expanded(child: _buildField(
                          controller: _firstNameCtrl,
                          label: 'First Name',
                          icon: Icons.person_outline,
                          validator: _required,
                        )),
                        const SizedBox(width: 12),
                        Expanded(child: _buildField(
                          controller: _lastNameCtrl,
                          label: 'Last Name',
                          validator: _required,
                        )),
                      ],
                    ),
                    const SizedBox(height: 16),

                    _buildField(
                      controller: _emailCtrl,
                      label: 'Email',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      textCapitalization: TextCapitalization.none,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        if (!RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,}$').hasMatch(v)) {
                          return 'Enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    _buildField(
                      controller: _phoneCtrl,
                      label: 'Phone',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [_PhoneFormatter()],
                      validator: _required,
                    ),
                    const SizedBox(height: 16),

                    // Address with autocomplete
                    AddressAutocomplete(
                      controller: _addressCtrl,
                      onAddressSelected: _onAddressSelected,
                      labelText: 'Address',
                      hintText: 'Start typing an address...',
                    ),
                    const SizedBox(height: 16),

                    // City / State / Zip row
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: _buildField(
                            controller: _cityCtrl,
                            label: 'City',
                            validator: _required,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: _buildField(
                            controller: _stateCtrl,
                            label: 'State',
                            textCapitalization: TextCapitalization.characters,
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(2),
                              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z]')),
                            ],
                            validator: (v) {
                              if (v == null || v.trim().length != 2) return '2 chars';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: _buildField(
                            controller: _zipCtrl,
                            label: 'Zip',
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(5),
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            validator: _required,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Referral code
                    _buildReferralField(),
                    const SizedBox(height: 16),

                    // Notes
                    _buildField(
                      controller: _notesCtrl,
                      label: 'Salesperson Notes',
                      hint: 'Gate code, dog, access notes...',
                      maxLines: 4,
                    ),
                    const SizedBox(height: 24),

                    // Photos section
                    _buildPhotoSection(),
                    const SizedBox(height: 32),

                    // Continue button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveAndContinue,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: NexGenPalette.cyan,
                          disabledBackgroundColor: NexGenPalette.cyan.withValues(alpha: 0.4),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : const Text(
                                'Continue to zones →',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Reusable field builder ──────────────────────────────────

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    String? hint,
    IconData? icon,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.words,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      validator: validator,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: NexGenPalette.textMedium),
        hintText: hint,
        hintStyle: TextStyle(color: NexGenPalette.textMedium.withValues(alpha: 0.5)),
        prefixIcon: icon != null ? Icon(icon, color: NexGenPalette.textMedium) : null,
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
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
      ),
    );
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  // ── Referral code field ─────────────────────────────────────

  Widget _buildReferralField() {
    Widget? suffixIcon;
    if (_isCheckingReferral) {
      suffixIcon = const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: NexGenPalette.cyan),
        ),
      );
    } else if (_referralValid == true) {
      suffixIcon = const Padding(
        padding: EdgeInsets.all(12),
        child: Icon(Icons.check_circle, color: Colors.green, size: 20),
      );
    } else if (_referralValid == false) {
      suffixIcon = const Padding(
        padding: EdgeInsets.all(12),
        child: Icon(Icons.cancel, color: Colors.red, size: 20),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _referralCodeCtrl,
          textCapitalization: TextCapitalization.characters,
          maxLength: 8,
          onChanged: _onReferralCodeChanged,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Referral code (optional)',
            labelStyle: const TextStyle(color: NexGenPalette.textMedium),
            hintText: 'e.g. LUM-A7X3',
            hintStyle: TextStyle(color: NexGenPalette.textMedium.withValues(alpha: 0.5)),
            counterText: '',
            prefixIcon: const Icon(Icons.card_giftcard, color: NexGenPalette.textMedium),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: NexGenPalette.gunmetal90,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: NexGenPalette.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _referralValid == false ? Colors.red : NexGenPalette.line,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _referralValid == false ? Colors.red : NexGenPalette.cyan,
              ),
            ),
          ),
        ),
        if (_referralValid == true)
          const Padding(
            padding: EdgeInsets.only(left: 12, top: 4),
            child: Text('Code accepted', style: TextStyle(color: Colors.green, fontSize: 12)),
          ),
        if (_referralValid == false)
          const Padding(
            padding: EdgeInsets.only(left: 12, top: 4),
            child: Text('Code not found', style: TextStyle(color: Colors.red, fontSize: 12)),
          ),
      ],
    );
  }

  // ── Photo section ───────────────────────────────────────────

  Widget _buildPhotoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Home photos',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          'Add photos of the home exterior and install areas',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _photoUrls.length + (_photoUrls.length < 6 ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              // "Add photo" tile
              if (i == _photoUrls.length) {
                return GestureDetector(
                  onTap: _isUploadingPhoto ? null : _addPhoto,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: NexGenPalette.gunmetal90,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: NexGenPalette.cyan.withValues(alpha: 0.3),
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: _isUploadingPhoto
                        ? const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: NexGenPalette.cyan,
                              ),
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_a_photo_outlined,
                                  color: NexGenPalette.cyan, size: 28),
                              const SizedBox(height: 4),
                              Text(
                                'Add photo',
                                style: TextStyle(
                                  color: NexGenPalette.cyan,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                  ),
                );
              }

              // Photo tile
              return Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      _photoUrls[i],
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          width: 100,
                          height: 100,
                          color: NexGenPalette.gunmetal90,
                          child: const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: NexGenPalette.cyan,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _removePhoto(i),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Phone number formatter ────────────────────────────────────

class _PhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();

    for (int i = 0; i < digits.length && i < 10; i++) {
      if (i == 0) buffer.write('(');
      if (i == 3) buffer.write(') ');
      if (i == 6) buffer.write('-');
      buffer.write(digits[i]);
    }

    return TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection.collapsed(offset: buffer.length),
    );
  }
}

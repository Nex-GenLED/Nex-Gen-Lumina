import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/demo/demo_lead_service.dart';
import 'package:nexgen_command/features/demo/demo_models.dart';
import 'package:nexgen_command/features/demo/demo_providers.dart';
import 'package:nexgen_command/features/demo/widgets/demo_scaffold.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/theme.dart';
import 'package:uuid/uuid.dart';

/// Profile setup screen for demo lead capture.
///
/// Collects:
/// - Name (optional)
/// - Email (required)
/// - Phone (required)
/// - Zip Code (required)
/// - Home Type (optional)
/// - Referral Source (optional)
class DemoProfileScreen extends ConsumerStatefulWidget {
  const DemoProfileScreen({super.key});

  @override
  ConsumerState<DemoProfileScreen> createState() => _DemoProfileScreenState();
}

class _DemoProfileScreenState extends ConsumerState<DemoProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _zipController = TextEditingController();

  HomeType? _selectedHomeType;
  ReferralSource? _selectedReferralSource;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _zipController.dispose();
    super.dispose();
  }

  Future<void> _submitProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      // Create lead object
      final lead = DemoLead(
        id: const Uuid().v4(),
        name: _nameController.text.trim().isEmpty
            ? null
            : _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        zipCode: _zipController.text.trim(),
        homeType: _selectedHomeType,
        referralSource: _selectedReferralSource,
        capturedAt: DateTime.now(),
      );

      // Store in provider
      ref.read(demoLeadProvider.notifier).state = lead;

      // Submit to Firestore
      final leadService = ref.read(demoLeadServiceProvider);
      await leadService.submitLead(lead);

      // Log analytics
      await leadService.logAnalyticsEvent(
        event: 'profile_completed',
        leadId: lead.id,
      );

      if (!mounted) return;

      // Advance to next step
      ref.read(demoFlowProvider.notifier).goToStep(DemoStep.photoCapture);
      context.push(AppRoutes.demoPhoto);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving profile: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DemoScaffold(
      title: 'Tell Us About Yourself',
      subtitle: 'So we can personalize your demo experience',
      showSkip: false,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

              // Name field (optional)
              _buildTextField(
                controller: _nameController,
                label: 'Name',
                hint: 'John Smith',
                icon: Icons.person_outline,
                required: false,
                textCapitalization: TextCapitalization.words,
              ),

              const SizedBox(height: 20),

              // Email field (required)
              _buildTextField(
                controller: _emailController,
                label: 'Email',
                hint: 'john@example.com',
                icon: Icons.email_outlined,
                required: true,
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Email is required';
                  }
                  final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                  if (!emailRegex.hasMatch(value)) {
                    return 'Please enter a valid email';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 20),

              // Phone field (required)
              _buildTextField(
                controller: _phoneController,
                label: 'Phone',
                hint: '(555) 123-4567',
                icon: Icons.phone_outlined,
                required: true,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  _PhoneNumberFormatter(),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Phone is required';
                  }
                  final digits = value.replaceAll(RegExp(r'\D'), '');
                  if (digits.length < 10) {
                    return 'Please enter a valid phone number';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 20),

              // Zip code field (required)
              _buildTextField(
                controller: _zipController,
                label: 'Zip Code',
                hint: '12345',
                icon: Icons.location_on_outlined,
                required: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(5),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Zip code is required';
                  }
                  if (value.length != 5) {
                    return 'Please enter a valid 5-digit zip code';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // Home type dropdown (optional)
              _buildDropdown<HomeType>(
                label: 'Home Type',
                icon: Icons.home_outlined,
                value: _selectedHomeType,
                items: HomeType.values,
                itemLabel: (item) => item.displayName,
                onChanged: (value) {
                  setState(() => _selectedHomeType = value);
                },
              ),

              const SizedBox(height: 20),

              // Referral source dropdown (optional)
              _buildDropdown<ReferralSource>(
                label: 'How did you hear about us?',
                icon: Icons.hearing_outlined,
                value: _selectedReferralSource,
                items: ReferralSource.values,
                itemLabel: (item) => item.displayName,
                onChanged: (value) {
                  setState(() => _selectedReferralSource = value);
                },
              ),

              const SizedBox(height: 32),

              // Privacy note
              DemoInfoBanner(
                message:
                    'Your information is secure and will only be used to help you get started with Nex-Gen lighting.',
                icon: Icons.lock_outline,
                color: NexGenPalette.textMedium,
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      bottomAction: DemoPrimaryButton(
        label: 'Continue',
        icon: Icons.arrow_forward,
        isLoading: _isSubmitting,
        onPressed: _submitProfile,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool required = false,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            if (required)
              Text(
                ' *',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Colors.red,
                    ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          inputFormatters: inputFormatters,
          validator: validator ??
              (required
                  ? (value) {
                      if (value == null || value.isEmpty) {
                        return '$label is required';
                      }
                      return null;
                    }
                  : null),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required IconData icon,
    required T? value,
    required List<T> items,
    required String Function(T) itemLabel,
    required void Function(T?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<T>(
          value: value,
          decoration: InputDecoration(
            prefixIcon: Icon(icon),
            hintText: 'Select...',
          ),
          items: items.map((item) {
            return DropdownMenuItem<T>(
              value: item,
              child: Text(itemLabel(item)),
            );
          }).toList(),
          onChanged: onChanged,
          dropdownColor: NexGenPalette.gunmetal,
          borderRadius: BorderRadius.circular(12),
        ),
      ],
    );
  }
}

/// Input formatter for phone numbers.
/// Formats as (XXX) XXX-XXXX
class _PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    if (digits.isEmpty) {
      return newValue.copyWith(text: '');
    }

    final buffer = StringBuffer();

    for (int i = 0; i < digits.length && i < 10; i++) {
      if (i == 0) buffer.write('(');
      if (i == 3) buffer.write(') ');
      if (i == 6) buffer.write('-');
      buffer.write(digits[i]);
    }

    return newValue.copyWith(
      text: buffer.toString(),
      selection: TextSelection.collapsed(offset: buffer.length),
    );
  }
}

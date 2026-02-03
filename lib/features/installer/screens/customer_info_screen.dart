import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/schedule/geocoding_service.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/address_autocomplete.dart';

/// Phase 2.1: Customer Information collection screen
class CustomerInfoScreen extends ConsumerStatefulWidget {
  final VoidCallback onNext;

  const CustomerInfoScreen({super.key, required this.onNext});

  @override
  ConsumerState<CustomerInfoScreen> createState() => _CustomerInfoScreenState();
}

class _CustomerInfoScreenState extends ConsumerState<CustomerInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _zipController = TextEditingController();
  final _notesController = TextEditingController();

  // Email uniqueness validation state
  String? _emailUniquenessError;
  bool _isCheckingEmail = false;
  bool _emailIsUnique = false;
  Timer? _emailDebouncer;

  @override
  void initState() {
    super.initState();
    // Load existing data if any
    final existingInfo = ref.read(installerCustomerInfoProvider);
    _nameController.text = existingInfo.name;
    _emailController.text = existingInfo.email;
    _phoneController.text = existingInfo.phone;
    _addressController.text = existingInfo.address;
    _cityController.text = existingInfo.city;
    _stateController.text = existingInfo.state;
    _zipController.text = existingInfo.zipCode;
    _notesController.text = existingInfo.notes;

    // If email already exists, validate it
    if (existingInfo.email.isNotEmpty) {
      _validateEmailUniqueness(existingInfo.email);
    }
  }

  @override
  void dispose() {
    _emailDebouncer?.cancel();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _zipController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// Validate email uniqueness against Firebase Auth
  /// Note: This attempts to check if an email is already registered
  Future<void> _validateEmailUniqueness(String email) async {
    // Basic format check first
    if (email.isEmpty || !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      setState(() {
        _emailUniquenessError = null;
        _emailIsUnique = false;
        _isCheckingEmail = false;
      });
      return;
    }

    setState(() {
      _isCheckingEmail = true;
      _emailUniquenessError = null;
      _emailIsUnique = false;
    });

    try {
      // Try to sign in with the email and a dummy password
      // If the email exists, we'll get a specific error code
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: '_check_email_exists_dummy_password_12345',
      );

      // If we somehow succeed (shouldn't happen), sign out
      await FirebaseAuth.instance.signOut();

      // Email exists (though this branch is unlikely)
      if (mounted) {
        setState(() {
          _isCheckingEmail = false;
          _emailUniquenessError = 'An account with this email already exists';
          _emailIsUnique = false;
        });
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _isCheckingEmail = false;

          if (e.code == 'user-not-found') {
            // Email doesn't exist - this is what we want
            _emailUniquenessError = null;
            _emailIsUnique = true;
          } else if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
            // Email exists but password is wrong
            _emailUniquenessError = 'An account with this email already exists';
            _emailIsUnique = false;
          } else if (e.code == 'too-many-requests') {
            // Too many attempts - can't verify, allow to proceed
            _emailUniquenessError = null;
            _emailIsUnique = true;
          } else {
            // Other errors - allow to proceed (will catch at account creation)
            _emailUniquenessError = null;
            _emailIsUnique = true;
          }
        });
      }
    } catch (e) {
      // General error - allow to proceed
      if (mounted) {
        setState(() {
          _isCheckingEmail = false;
          _emailUniquenessError = null;
          _emailIsUnique = true;
        });
      }
    }
  }

  void _onEmailChanged(String value) {
    // Cancel previous debounce timer
    _emailDebouncer?.cancel();

    // Reset state immediately
    setState(() {
      _emailUniquenessError = null;
      _emailIsUnique = false;
    });

    // Debounce the uniqueness check
    _emailDebouncer = Timer(const Duration(milliseconds: 500), () {
      _validateEmailUniqueness(value);
    });
  }

  /// Auto-fill city, state, and zip when an address is selected
  void _onAddressSelected(AddressSuggestion suggestion) {
    // Update address field with street address
    _addressController.text = suggestion.streetAddress;

    // Auto-fill city, state, zip if available
    if (suggestion.city != null) {
      _cityController.text = suggestion.city!;
    }
    if (suggestion.state != null) {
      // Extract state abbreviation if full state name provided
      final state = suggestion.state!;
      _stateController.text = state.length > 2 ? _getStateAbbreviation(state) : state;
    }
    if (suggestion.postcode != null) {
      // Take first 5 digits of zip code
      final zip = suggestion.postcode!.replaceAll(RegExp(r'\D'), '');
      _zipController.text = zip.length > 5 ? zip.substring(0, 5) : zip;
    }
  }

  /// Convert full state name to abbreviation
  String _getStateAbbreviation(String fullName) {
    const stateAbbreviations = {
      'alabama': 'AL', 'alaska': 'AK', 'arizona': 'AZ', 'arkansas': 'AR',
      'california': 'CA', 'colorado': 'CO', 'connecticut': 'CT', 'delaware': 'DE',
      'florida': 'FL', 'georgia': 'GA', 'hawaii': 'HI', 'idaho': 'ID',
      'illinois': 'IL', 'indiana': 'IN', 'iowa': 'IA', 'kansas': 'KS',
      'kentucky': 'KY', 'louisiana': 'LA', 'maine': 'ME', 'maryland': 'MD',
      'massachusetts': 'MA', 'michigan': 'MI', 'minnesota': 'MN', 'mississippi': 'MS',
      'missouri': 'MO', 'montana': 'MT', 'nebraska': 'NE', 'nevada': 'NV',
      'new hampshire': 'NH', 'new jersey': 'NJ', 'new mexico': 'NM', 'new york': 'NY',
      'north carolina': 'NC', 'north dakota': 'ND', 'ohio': 'OH', 'oklahoma': 'OK',
      'oregon': 'OR', 'pennsylvania': 'PA', 'rhode island': 'RI', 'south carolina': 'SC',
      'south dakota': 'SD', 'tennessee': 'TN', 'texas': 'TX', 'utah': 'UT',
      'vermont': 'VT', 'virginia': 'VA', 'washington': 'WA', 'west virginia': 'WV',
      'wisconsin': 'WI', 'wyoming': 'WY', 'district of columbia': 'DC',
    };
    return stateAbbreviations[fullName.toLowerCase()] ?? fullName;
  }

  void _saveAndContinue() {
    // Check for email uniqueness error first
    if (_emailUniquenessError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please use a different email address'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Check if still checking email
    if (_isCheckingEmail) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait while we verify the email address'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_formKey.currentState?.validate() ?? false) {
      // Save customer info to provider
      ref.read(installerCustomerInfoProvider.notifier).state = CustomerInfo(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        address: _addressController.text.trim(),
        city: _cityController.text.trim(),
        state: _stateController.text.trim(),
        zipCode: _zipController.text.trim(),
        notes: _notesController.text.trim(),
      );

      // Record activity
      ref.read(installerModeActiveProvider.notifier).recordActivity();

      widget.onNext();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header
            const Text(
              'Customer Information',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter the homeowner\'s contact details for their account.',
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
            ),
            const SizedBox(height: 32),

            // Name field
            _buildTextField(
              controller: _nameController,
              label: 'Full Name',
              hint: 'John Smith',
              icon: Icons.person_outline,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // Email field with uniqueness validation
            _buildEmailField(),
            const SizedBox(height: 20),

            // Phone field
            _buildTextField(
              controller: _phoneController,
              label: 'Phone Number',
              hint: '(555) 123-4567',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                _PhoneNumberFormatter(),
              ],
            ),
            const SizedBox(height: 32),

            // Address section header
            const Text(
              'Installation Address',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),

            // Street address with autocomplete
            AddressAutocomplete(
              controller: _addressController,
              labelText: 'Street Address',
              hintText: 'Start typing to search...',
              maxLines: 1,
              onAddressSelected: (suggestion) => _onAddressSelected(suggestion),
            ),
            const SizedBox(height: 20),

            // City, State, Zip row (auto-populated from address selection)
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _buildTextField(
                    controller: _cityController,
                    label: 'City',
                    hint: 'Auto-filled',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    controller: _stateController,
                    label: 'State',
                    hint: 'ST',
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z]')),
                      LengthLimitingTextInputFormatter(2),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    controller: _zipController,
                    label: 'ZIP',
                    hint: '00000',
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(5),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Notes section
            const Text(
              'Installation Notes',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Any special instructions or details about the installation.',
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
            ),
            const SizedBox(height: 16),

            // Notes field
            TextFormField(
              controller: _notesController,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'e.g., Gate code: 1234, Dog in backyard, etc.',
                hintStyle: const TextStyle(color: NexGenPalette.textMedium),
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
            ),
            const SizedBox(height: 40),

            // Next button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveAndContinue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: NexGenPalette.cyan,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text(
                  'Continue to Controller Setup',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailField() {
    Widget? suffixIcon;

    if (_isCheckingEmail) {
      suffixIcon = const SizedBox(
        width: 20,
        height: 20,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(strokeWidth: 2, color: NexGenPalette.cyan),
        ),
      );
    } else if (_emailUniquenessError != null) {
      suffixIcon = const Padding(
        padding: EdgeInsets.all(12),
        child: Icon(Icons.error_outline, color: Colors.red, size: 20),
      );
    } else if (_emailIsUnique && _emailController.text.isNotEmpty) {
      suffixIcon = const Padding(
        padding: EdgeInsets.all(12),
        child: Icon(Icons.check_circle, color: Colors.green, size: 20),
      );
    }

    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      textCapitalization: TextCapitalization.none,
      onChanged: _onEmailChanged,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Email is required';
        }
        if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
          return 'Enter a valid email address';
        }
        if (_emailUniquenessError != null) {
          return _emailUniquenessError;
        }
        return null;
      },
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: 'Email Address',
        labelStyle: const TextStyle(color: NexGenPalette.textMedium),
        hintText: 'john@example.com',
        hintStyle: TextStyle(color: NexGenPalette.textMedium.withValues(alpha: 0.5)),
        prefixIcon: const Icon(Icons.email_outlined, color: NexGenPalette.textMedium),
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
            color: _emailUniquenessError != null ? Colors.red : NexGenPalette.line,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: _emailUniquenessError != null ? Colors.red : NexGenPalette.cyan,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        errorText: _emailUniquenessError,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    IconData? icon,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.words,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      validator: validator,
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
}

/// Formats phone numbers as (XXX) XXX-XXXX
class _PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();

    for (var i = 0; i < digits.length && i < 10; i++) {
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

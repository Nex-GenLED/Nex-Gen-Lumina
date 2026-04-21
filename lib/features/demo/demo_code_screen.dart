import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nexgen_command/models/dealer_demo_code.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/services/demo_code_service.dart';
import 'package:nexgen_command/theme.dart';

/// Stores the validated demo code for downstream use.
final validatedDemoCodeProvider = StateProvider<DealerDemoCode?>((ref) => null);

/// Gate screen shown before the demo welcome flow.
/// Requires a valid dealer referral code to proceed.
class DemoCodeScreen extends ConsumerStatefulWidget {
  const DemoCodeScreen({super.key});

  @override
  ConsumerState<DemoCodeScreen> createState() => _DemoCodeScreenState();
}

class _DemoCodeScreenState extends ConsumerState<DemoCodeScreen>
    with SingleTickerProviderStateMixin {
  final _codeController = TextEditingController();
  late final AnimationController _shakeController;
  bool _isValidating = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _validate() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _errorText = 'Please enter a demo code');
      return;
    }

    setState(() {
      _isValidating = true;
      _errorText = null;
    });

    try {
      final service = ref.read(demoCodeServiceProvider);
      final result = await service.validateCode(code);

      if (!mounted) return;

      if (result != null) {
        ref.read(validatedDemoCodeProvider.notifier).state = result;
        context.go(AppRoutes.demoWelcome);
      } else {
        _shakeController.forward(from: 0);
        setState(() {
          _errorText =
              'Invalid code \u2014 ask your Nex-Gen specialist for a valid code';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorText = 'Could not verify code. Please try again.');
    } finally {
      if (mounted) setState(() => _isValidating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      body: Container(
        decoration: const BoxDecoration(
          gradient: BrandGradients.atmosphere,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Back button
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8, top: 8),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white70, size: 20),
                    onPressed: () => context.go(AppRoutes.login),
                  ),
                ),
              ),

              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Logo icon
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                NexGenPalette.cyan,
                                NexGenPalette.blue,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: NexGenPalette.cyan.withValues(alpha: 0.3),
                                blurRadius: 24,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.hub,
                            size: 40,
                            color: Colors.black,
                          ),
                        ),

                        const SizedBox(height: 32),

                        Text(
                          'Enter Your Demo Code',
                          style:
                              Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 8),

                        Text(
                          'Get your code from a Nex-Gen LED specialist',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: NexGenPalette.textMedium,
                                  ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 40),

                        // Code input with shake animation
                        AnimatedBuilder(
                          animation: _shakeController,
                          builder: (context, child) {
                            final offset = _shakeController.isAnimating
                                ? sin(_shakeController.value * pi * 6) * 8
                                : 0.0;
                            return Transform.translate(
                              offset: Offset(offset, 0),
                              child: child,
                            );
                          },
                          child: TextField(
                            controller: _codeController,
                            maxLength: 6,
                            textAlign: TextAlign.center,
                            textCapitalization: TextCapitalization.characters,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[a-zA-Z0-9]')),
                              UpperCaseTextFormatter(),
                            ],
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 8,
                            ),
                            decoration: InputDecoration(
                              counterText: '',
                              hintText: '------',
                              hintStyle: GoogleFonts.jetBrainsMono(
                                fontSize: 28,
                                fontWeight: FontWeight.w400,
                                color: Colors.white24,
                                letterSpacing: 8,
                              ),
                              filled: true,
                              fillColor: NexGenPalette.gunmetal.withValues(alpha: 0.5),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide:
                                    const BorderSide(color: NexGenPalette.line),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                    color: NexGenPalette.cyan, width: 2),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 20),
                            ),
                            onSubmitted: (_) => _validate(),
                          ),
                        ),

                        // Error text
                        if (_errorText != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _errorText!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.redAccent),
                            textAlign: TextAlign.center,
                          ),
                        ],

                        const SizedBox(height: 32),

                        // Start Demo button
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton(
                            onPressed: _isValidating ? null : _validate,
                            child: _isValidating
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.black),
                                  )
                                : const Text('Start Demo'),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Consultation link
                        Text(
                          "Don't have a code? Request a consultation at",
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: NexGenPalette.textMedium,
                                  ),
                          textAlign: TextAlign.center,
                        ),
                        GestureDetector(
                          onTap: () => launchUrl(
                            Uri.parse('https://nex-genled.com'),
                            mode: LaunchMode.externalApplication,
                          ),
                          child: Text(
                            'Nex-GenLED.com',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: NexGenPalette.cyan,
                                      decoration: TextDecoration.underline,
                                      decorationColor: NexGenPalette.cyan,
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Formats text input to uppercase as the user types.
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

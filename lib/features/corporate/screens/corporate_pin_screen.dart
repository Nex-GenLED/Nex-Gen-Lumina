import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/corporate/providers/corporate_providers.dart';
import 'package:nexgen_command/theme.dart';

/// Corporate Mode PIN entry screen.
///
/// Mirrors [SalesPinScreen] in structure and styling. The corporate PIN
/// is a single 4-digit value validated against `app_config/master_corporate_pin`.
class CorporatePinScreen extends ConsumerStatefulWidget {
  const CorporatePinScreen({super.key});

  @override
  ConsumerState<CorporatePinScreen> createState() => _CorporatePinScreenState();
}

class _CorporatePinScreenState extends ConsumerState<CorporatePinScreen>
    with SingleTickerProviderStateMixin {
  String _enteredPin = '';
  bool _isValidating = false;
  int _failedAttempts = 0;
  String? _errorMessage;
  late AnimationController _shakeController;

  static const int _maxAttempts = 5;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _onDigit(String digit) {
    if (_isValidating || _failedAttempts >= _maxAttempts) return;
    if (_enteredPin.length >= 4) return;

    HapticFeedback.lightImpact();
    setState(() {
      _enteredPin += digit;
      _errorMessage = null;
    });

    if (_enteredPin.length == 4) {
      _validatePin();
    }
  }

  void _onBackspace() {
    if (_enteredPin.isEmpty || _isValidating) return;
    HapticFeedback.lightImpact();
    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      _errorMessage = null;
    });
  }

  Future<void> _validatePin() async {
    setState(() => _isValidating = true);

    final success = await ref
        .read(corporateModeProvider.notifier)
        .authenticate(_enteredPin);

    if (!mounted) return;

    if (success) {
      HapticFeedback.mediumImpact();
      context.go(AppRoutes.corporateDashboard);
    } else {
      _failedAttempts++;
      _shakeController.forward(from: 0);
      HapticFeedback.heavyImpact();
      setState(() {
        _enteredPin = '';
        _isValidating = false;
        _errorMessage = _failedAttempts >= _maxAttempts
            ? 'Too many attempts. Restart the app to try again.'
            : 'Invalid corporate PIN. ${_maxAttempts - _failedAttempts} attempts remaining.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLockedOut = _failedAttempts >= _maxAttempts;

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/');
            }
          },
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),

            Text(
              'Corporate Mode',
              style: GoogleFonts.montserrat(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Nex-Gen LED Systems — internal access',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: NexGenPalette.gold.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Enter 4-digit corporate PIN',
                    style: TextStyle(
                      color: NexGenPalette.gold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // PIN dots display — single solid color (gold) for corporate
            AnimatedBuilder(
              animation: _shakeController,
              builder: (context, child) {
                final offset = _shakeController.isAnimating
                    ? 10.0 *
                        (0.5 - _shakeController.value).abs() *
                        (_shakeController.value < 0.5 ? -1 : 1)
                    : 0.0;
                return Transform.translate(
                  offset: Offset(offset, 0),
                  child: child,
                );
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (i) {
                  final isFilled = i < _enteredPin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFilled ? NexGenPalette.gold : Colors.transparent,
                      border: Border.all(
                        color: isFilled
                            ? NexGenPalette.gold
                            : Colors.white.withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                  );
                }),
              ),
            ),

            const SizedBox(height: 16),
            SizedBox(
              height: 20,
              child: _errorMessage != null
                  ? Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    )
                  : _isValidating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: NexGenPalette.gold,
                          ),
                        )
                      : null,
            ),

            const Spacer(flex: 1),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Column(
                children: [
                  _buildKeypadRow(['1', '2', '3'], isLockedOut),
                  const SizedBox(height: 12),
                  _buildKeypadRow(['4', '5', '6'], isLockedOut),
                  const SizedBox(height: 12),
                  _buildKeypadRow(['7', '8', '9'], isLockedOut),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      const SizedBox(width: 72, height: 72),
                      _buildKeypadButton('0', isLockedOut),
                      SizedBox(
                        width: 72,
                        height: 72,
                        child: IconButton(
                          onPressed: isLockedOut ? null : _onBackspace,
                          icon: Icon(
                            Icons.backspace_outlined,
                            color: isLockedOut
                                ? Colors.white.withValues(alpha: 0.2)
                                : Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }

  Widget _buildKeypadRow(List<String> digits, bool disabled) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: digits.map((d) => _buildKeypadButton(d, disabled)).toList(),
    );
  }

  Widget _buildKeypadButton(String digit, bool disabled) {
    return SizedBox(
      width: 72,
      height: 72,
      child: TextButton(
        onPressed: disabled ? null : () => _onDigit(digit),
        style: TextButton.styleFrom(
          shape: const CircleBorder(),
          backgroundColor: Colors.white.withValues(alpha: 0.06),
        ),
        child: Text(
          digit,
          style: GoogleFonts.montserrat(
            fontSize: 28,
            fontWeight: FontWeight.w400,
            color: disabled
                ? Colors.white.withValues(alpha: 0.2)
                : Colors.white,
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/sales/sales_providers.dart';
import 'package:nexgen_command/theme.dart';

/// Sales Mode PIN entry screen.
/// Mirrors installer_pin_screen.dart exactly in structure and style.
class SalesPinScreen extends ConsumerStatefulWidget {
  const SalesPinScreen({super.key});

  @override
  ConsumerState<SalesPinScreen> createState() => _SalesPinScreenState();
}

class _SalesPinScreenState extends ConsumerState<SalesPinScreen>
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
        .read(salesModeProvider.notifier)
        .enterSalesMode(_enteredPin);

    if (!mounted) return;

    if (success) {
      HapticFeedback.mediumImpact();
      context.go(AppRoutes.salesLanding);
    } else {
      _failedAttempts++;
      _shakeController.forward(from: 0);
      HapticFeedback.heavyImpact();
      setState(() {
        _enteredPin = '';
        _isValidating = false;
        _errorMessage = _failedAttempts >= _maxAttempts
            ? 'Too many attempts. Restart the app to try again.'
            : 'Invalid sales code. ${_maxAttempts - _failedAttempts} attempts remaining.';
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

            // Title
            Text(
              'Sales Mode',
              style: GoogleFonts.montserrat(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter your 4-digit sales code',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),

            // PIN format hint
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: NexGenPalette.violet.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Dealer',
                    style: TextStyle(color: NexGenPalette.violet, fontSize: 11),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: NexGenPalette.cyan.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Salesperson',
                    style: TextStyle(color: NexGenPalette.cyan, fontSize: 11),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // PIN dots display
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
                  final isDealer = i < 2;
                  final activeColor = isDealer ? NexGenPalette.violet : NexGenPalette.cyan;

                  return Container(
                    margin: EdgeInsets.only(
                      left: 10,
                      right: i == 1 ? 20 : 10, // gap between dealer/salesperson
                    ),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFilled ? activeColor : Colors.transparent,
                      border: Border.all(
                        color: isFilled
                            ? activeColor
                            : Colors.white.withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                  );
                }),
              ),
            ),

            // Error message
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
                            color: NexGenPalette.cyan,
                          ),
                        )
                      : null,
            ),

            const Spacer(flex: 1),

            // Numeric keypad
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
                      // Empty space
                      const SizedBox(width: 72, height: 72),
                      // 0
                      _buildKeypadButton('0', isLockedOut),
                      // Backspace
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

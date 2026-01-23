import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/theme.dart';

/// PIN entry screen for installer mode access
/// PIN format: [DD][II] where DD = 2-digit dealer code, II = 2-digit installer code
class InstallerPinScreen extends ConsumerStatefulWidget {
  const InstallerPinScreen({super.key});

  @override
  ConsumerState<InstallerPinScreen> createState() => _InstallerPinScreenState();
}

class _InstallerPinScreenState extends ConsumerState<InstallerPinScreen> {
  String _enteredPin = '';
  bool _showError = false;
  bool _isLoading = false;
  int _attemptCount = 0;
  static const int _maxAttempts = 5;
  static const int _pinLength = 4;

  void _onKeyPressed(String key) {
    if (_isLoading) return;
    if (_enteredPin.length < _pinLength) {
      HapticFeedback.lightImpact();
      setState(() {
        _enteredPin += key;
        _showError = false;
      });

      // Auto-submit when PIN is complete
      if (_enteredPin.length == _pinLength) {
        _submitPin();
      }
    }
  }

  void _onBackspace() {
    if (_isLoading) return;
    if (_enteredPin.isNotEmpty) {
      HapticFeedback.lightImpact();
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        _showError = false;
      });
    }
  }

  Future<void> _submitPin() async {
    setState(() => _isLoading = true);

    try {
      final success = await ref.read(installerModeActiveProvider.notifier).enterInstallerMode(_enteredPin);

      if (!mounted) return;

      if (success) {
        HapticFeedback.mediumImpact();
        // Navigate to installer wizard
        context.go('/installer/wizard');
      } else {
        HapticFeedback.heavyImpact();
        setState(() {
          _showError = true;
          _attemptCount++;
          _enteredPin = '';
          _isLoading = false;
        });

        // Lock out after max attempts
        if (_attemptCount >= _maxAttempts) {
          _showLockoutDialog();
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _showError = true;
        _enteredPin = '';
        _isLoading = false;
      });
    }
  }

  void _showLockoutDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text('Too Many Attempts', style: TextStyle(color: Colors.white)),
        content: const Text(
          'You have exceeded the maximum number of PIN attempts. Please try again later.',
          style: TextStyle(color: NexGenPalette.textMedium),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.pop();
            },
            child: const Text('OK', style: TextStyle(color: NexGenPalette.cyan)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text('Installer Access', style: TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // Lock icon
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: NexGenPalette.gunmetal90,
                  border: Border.all(color: NexGenPalette.line),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(color: NexGenPalette.cyan, strokeWidth: 3),
                      )
                    : Icon(
                        Icons.engineering_outlined,
                        size: 48,
                        color: _showError ? Colors.red : NexGenPalette.cyan,
                      ),
              ),
              const SizedBox(height: 32),
              // Title
              Text(
                'Enter Installer PIN',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'This area is restricted to authorized installers',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: NexGenPalette.textMedium,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              // PIN format hint
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: NexGenPalette.gunmetal90.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: NexGenPalette.line.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: NexGenPalette.textMedium),
                    const SizedBox(width: 8),
                    Text(
                      'Format: Dealer Code (2) + Installer Code (2)',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: NexGenPalette.textMedium,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              // PIN dots with labels
              Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Dealer code section
                      Column(
                        children: [
                          Row(
                            children: List.generate(2, (index) {
                              final isFilled = index < _enteredPin.length;
                              return Container(
                                margin: const EdgeInsets.symmetric(horizontal: 8),
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isFilled
                                      ? (_showError ? Colors.red : NexGenPalette.violet)
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: _showError ? Colors.red : NexGenPalette.violet.withValues(alpha: 0.7),
                                    width: 2,
                                  ),
                                ),
                              );
                            }),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Dealer',
                            style: TextStyle(
                              color: NexGenPalette.violet.withValues(alpha: 0.8),
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 24),
                      // Installer code section
                      Column(
                        children: [
                          Row(
                            children: List.generate(2, (index) {
                              final actualIndex = index + 2;
                              final isFilled = actualIndex < _enteredPin.length;
                              return Container(
                                margin: const EdgeInsets.symmetric(horizontal: 8),
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isFilled
                                      ? (_showError ? Colors.red : NexGenPalette.cyan)
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: _showError ? Colors.red : NexGenPalette.cyan.withValues(alpha: 0.7),
                                    width: 2,
                                  ),
                                ),
                              );
                            }),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Installer',
                            style: TextStyle(
                              color: NexGenPalette.cyan.withValues(alpha: 0.8),
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Error message
              AnimatedOpacity(
                opacity: _showError ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Text(
                  'Incorrect PIN. ${_maxAttempts - _attemptCount} attempts remaining.',
                  style: const TextStyle(color: Colors.red, fontSize: 14),
                ),
              ),
              const SizedBox(height: 32),
              // Numeric keypad
              _buildKeypad(),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeypad() {
    return Column(
      children: [
        _buildKeypadRow(['1', '2', '3']),
        const SizedBox(height: 16),
        _buildKeypadRow(['4', '5', '6']),
        const SizedBox(height: 16),
        _buildKeypadRow(['7', '8', '9']),
        const SizedBox(height: 16),
        _buildKeypadRow(['', '0', 'backspace']),
      ],
    );
  }

  Widget _buildKeypadRow(List<String> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: keys.map((key) {
        if (key.isEmpty) {
          return const SizedBox(width: 80, height: 80);
        }
        if (key == 'backspace') {
          return _buildKeypadButton(
            onPressed: _onBackspace,
            child: const Icon(Icons.backspace_outlined, color: Colors.white, size: 28),
          );
        }
        return _buildKeypadButton(
          onPressed: () => _onKeyPressed(key),
          child: Text(
            key,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildKeypadButton({required VoidCallback onPressed, required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(40),
          child: Opacity(
            opacity: _isLoading ? 0.5 : 1.0,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: NexGenPalette.gunmetal90,
                border: Border.all(color: NexGenPalette.line),
              ),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

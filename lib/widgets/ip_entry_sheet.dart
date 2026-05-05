import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexgen_command/theme.dart';

/// Bottom sheet for IP-address entry. Replaces the legacy AlertDialog
/// pattern that consistently failed to lift its TextField above the
/// software keyboard on iOS regardless of inset-padding strategy.
///
/// The fix is `viewInsets.bottom` padding at the WIDGET ROOT (not on
/// the AlertDialog container) — this lifts the entire sheet up as the
/// keyboard appears so the input stays visible above it. Used for both
/// bridge IP entry (BridgeSetupScreen) and controller IP entry
/// (ControllerSetupScreen).
class IpEntrySheet extends StatefulWidget {
  const IpEntrySheet({
    super.key,
    required this.title,
    this.hintText = '192.168.1.100',
  });

  final String title;
  final String hintText;

  @override
  State<IpEntrySheet> createState() => _IpEntrySheetState();
}

class _IpEntrySheetState extends State<IpEntrySheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: Container(
        decoration: const BoxDecoration(
          color: NexGenPalette.gunmetal90,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(20),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: NexGenPalette.textMedium.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.title,
              style: GoogleFonts.exo2(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                LengthLimitingTextInputFormatter(15),
              ],
              onSubmitted: (v) => Navigator.pop(context, v.trim()),
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: TextStyle(
                  color: NexGenPalette.textMedium.withValues(alpha: 0.5),
                ),
                filled: true,
                fillColor: NexGenPalette.matteBlack,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: NexGenPalette.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: NexGenPalette.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: NexGenPalette.cyan,
                    width: 2,
                  ),
                ),
                prefixIcon: const Icon(
                  Icons.lan_outlined,
                  color: NexGenPalette.cyan,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: NexGenPalette.line),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: NexGenPalette.textMedium),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () =>
                        Navigator.pop(context, _ctrl.text.trim()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NexGenPalette.cyan,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      'Connect',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Convenience helper that opens [IpEntrySheet] as a modal bottom sheet
/// with the standard styling (transparent backdrop so the sheet's own
/// rounded gunmetal container shows; isScrollControlled: true so the
/// sheet can grow tall enough to hold the keyboard offset).
///
/// Returns the trimmed entered IP, or null if the user cancelled.
Future<String?> showIpEntrySheet(
  BuildContext context, {
  required String title,
  String hintText = '192.168.1.100',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => IpEntrySheet(
      title: title,
      hintText: hintText,
    ),
  );
}

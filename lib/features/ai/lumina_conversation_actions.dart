import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/ai/adjustment_state_controller.dart';
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart';

/// Clears the Lumina conversation AND any adjustment session (+110 E2
/// row 108). Both surfaces' "Clear conversation" buttons call this; the
/// session used to outlive the thread it belonged to.
void clearLuminaConversation(WidgetRef ref) {
  ref.read(luminaSheetProvider.notifier).clearSession();
  ref.read(adjustmentStateProvider.notifier).clear();
}

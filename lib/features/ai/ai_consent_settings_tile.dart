import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/ai/ai_consent.dart';
import 'package:nexgen_command/features/ai/ai_consent_host.dart';
import 'package:nexgen_command/features/ai/ai_consent_sheet.dart';
import 'package:nexgen_command/theme.dart';

const String kAiConsentSettingsTitle = 'Use Lumina AI';
const String kAiConsentSettingsSubtitle = 'Sends your requests to Anthropic';
const String kAiConsentSettingsWhatsSent = "What's sent";

/// Settings → Lumina AI. Off revokes at once. On shows the consent sheet;
/// the switch alone is never consent.
class AiConsentSettingsTile extends ConsumerStatefulWidget {
  const AiConsentSettingsTile({super.key});

  @override
  ConsumerState<AiConsentSettingsTile> createState() =>
      _AiConsentSettingsTileState();
}

class _AiConsentSettingsTileState extends ConsumerState<AiConsentSettingsTile> {
  bool _busy = false;

  Future<void> _onChanged(bool on) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    if (on) {
      await promptForAiConsent(ref, context: context);
    } else {
      final saved = await revokeAiConsent(ref);
      if (!saved) {
        messenger.showSnackBar(
            const SnackBar(content: Text(kAiConsentRevokeNotSaved)));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    // The account's stored grant, minus a switch-off on this phone: a revoke
    // whose save failed still shows Off. The tile sets that flag itself and
    // rebuilds after, so there is no ordering race with the gate's sync.
    final on = ref.watch(aiConsentGrantedProvider) &&
        !AiConsentGate.revokedOnThisPhone;
    final body = Theme.of(context).textTheme.bodySmall;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile(
          secondary: Icon(Icons.auto_awesome, color: NexGenPalette.cyan),
          title: const Text(kAiConsentSettingsTitle),
          subtitle: const Text(kAiConsentSettingsSubtitle),
          value: on,
          onChanged: _busy ? null : _onChanged,
        ),
        ExpansionTile(
          title: const Text(kAiConsentSettingsWhatsSent),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in kAiConsentSentItems)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('•  $item', style: body),
              ),
            const SizedBox(height: 4),
            Text(kAiConsentNotSent, style: body),
          ],
        ),
      ],
    );
  }
}

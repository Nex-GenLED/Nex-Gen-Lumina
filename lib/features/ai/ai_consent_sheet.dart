import 'package:flutter/material.dart';
import 'package:nexgen_command/theme.dart';
import 'package:url_launcher/url_launcher.dart';

// The Lumina AI consent sheet: the text approved in the store window (item 5,
// city-and-state variant). Change it only with an approved edit, and bump
// kAiConsentVersion (ai_consent.dart) when what is sent or the provider
// changes.
//
// No statement about the provider's own retention or training belongs here.
// That lives in the privacy policy, verified against the provider's current
// terms.

const String kAiConsentTitle = 'Lumina AI uses Anthropic';

const String kAiConsentIntro =
    'To answer your requests, Lumina AI sends them to Anthropic, the company '
    "that makes the Claude AI model. Nex-Gen doesn't sell this information or "
    'use it for advertising.';

const String kAiConsentSentHeading = 'Each time you ask Lumina AI, we send:';

const List<String> kAiConsentSentItems = [
  'What you type, or the words you say. Your voice recording stays on your '
      'phone; only the text is sent.',
  'The current date, time and your time zone.',
  'Your general location (city and state) from your profile.',
  "Interests and dislikes you've saved in your profile.",
  'A description of your lights: how many there are, your roofline section '
      'names and where they are, and which effects your controller supports.',
  'When it helps: your current design, today\'s sunrise and sunset times, and '
      'the name of a favorite or scene you mention.',
  'For business accounts: your business name, brand colors, and the event '
      'you describe.',
];

const String kAiConsentNotSent =
    "We don't send your name, email, phone number, account ID, exact location, "
    "or your controllers' network addresses.";

const String kAiConsentKept =
    "Nex-Gen doesn't keep your requests or Lumina's replies. We keep only a "
    'record of when you used Lumina AI and how much it processed, and it\'s '
    'deleted if you delete your account.';

const String kAiConsentTurnOff =
    'You can turn Lumina AI off at any time in Settings → Lumina AI.';

const String kAiConsentAllow = 'Allow Lumina AI';
const String kAiConsentNotNow = 'Not now';
const String kAiConsentPrivacyLink = 'Privacy Policy';
const String kPrivacyPolicyUrl = 'https://nex-genled.com/privacy-policy';

/// Shows the sheet. True = Allow, false = Not now, null = dismissed. Writing
/// the decision is the caller's job, so a failed write can fail closed.
Future<bool?> showAiConsentSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: NexGenPalette.gunmetal90,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => const AiConsentSheet(),
  );
}

class AiConsentSheet extends StatelessWidget {
  const AiConsentSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(kAiConsentTitle, style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              _bolded(kAiConsentIntro, 'Anthropic', body),
              const SizedBox(height: 16),
              Text(kAiConsentSentHeading,
                  style: body?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final item in kAiConsentSentItems)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('•  $item', style: body),
                ),
              const SizedBox(height: 10),
              _bolded(kAiConsentNotSent, "We don't send", body),
              const SizedBox(height: 10),
              Text(kAiConsentKept, style: body),
              const SizedBox(height: 10),
              _bolded(kAiConsentTurnOff, 'Settings → Lumina AI', body),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => launchUrl(Uri.parse(kPrivacyPolicyUrl),
                      mode: LaunchMode.externalApplication),
                  child: const Text(kAiConsentPrivacyLink),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text(kAiConsentAllow),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text(kAiConsentNotNow),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [text] with the first occurrence of [bold] in bold, as the approved
/// sheet shows it.
Widget _bolded(String text, String bold, TextStyle? style) {
  final i = text.indexOf(bold);
  if (i < 0) return Text(text, style: style);
  return Text.rich(
    TextSpan(style: style, children: [
      TextSpan(text: text.substring(0, i)),
      TextSpan(
          text: bold, style: const TextStyle(fontWeight: FontWeight.w700)),
      TextSpan(text: text.substring(i + bold.length)),
    ]),
  );
}

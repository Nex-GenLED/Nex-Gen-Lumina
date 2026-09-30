import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/auth/account_session.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:url_launcher/url_launcher.dart';

/// Who a signed-in but unlinked customer should get in touch with.
class SupportContact {
  const SupportContact({
    required this.name,
    required this.isDealer,
    this.phone,
    this.email,
    this.website,
  });

  final String name;

  /// True when this is the account's own dealer (from `dealer_code`).
  final bool isDealer;
  final String? phone;
  final String? email;
  final String? website;

  bool get canCall => (phone ?? '').trim().isNotEmpty;
  bool get canEmail => (email ?? '').trim().isNotEmpty;

  /// A `tel:` URI of digits and a leading `+` only, so "(816) 555-0100"
  /// reaches the dialler as a number.
  Uri? get telUri {
    if (!canCall) return null;
    final digits = phone!.replaceAll(RegExp(r'[^0-9+]'), '');
    return digits.isEmpty ? null : Uri(scheme: 'tel', path: digits);
  }

  Uri? get mailtoUri =>
      canEmail ? Uri(scheme: 'mailto', path: email!.trim()) : null;

  Uri? get webUri =>
      (website ?? '').trim().isEmpty ? null : Uri.https(website!.trim(), '');
}

/// Nex-Gen LED itself, for an account with no dealer.
///
/// The phone number is deliberately unset. Nothing in the repo or the live
/// data carries a confirmed corporate number (the old dialog's
/// "1-800-NEXGEN-LED" was a 13-digit placeholder). Until the owner confirms
/// one, the card offers email and the website; set [SupportContact.phone]
/// here and the Call button appears.
const kNexGenCorporateContact = SupportContact(
  name: 'Nex-Gen LED',
  isDealer: false,
  email: 'info@Nex-GenLED.com',
  website: 'Nex-GenLED.com',
);

const _kLookupTimeout = Duration(seconds: 8);

/// The contact for the signed-in account: its dealer when the profile carries
/// a `dealer_code`, `/dealers/{code}` can be read, and that record has a phone
/// or email; otherwise Nex-Gen LED. Never throws; every failure falls back.
///
/// Under the deployed rules a customer cannot read `/dealers`, so in
/// production this resolves to corporate today. The read is in place for when
/// that rule, or a server path, admits it.
final supportContactProvider =
    FutureProvider.autoDispose<SupportContact>((ref) async {
  String? code;
  try {
    final profile = await ref
        .watch(currentUserProfileProvider.future)
        .timeout(_kLookupTimeout);
    code = profile?.dealerCode?.trim();
  } catch (_) {
    return kNexGenCorporateContact;
  }
  if (code == null || code.isEmpty) return kNexGenCorporateContact;
  try {
    final doc = await ref
        .read(accountFirestoreProvider)
        .collection('dealers')
        .doc(code)
        .get()
        .timeout(_kLookupTimeout);
    return dealerContactFrom(doc.data()) ?? kNexGenCorporateContact;
  } catch (_) {
    return kNexGenCorporateContact;
  }
});

/// A dealer record's contact, or null when it has neither phone nor email.
SupportContact? dealerContactFrom(Map<String, dynamic>? data) {
  if (data == null) return null;
  String? field(String key) {
    final v = data[key];
    return v is String && v.trim().isNotEmpty ? v.trim() : null;
  }

  final phone = field('phone');
  final email = field('email');
  if (phone == null && email == null) return null;
  return SupportContact(
    name: field('companyName') ??
        field('businessName') ??
        field('name') ??
        'Your Nex-Gen dealer',
    isDealer: true,
    phone: phone,
    email: email,
  );
}

/// Opens [uri] outside the app. Tests override it to capture the URI.
final externalLinkOpenerProvider = Provider<Future<bool> Function(Uri uri)>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:url_launcher/url_launcher.dart';

// ── Nex-Gen LED corporate contact: the single source in the app ────────────
//
// Owner-confirmed 2026-09-29. The email forwards to the owner's inbox. Every
// screen that shows or mails corporate uses these; there is no other
// spelling in lib/.

const String kNexGenCorporatePhone = '816-408-0177';
const String kNexGenCorporateEmail = 'general@nex-genled.com';
const String kNexGenCorporateWebsite = 'Nex-GenLED.com';

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

  /// True when this is the account's own dealer, from the profile's
  /// `dealer_name` / `dealer_phone` / `dealer_email`.
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

/// Nex-Gen LED itself, for an account whose profile carries no dealer contact.
const kNexGenCorporateContact = SupportContact(
  name: 'Nex-Gen LED',
  isDealer: false,
  phone: kNexGenCorporatePhone,
  email: kNexGenCorporateEmail,
  website: kNexGenCorporateWebsite,
);

/// The dealer's contact from the profile, or null when the profile carries
/// neither a dealer phone nor a dealer email. Pure; no store read.
SupportContact? dealerContactFromProfile(UserModel? profile) {
  if (profile == null) return null;
  final phone = profile.dealerPhone?.trim();
  final email = profile.dealerEmail?.trim();
  if ((phone ?? '').isEmpty && (email ?? '').isEmpty) return null;
  final name = profile.dealerName?.trim();
  return SupportContact(
    name: (name ?? '').isEmpty ? 'Your Nex-Gen dealer' : name!,
    isDealer: true,
    phone: (phone ?? '').isEmpty ? null : phone,
    email: (email ?? '').isEmpty ? null : email,
  );
}

const _kProfileTimeout = Duration(seconds: 8);

/// The contact for the signed-in account: its dealer when the profile carries
/// the denormalised dealer contact, otherwise Nex-Gen LED. Never throws.
///
/// Customers cannot read `/dealers` (firestore.rules), so nothing here reads
/// it: the installer wizard, `createCustomerAccount` and
/// `claimCustomerByEmail` copy the dealer's name, phone and email onto the
/// profile at provisioning. Profiles provisioned before +110 have none of
/// this and see the corporate card.
final supportContactProvider =
    FutureProvider.autoDispose<SupportContact>((ref) async {
  try {
    final profile = await ref
        .watch(currentUserProfileProvider.future)
        .timeout(_kProfileTimeout);
    return dealerContactFromProfile(profile) ?? kNexGenCorporateContact;
  } catch (_) {
    return kNexGenCorporateContact;
  }
});

/// Opens [uri] outside the app. Tests override it to capture the URI.
final externalLinkOpenerProvider = Provider<Future<bool> Function(Uri uri)>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

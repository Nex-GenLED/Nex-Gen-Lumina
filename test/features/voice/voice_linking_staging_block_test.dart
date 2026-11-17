// Owner decision D3 (2026-11-17): Alexa / Google Home linking is hidden in
// staging. The skill and the action are the PRODUCTION ones and their account
// linking runs on production Cloud Functions, so linking from a staging build
// would link a production account.
//
// Today no linking card renders anywhere (removed under FACTS T-VA1). This
// test keeps it that way for staging if the cards come back: the services
// refuse before touching Firebase or a URL, and any file that uses either
// service must also reference kVoiceAssistantLinkingEnabled.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/config/lumina_env.dart';
import 'package:nexgen_command/features/voice/alexa_service.dart';
import 'package:nexgen_command/features/voice/google_home_service.dart';

/// Any member access throws, so a blocked call that returns normally proves
/// it never touched Firestore or Auth.
class _UntouchableFirestore extends Fake implements FirebaseFirestore {}

class _UntouchableAuth extends Fake implements FirebaseAuth {}

AlexaService _alexa({required bool allowsLinking}) => AlexaService(
    firestore: _UntouchableFirestore(),
    auth: _UntouchableAuth(),
    allowsLinking: allowsLinking);

GoogleHomeService _google({required bool allowsLinking}) => GoogleHomeService(
    firestore: _UntouchableFirestore(),
    auth: _UntouchableAuth(),
    allowsLinking: allowsLinking);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a production build (this binary) still allows linking', () {
    expect(kVoiceAssistantLinkingEnabled, isTrue);
    expect(
        AlexaService(firestore: _UntouchableFirestore(), auth: _UntouchableAuth())
            .allowsLinking,
        isTrue);
    expect(
        GoogleHomeService(
                firestore: _UntouchableFirestore(), auth: _UntouchableAuth())
            .allowsLinking,
        isTrue);
  });

  group('staging: link-outs refuse before Firebase or a URL', () {
    test('Alexa account linking', () async {
      expect(await _alexa(allowsLinking: false).initiateAccountLinking(),
          isFalse);
    });

    test('Alexa device discovery', () async {
      await expectLater(
          _alexa(allowsLinking: false).discoverDevices(), completes);
    });

    test('Google Home account linking', () async {
      expect(await _google(allowsLinking: false).initiateAccountLinking(),
          isFalse);
    });

    test('Google Home device sync', () async {
      await expectLater(_google(allowsLinking: false).syncDevices(), completes);
    });
  });

  group('production: the block is the only difference', () {
    test('linking goes on to read the signed-in user', () async {
      // The untouchable auth throws on that read, which proves the call got
      // past the block into the unchanged code.
      await expectLater(_alexa(allowsLinking: true).initiateAccountLinking(),
          throwsA(isA<UnimplementedError>()));
      await expectLater(_google(allowsLinking: true).initiateAccountLinking(),
          throwsA(isA<UnimplementedError>()));
    });
  });

  test('every file that uses either service also checks the switch', () {
    final uses = RegExp(r'\b(AlexaService|GoogleHomeService)\b');
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) {
          final src = f.readAsStringSync();
          return uses.hasMatch(src) &&
              !src.contains('kVoiceAssistantLinkingEnabled');
        })
        .map((f) => f.path.replaceAll('\\', '/'))
        .toList();
    expect(offenders, isEmpty,
        reason: 'A linking card must render only when '
            'kVoiceAssistantLinkingEnabled (false in staging).');
  });
}

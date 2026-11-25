import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexgen_command/features/sales/models/dealer_messaging_config.dart';
import 'package:nexgen_command/features/sales/screens/dealer_messaging_config_screen.dart';
import 'package:nexgen_command/features/sales/services/dealer_messaging_config_service.dart';

/// `sendStatusSms` — the dealer toggle for the three status-update SMS that
/// onSalesJobStatusChanged sends (prep day booked, install day booked,
/// wiring prep complete). The server reads `sendStatusSms` from
/// dealers/{code}/config/messaging and defaults it to true. The Flutter
/// model must carry the same name and default, or the Messaging tab can
/// neither show nor change it.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('model', () {
    test('defaults to on', () {
      expect(DealerMessagingConfig.defaults('01').sendStatusSms, isTrue);
      const cfg = DealerMessagingConfig(
        dealerCode: '01',
        senderName: 'Nex-Gen LED',
        replyPhone: '',
        supportEmail: '',
      );
      expect(cfg.sendStatusSms, isTrue);
    });

    test('a doc saved before the field existed reads as on', () {
      final cfg = DealerMessagingConfig.fromJson({
        'dealerCode': '01',
        'senderName': 'Acme Lights',
        'sendDay1Reminder': false,
      });
      expect(cfg.sendStatusSms, isTrue);
      expect(cfg.sendDay1Reminder, isFalse);
    });

    test('round-trips under the server field name', () {
      final off = DealerMessagingConfig.defaults('01')
          .copyWith(sendStatusSms: false);
      final json = off.toJson();
      expect(json['sendStatusSms'], isFalse);
      expect(DealerMessagingConfig.fromJson(json).sendStatusSms, isFalse);
      expect(off.copyWith().sendStatusSms, isFalse,
          reason: 'copyWith without the arg keeps it');
    });
  });

  group('service', () {
    test('saves and reads back sendStatusSms', () async {
      final db = FakeFirebaseFirestore();
      final service = DealerMessagingConfigService(db);
      await service.saveConfig(
        DealerMessagingConfig.defaults('01').copyWith(sendStatusSms: false),
      );
      final raw =
          await db.doc('dealers/01/config/messaging').get();
      expect(raw.data()!['sendStatusSms'], isFalse);
      final watched = await service.watchConfig('01').first;
      expect(watched.sendStatusSms, isFalse);
    });
  });

  group('editor', () {
    Future<FakeFirebaseFirestore> pumpEditor(WidgetTester tester) async {
      final db = FakeFirebaseFirestore();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dealerMessagingConfigServiceProvider
                .overrideWithValue(DealerMessagingConfigService(db)),
          ],
          child: const MaterialApp(
            home: Scaffold(body: DealerMessagingConfigScreen(dealerCode: '01')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return db;
    }

    SwitchListTile statusToggle(WidgetTester tester) => tester.widget(
          find.ancestor(
            of: find.text('Status Update SMS'),
            matching: find.byType(SwitchListTile),
          ),
        );

    testWidgets('shows the toggle, on by default', (tester) async {
      await pumpEditor(tester);
      expect(find.text('Status Update SMS'), findsOneWidget);
      expect(statusToggle(tester).value, isTrue);
    });

    testWidgets('turning it off and saving writes sendStatusSms: false',
        (tester) async {
      final db = await pumpEditor(tester);

      await tester.ensureVisible(find.text('Status Update SMS'));
      await tester.tap(find.text('Status Update SMS'));
      await tester.pumpAndSettle();
      expect(statusToggle(tester).value, isFalse);

      await tester.tap(find.text('Save messaging settings'));
      await tester.pumpAndSettle();

      final saved = await db.doc('dealers/01/config/messaging').get();
      expect(saved.data()!['sendStatusSms'], isFalse);
      // The other toggles are untouched.
      expect(saved.data()!['sendDay1Reminder'], isTrue);
    });
  });
}

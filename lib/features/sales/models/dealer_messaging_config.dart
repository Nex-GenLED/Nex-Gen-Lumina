import 'package:cloud_firestore/cloud_firestore.dart';

/// Per-dealer customization of the customer messaging pipeline.
///
/// Lives at Firestore path `dealers/{dealerCode}/config/messaging` —
/// one document per dealer, mirroring the existing
/// `dealers/{dealerCode}/pricing/current` shape used by
/// [DealerPricing].
///
/// Read by:
///   • The Cloud Functions side ([loadDealerMessagingConfig] in
///     functions/src/messaging-helpers.ts) before any outbound message
///     to apply toggles + the SMS sign-off
///   • The dealer dashboard's Messaging tab so dealers can edit it
///
/// Toggle behavior: when a `send*` flag is `false`, the corresponding
/// Cloud Function logs the skip and returns without calling Twilio /
/// Resend. The Firestore trigger itself never errors — toggles are a
/// soft mute, not a hard wire cut.
class DealerMessagingConfig {
  /// 2-digit dealer code matching the parent doc.
  final String dealerCode;

  /// Display name shown as the SMS sign-off when no [customSmsSignOff]
  /// is set, and as the dealer attribution in emails. Default
  /// "Nex-Gen LED".
  final String senderName;

  /// US phone number customers can reply to or call. Shown in emails;
  /// not used for the Twilio FROM number (which is the dealer-shared
  /// `TWILIO_FROM_NUMBER` env var).
  final String replyPhone;

  /// Support email address shown in customer-facing emails.
  final String supportEmail;

  /// Default opt-in state for new prospects' SMS preferences. Stored
  /// for the salesperson wizard to read when creating a new prospect.
  /// Defaults to true so dealers don't have to flip a setting before
  /// their first job.
  final bool smsOptInDefault;

  /// If true, the day-before Day 1 reminder SMS goes out via
  /// [sendInstallReminders]. Defaults to true.
  final bool sendDay1Reminder;

  /// If true, the day-before Day 2 reminder SMS goes out via
  /// [sendInstallReminders]. Defaults to true.
  final bool sendDay2Reminder;

  /// If true, the booking confirmation email goes out via
  /// [onSalesJobStatusChanged] when the customer signs the estimate.
  /// Defaults to true.
  final bool sendEstimateSignedEmail;

  /// If true, the install completion email (with download links) goes
  /// out via [onSalesJobStatusChanged] when the job hits
  /// `installComplete` status. Defaults to true.
  final bool sendInstallCompleteEmail;

  /// Optional override for the SMS sign-off. When non-null/non-empty,
  /// replaces "— Nex-Gen LED" (and the dealer's [senderName]) at the
  /// end of every SMS this dealer sends. Capped at 30 characters by
  /// the config screen — there is no server-side enforcement of the
  /// limit beyond what the screen does.
  final String? customSmsSignOff;

  final DateTime? updatedAt;

  const DealerMessagingConfig({
    required this.dealerCode,
    required this.senderName,
    required this.replyPhone,
    required this.supportEmail,
    this.smsOptInDefault = true,
    this.sendDay1Reminder = true,
    this.sendDay2Reminder = true,
    this.sendEstimateSignedEmail = true,
    this.sendInstallCompleteEmail = true,
    this.customSmsSignOff,
    this.updatedAt,
  });

  /// Sensible fallback used by [DealerMessagingConfigService.watchConfig]
  /// when no `dealers/{dealerCode}/config/messaging` document exists
  /// yet. Lets the screen always render something, and lets the Cloud
  /// Functions still send messages on freshly-provisioned dealers
  /// before they've touched the config screen.
  factory DealerMessagingConfig.defaults(String dealerCode) =>
      DealerMessagingConfig(
        dealerCode: dealerCode,
        senderName: 'Nex-Gen LED',
        replyPhone: '',
        supportEmail: '',
        smsOptInDefault: true,
        sendDay1Reminder: true,
        sendDay2Reminder: true,
        sendEstimateSignedEmail: true,
        sendInstallCompleteEmail: true,
        customSmsSignOff: null,
        updatedAt: null,
      );

  Map<String, dynamic> toJson() => {
        'dealerCode': dealerCode,
        'senderName': senderName,
        'replyPhone': replyPhone,
        'supportEmail': supportEmail,
        'smsOptInDefault': smsOptInDefault,
        'sendDay1Reminder': sendDay1Reminder,
        'sendDay2Reminder': sendDay2Reminder,
        'sendEstimateSignedEmail': sendEstimateSignedEmail,
        'sendInstallCompleteEmail': sendInstallCompleteEmail,
        if (customSmsSignOff != null) 'customSmsSignOff': customSmsSignOff,
        if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
      };

  factory DealerMessagingConfig.fromJson(Map<String, dynamic> j) =>
      DealerMessagingConfig(
        dealerCode: j['dealerCode'] as String? ?? '',
        senderName: j['senderName'] as String? ?? 'Nex-Gen LED',
        replyPhone: j['replyPhone'] as String? ?? '',
        supportEmail: j['supportEmail'] as String? ?? '',
        smsOptInDefault: j['smsOptInDefault'] as bool? ?? true,
        sendDay1Reminder: j['sendDay1Reminder'] as bool? ?? true,
        sendDay2Reminder: j['sendDay2Reminder'] as bool? ?? true,
        sendEstimateSignedEmail:
            j['sendEstimateSignedEmail'] as bool? ?? true,
        sendInstallCompleteEmail:
            j['sendInstallCompleteEmail'] as bool? ?? true,
        customSmsSignOff: j['customSmsSignOff'] as String?,
        updatedAt: (j['updatedAt'] as Timestamp?)?.toDate(),
      );

  DealerMessagingConfig copyWith({
    String? dealerCode,
    String? senderName,
    String? replyPhone,
    String? supportEmail,
    bool? smsOptInDefault,
    bool? sendDay1Reminder,
    bool? sendDay2Reminder,
    bool? sendEstimateSignedEmail,
    bool? sendInstallCompleteEmail,
    String? customSmsSignOff,
    bool clearCustomSmsSignOff = false,
    DateTime? updatedAt,
  }) =>
      DealerMessagingConfig(
        dealerCode: dealerCode ?? this.dealerCode,
        senderName: senderName ?? this.senderName,
        replyPhone: replyPhone ?? this.replyPhone,
        supportEmail: supportEmail ?? this.supportEmail,
        smsOptInDefault: smsOptInDefault ?? this.smsOptInDefault,
        sendDay1Reminder: sendDay1Reminder ?? this.sendDay1Reminder,
        sendDay2Reminder: sendDay2Reminder ?? this.sendDay2Reminder,
        sendEstimateSignedEmail:
            sendEstimateSignedEmail ?? this.sendEstimateSignedEmail,
        sendInstallCompleteEmail:
            sendInstallCompleteEmail ?? this.sendInstallCompleteEmail,
        customSmsSignOff: clearCustomSmsSignOff
            ? null
            : (customSmsSignOff ?? this.customSmsSignOff),
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// The string the SMS sender should sign off with — `customSmsSignOff`
  /// when set and non-empty, otherwise `senderName`. Both screens and
  /// (in TS form) the Cloud Functions implement the same fallback.
  String get effectiveSmsSignOff =>
      (customSmsSignOff != null && customSmsSignOff!.trim().isNotEmpty)
          ? customSmsSignOff!.trim()
          : senderName;
}

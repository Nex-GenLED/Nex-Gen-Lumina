import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../neighborhood_providers.dart';

// ═════════════════════════════════════════════════════════════════════════════
// NOTIFICATION PREFERENCE MODEL
// ═════════════════════════════════════════════════════════════════════════════

/// Per-user granular notification preferences for sync events.
class SyncNotificationPreferences {
  final bool enabled;
  final bool sessionStart;
  final bool scoreCelebrations;
  final bool sessionEnd;

  const SyncNotificationPreferences({
    this.enabled = true,
    this.sessionStart = true,
    this.scoreCelebrations = false, // Off by default — lights are the notification
    this.sessionEnd = true,
  });

  factory SyncNotificationPreferences.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const SyncNotificationPreferences();
    return SyncNotificationPreferences(
      enabled: map['enabled'] ?? true,
      sessionStart: map['sessionStart'] ?? true,
      scoreCelebrations: map['scoreCelebrations'] ?? false,
      sessionEnd: map['sessionEnd'] ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'sessionStart': sessionStart,
        'scoreCelebrations': scoreCelebrations,
        'sessionEnd': sessionEnd,
      };

  SyncNotificationPreferences copyWith({
    bool? enabled,
    bool? sessionStart,
    bool? scoreCelebrations,
    bool? sessionEnd,
  }) {
    return SyncNotificationPreferences(
      enabled: enabled ?? this.enabled,
      sessionStart: sessionStart ?? this.sessionStart,
      scoreCelebrations: scoreCelebrations ?? this.scoreCelebrations,
      sessionEnd: sessionEnd ?? this.sessionEnd,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// NOTIFICATION EVENT TYPES
// ═════════════════════════════════════════════════════════════════════════════

enum SyncNotificationType {
  sessionStarted,
  scoreCelebration,
  sessionEnding,
  sessionEnded,
  joinBanner,
  groupDissolved,

  /// A shortForm group has taken over — longForm is paused.
  handoffPaused,

  /// ShortForm session ended — longForm is resuming.
  handoffResumed,

  /// Game is in overtime — longForm resume is delayed.
  handoffOvertimeDelay,

  /// Victory celebration before handing back to longForm.
  handoffVictory,
}

// ═════════════════════════════════════════════════════════════════════════════
// SYNC NOTIFICATION SERVICE
// ═════════════════════════════════════════════════════════════════════════════

/// Handles FCM token management, sending push notifications via Cloud Function,
/// and foreground notification display for Neighborhood Sync events.
class SyncNotificationService {
  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;
  final FlutterLocalNotificationsPlugin _localNotifications;

  StreamSubscription? _tokenRefreshSub;
  StreamSubscription? _foregroundMessageSub;
  bool _initialized = false;

  /// Android notification channel for sync events.
  static const _kChannelId = 'neighborhood_sync';
  static const _kChannelName = 'Neighborhood Sync';
  static const _kChannelDesc = 'Notifications for neighborhood sync events';

  /// Notification IDs (avoid collision with other channels).
  static const _kSessionStartId = 7001;
  static const _kScoreCelebrationId = 7002;
  static const _kSessionEndingId = 7003;
  static const _kSessionEndedId = 7004;
  static const _kJoinBannerId = 7005;
  static const _kGroupDissolvedId = 7006;
  static const _kHandoffPausedId = 7007;
  static const _kHandoffResumedId = 7008;
  static const _kHandoffOvertimeId = 7009;
  static const _kHandoffVictoryId = 7010;

  SyncNotificationService({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    FlutterLocalNotificationsPlugin? localNotifications,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _functions = functions ?? FirebaseFunctions.instance,
        _localNotifications =
            localNotifications ?? FlutterLocalNotificationsPlugin();

  String? get _uid => _auth.currentUser?.uid;

  // ── Initialization ─────────────────────────────────────────────────

  /// Initialize FCM: request permission, get token, listen for refresh.
  /// Called once from main.dart after Firebase.initializeApp().
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Request permission (iOS will show the system prompt once)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('[SyncNotification] Permission denied');
      return;
    }

    debugPrint(
      '[SyncNotification] Permission: ${settings.authorizationStatus}',
    );

    // Get and store the FCM token
    await _refreshAndStoreToken();

    // Listen for token refresh
    _tokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) {
      _storeToken(newToken);
    });

    // Foreground message handler
    _foregroundMessageSub =
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Background message tap handler (app brought to foreground)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);

    debugPrint('[SyncNotification] Initialized');
  }

  // ── Token Management ───────────────────────────────────────────────

  /// Get the current FCM token and store it in Firestore.
  Future<void> _refreshAndStoreToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await _storeToken(token);
      }
    } catch (e) {
      debugPrint('[SyncNotification] Token retrieval failed: $e');
    }
  }

  /// Store the FCM token in the user's document under their member profile
  /// within each neighborhood group they belong to.
  Future<void> _storeToken(String token) async {
    final uid = _uid;
    if (uid == null) return;

    debugPrint('[SyncNotification] Storing token for $uid');

    // Store in user's top-level document for easy access
    await _firestore.collection('users').doc(uid).set(
      {'fcmToken': token, 'fcmTokenUpdatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );

    // Also update in all neighborhood groups this user belongs to
    final groups = await _firestore
        .collection('neighborhoods')
        .where('memberUids', arrayContains: uid)
        .get();

    final batch = _firestore.batch();
    for (final groupDoc in groups.docs) {
      final memberRef = groupDoc.reference
          .collection('members')
          .doc(uid);
      batch.set(
        memberRef,
        {'fcmToken': token},
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  /// Store the token specifically for a group (called when joining a group).
  Future<void> storeTokenForGroup(String groupId) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final token = await _messaging.getToken();
      if (token == null) return;
      await _firestore
          .collection('neighborhoods')
          .doc(groupId)
          .collection('members')
          .doc(uid)
          .set({'fcmToken': token}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[SyncNotification] storeTokenForGroup failed: $e');
    }
  }

  // ── Send Notifications (via Cloud Function) ────────────────────────

  /// Send a push notification to multiple participants via Cloud Function.
  ///
  /// The Cloud Function looks up FCM tokens from Firestore and sends
  /// via FCM HTTP v1 API. Tokens are never sent client-to-client.
  Future<void> notifyParticipants({
    required String groupId,
    required List<String> participantUids,
    required String title,
    required String body,
    required SyncNotificationType type,
    Map<String, String>? data,
  }) async {
    if (participantUids.isEmpty) return;

    try {
      final callable = _functions.httpsCallable('sendSyncNotification');
      await callable.call<dynamic>({
        'groupId': groupId,
        'participantUids': participantUids,
        'title': title,
        'body': body,
        'type': type.name,
        'data': data ?? {},
      });
      debugPrint(
        '[SyncNotification] Sent ${type.name} to ${participantUids.length} participants',
      );
    } catch (e) {
      debugPrint('[SyncNotification] Cloud Function call failed: $e');
      // Fall back to local notification for the current user
      if (participantUids.contains(_uid)) {
        await _showLocalNotification(title, body, type);
      }
    }
  }

  /// Convenience methods for specific notification types.

  Future<void> notifySessionStarted({
    required String groupId,
    required List<String> participantUids,
    required String eventName,
    required String hostName,
  }) async {
    await notifyParticipants(
      groupId: groupId,
      participantUids: participantUids,
      title: 'Neighborhood Sync',
      body: '$hostName just kicked off $eventName sync — your lights are joining!',
      type: SyncNotificationType.sessionStarted,
      data: {'eventName': eventName, 'groupId': groupId},
    );
  }

  Future<void> notifyScoreCelebration({
    required String groupId,
    required List<String> participantUids,
    required String teamName,
  }) async {
    await notifyParticipants(
      groupId: groupId,
      participantUids: participantUids,
      title: '$teamName Scored!',
      body: 'Your lights are celebrating with the neighborhood',
      type: SyncNotificationType.scoreCelebration,
    );
  }

  Future<void> notifySessionEnding({
    required String groupId,
    required List<String> participantUids,
    required String eventName,
  }) async {
    await notifyParticipants(
      groupId: groupId,
      participantUids: participantUids,
      title: 'Sync Ending',
      body: '$eventName sync is wrapping up',
      type: SyncNotificationType.sessionEnding,
    );
  }

  Future<void> notifySessionEnded({
    required String groupId,
    required List<String> participantUids,
    required String eventName,
  }) async {
    await notifyParticipants(
      groupId: groupId,
      participantUids: participantUids,
      title: 'Sync Ended',
      body: '$eventName sync ended — your lights are back on your schedule.',
      type: SyncNotificationType.sessionEnded,
    );
  }

  Future<void> notifyJoinBanner({
    required String groupId,
    required List<String> participantUids,
    required String eventName,
  }) async {
    await notifyParticipants(
      groupId: groupId,
      participantUids: participantUids,
      title: 'Sync Active',
      body: '$eventName sync started — tap to join',
      type: SyncNotificationType.joinBanner,
      data: {'eventName': eventName, 'groupId': groupId, 'action': 'join'},
    );
  }

  Future<void> notifyGroupDissolved({
    required String groupId,
    required List<String> participantUids,
    required String hostName,
  }) async {
    await notifyParticipants(
      groupId: groupId,
      participantUids: participantUids,
      title: 'Neighborhood Sync',
      body: '$hostName has left and the group has been dissolved. '
          'Create or join a new group to sync again.',
      type: SyncNotificationType.groupDissolved,
    );
  }

  // ── Handoff Notifications ───────────────────────────────────────────

  Future<void> notifyHandoffPaused({
    required String groupId,
    required List<String> participantUids,
    required String shortFormEventName,
    required String longFormGroupName,
  }) async {
    await notifyParticipants(
      groupId: groupId,
      participantUids: participantUids,
      title: '$shortFormEventName is live! 🏈',
      body:
          'Your $longFormGroupName lights will resume after the game.',
      type: SyncNotificationType.handoffPaused,
    );
  }

  Future<void> notifyHandoffResumed({
    required String groupId,
    required List<String> participantUids,
    required String longFormGroupName,
  }) async {
    await notifyParticipants(
      groupId: groupId,
      participantUids: participantUids,
      title: 'Welcome back!',
      body: 'Your $longFormGroupName lights are back! 🎄',
      type: SyncNotificationType.handoffResumed,
    );
  }

  Future<void> notifyHandoffOvertime({
    required String groupId,
    required List<String> participantUids,
    required String longFormGroupName,
  }) async {
    await notifyParticipants(
      groupId: groupId,
      participantUids: participantUids,
      title: 'Overtime!',
      body: "Game's in overtime — $longFormGroupName lights standing by 🎄",
      type: SyncNotificationType.handoffOvertimeDelay,
    );
  }

  Future<void> notifyHandoffVictory({
    required String groupId,
    required List<String> participantUids,
    required String teamName,
    required String longFormGroupName,
  }) async {
    await notifyParticipants(
      groupId: groupId,
      participantUids: participantUids,
      title: '$teamName wins! 🏆',
      body: 'Celebrating before handing back to $longFormGroupName...',
      type: SyncNotificationType.handoffVictory,
    );
  }

  // ── Foreground Notification Handling ────────────────────────────────

  /// Handle messages received while app is in the foreground.
  /// Suppress OS banner and show an in-app local notification instead.
  /// Also handles silent push messages for failover.
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint(
      '[SyncNotification] Foreground message: ${message.notification?.title}',
    );

    // ── Silent push: failover trigger ──────────────────────────────
    final type = message.data['type'];
    if (type == 'syncFailover') {
      _handleFailoverPush(message.data);
      return;
    }

    final notification = message.notification;
    if (notification == null) return;

    if (type == null) return;

    final syncType = SyncNotificationType.values.firstWhere(
      (t) => t.name == type,
      orElse: () => SyncNotificationType.sessionStarted,
    );

    // Show as local notification (suppresses the FCM OS banner)
    _showLocalNotification(
      notification.title ?? 'Neighborhood Sync',
      notification.body ?? '',
      syncType,
    );
  }

  /// Handle notification tap when app comes to foreground from background.
  void _handleMessageTap(RemoteMessage message) {
    debugPrint(
      '[SyncNotification] Message tap: ${message.data}',
    );

    // Handle failover push that arrived while app was in background
    final type = message.data['type'];
    if (type == 'syncFailover') {
      _handleFailoverPush(message.data);
      return;
    }

    final action = message.data['action'];
    if (action == 'join') {
      // Deep-link: user tapped "tap to join" — handled by the UI layer
      debugPrint('[SyncNotification] Join action from notification tap');
    }
  }

  /// Handle a failover silent push — this device should initiate the session.
  void _handleFailoverPush(Map<String, dynamic> data) {
    final groupId = data['groupId'] as String?;
    final eventId = data['eventId'] as String?;
    final gameId = data['gameId'] as String?;

    if (groupId == null || eventId == null) return;

    debugPrint(
      '[SyncNotification] Failover push received — initiating session '
      'for event $eventId in group $groupId',
    );

    // Signal the background service to initiate the session
    _onFailoverReceived?.call(groupId, eventId, gameId);
  }

  /// Callback for failover push — set by the background service or UI layer.
  static void Function(String groupId, String eventId, String? gameId)?
      _onFailoverReceived;

  /// Register a callback to handle failover pushes.
  static void setFailoverHandler(
    void Function(String groupId, String eventId, String? gameId) handler,
  ) {
    _onFailoverReceived = handler;
  }

  /// Show a local notification for foreground display.
  Future<void> _showLocalNotification(
    String title,
    String body,
    SyncNotificationType type,
  ) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        _kChannelId,
        _kChannelName,
        channelDescription: _kChannelDesc,
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(''),
      );
      const iosDetails = DarwinNotificationDetails();
      const details =
          NotificationDetails(android: androidDetails, iOS: iosDetails);

      final id = _notificationIdForType(type);
      await _localNotifications.show(id, title, body, details);
    } catch (e) {
      debugPrint('[SyncNotification] Local notification failed: $e');
    }
  }

  int _notificationIdForType(SyncNotificationType type) {
    switch (type) {
      case SyncNotificationType.sessionStarted:
        return _kSessionStartId;
      case SyncNotificationType.scoreCelebration:
        return _kScoreCelebrationId;
      case SyncNotificationType.sessionEnding:
        return _kSessionEndingId;
      case SyncNotificationType.sessionEnded:
        return _kSessionEndedId;
      case SyncNotificationType.joinBanner:
        return _kJoinBannerId;
      case SyncNotificationType.groupDissolved:
        return _kGroupDissolvedId;
      case SyncNotificationType.handoffPaused:
        return _kHandoffPausedId;
      case SyncNotificationType.handoffResumed:
        return _kHandoffResumedId;
      case SyncNotificationType.handoffOvertimeDelay:
        return _kHandoffOvertimeId;
      case SyncNotificationType.handoffVictory:
        return _kHandoffVictoryId;
    }
  }

  // ── Notification Preferences ───────────────────────────────────────

  /// Get the current user's notification preferences.
  Future<SyncNotificationPreferences> getPreferences(String groupId) async {
    final uid = _uid;
    if (uid == null) return const SyncNotificationPreferences();

    final doc = await _firestore
        .collection('neighborhoods')
        .doc(groupId)
        .collection('members')
        .doc(uid)
        .collection('settings')
        .doc('notificationPrefs')
        .get();

    if (!doc.exists) return const SyncNotificationPreferences();
    return SyncNotificationPreferences.fromMap(doc.data());
  }

  /// Save notification preferences.
  Future<void> savePreferences(
    String groupId,
    SyncNotificationPreferences prefs,
  ) async {
    final uid = _uid;
    if (uid == null) return;

    await _firestore
        .collection('neighborhoods')
        .doc(groupId)
        .collection('members')
        .doc(uid)
        .collection('settings')
        .doc('notificationPrefs')
        .set(prefs.toMap());
  }

  /// Stream notification preferences.
  Stream<SyncNotificationPreferences> watchPreferences(String groupId) {
    final uid = _uid;
    if (uid == null) {
      return Stream.value(const SyncNotificationPreferences());
    }
    return _firestore
        .collection('neighborhoods')
        .doc(groupId)
        .collection('members')
        .doc(uid)
        .collection('settings')
        .doc('notificationPrefs')
        .snapshots()
        .map((doc) {
      if (!doc.exists) return const SyncNotificationPreferences();
      return SyncNotificationPreferences.fromMap(doc.data());
    });
  }

  /// Check if the current user wants to receive a specific notification type.
  Future<bool> shouldSendNotification(
    String groupId,
    SyncNotificationType type,
  ) async {
    final prefs = await getPreferences(groupId);
    if (!prefs.enabled) return false;
    switch (type) {
      case SyncNotificationType.sessionStarted:
        return prefs.sessionStart;
      case SyncNotificationType.scoreCelebration:
        return prefs.scoreCelebrations;
      case SyncNotificationType.sessionEnding:
      case SyncNotificationType.sessionEnded:
        return prefs.sessionEnd;
      case SyncNotificationType.joinBanner:
        return prefs.sessionStart; // Same category as session start
      case SyncNotificationType.groupDissolved:
        return true; // Always send dissolution notifications
      case SyncNotificationType.handoffPaused:
      case SyncNotificationType.handoffResumed:
      case SyncNotificationType.handoffVictory:
        return prefs.sessionStart;
      case SyncNotificationType.handoffOvertimeDelay:
        return prefs.sessionEnd;
    }
  }

  /// Filter participant UIDs to only those who want this notification type.
  /// This runs on the host device before calling the Cloud Function.
  Future<List<String>> filterByPreferences(
    String groupId,
    List<String> uids,
    SyncNotificationType type,
  ) async {
    final eligible = <String>[];
    for (final uid in uids) {
      // Read each participant's preferences
      final doc = await _firestore
          .collection('neighborhoods')
          .doc(groupId)
          .collection('members')
          .doc(uid)
          .collection('settings')
          .doc('notificationPrefs')
          .get();

      final prefs = SyncNotificationPreferences.fromMap(
        doc.exists ? doc.data() : null,
      );

      if (!prefs.enabled) continue;

      switch (type) {
        case SyncNotificationType.sessionStarted:
        case SyncNotificationType.joinBanner:
          if (prefs.sessionStart) eligible.add(uid);
          break;
        case SyncNotificationType.scoreCelebration:
          if (prefs.scoreCelebrations) eligible.add(uid);
          break;
        case SyncNotificationType.sessionEnding:
        case SyncNotificationType.sessionEnded:
          if (prefs.sessionEnd) eligible.add(uid);
          break;
        case SyncNotificationType.groupDissolved:
          eligible.add(uid); // Always notify about dissolution
          break;
        // Handoff notifications follow session start/end preferences
        case SyncNotificationType.handoffPaused:
        case SyncNotificationType.handoffResumed:
        case SyncNotificationType.handoffVictory:
          if (prefs.sessionStart) eligible.add(uid);
          break;
        case SyncNotificationType.handoffOvertimeDelay:
          if (prefs.sessionEnd) eligible.add(uid);
          break;
      }
    }
    return eligible;
  }

  // ── Cleanup ────────────────────────────────────────────────────────

  void dispose() {
    _tokenRefreshSub?.cancel();
    _foregroundMessageSub?.cancel();
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PROVIDERS
// ═════════════════════════════════════════════════════════════════════════════

final syncNotificationServiceProvider =
    Provider<SyncNotificationService>((ref) {
  final service = SyncNotificationService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Stream notification preferences for the active group.
final syncNotificationPrefsProvider =
    StreamProvider<SyncNotificationPreferences>((ref) {
  final groupId = ref.watch(activeNeighborhoodIdProvider);
  if (groupId == null) {
    return Stream.value(const SyncNotificationPreferences());
  }
  final service = ref.watch(syncNotificationServiceProvider);
  return service.watchPreferences(groupId);
});

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

  /// Host set Game Day Autopilot for the group.
  groupAutopilotSet,

  /// Group autopilot was cancelled (host opted out or disabled).
  groupAutopilotCancelled,
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
  StreamSubscription? _messageOpenedSub;
  StreamSubscription<User?>? _authSub;

  /// True once the FCM STREAM LISTENERS have been attached.
  ///
  /// Scope is deliberately narrow: it guards ONLY the attach-once block at the
  /// bottom of [initialize]. It does NOT gate the permission request or the
  /// token write, both of which re-run on every call so a second account
  /// signing in on the same device re-points the token at its uid. It is also
  /// NOT set on a permission denial — see the denied branch in [initialize].
  bool _initialized = false;

  /// Re-entrancy guard, so two near-simultaneous callers cannot both run the
  /// wiring. This is what `_initialized = true`-on-entry used to provide.
  bool _initializing = false;

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
  static const _kGroupAutopilotSetId = 7011;
  static const _kGroupAutopilotCancelledId = 7012;

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

  /// Start watching auth state. **This is what main.dart calls at startup.**
  ///
  /// It prompts for nothing and touches no network on its own — it only
  /// subscribes. [initialize] then runs the first time a user is actually
  /// present, and the token is (re-)stored on every sign-in.
  ///
  /// Two bugs are fixed by this indirection, and they are separate:
  ///
  /// 1. **Permission timing.** `initialize()` used to be called
  ///    unconditionally from `main()`, so `requestPermission` fired the
  ///    Android 13+ POST_NOTIFICATIONS dialog on the cold-launch frame,
  ///    before the login screen, with no in-app explanation. Now the prompt
  ///    cannot appear until someone is signed in.
  ///
  /// 2. **The FCM token was never stored for anyone who signed in after
  ///    launch.** `initialize()` set `_initialized = true` on ENTRY, and
  ///    `_storeToken` early-returns when `uid == null`. On a cold start with
  ///    no user, the token write was therefore skipped — and because the
  ///    method was idempotent-by-flag it never ran again for that session.
  ///    Only `onTokenRefresh` could ever have recovered it, which is rare.
  ///    Push (weekly brief, sync events) was silently dead for those users.
  ///
  /// `authStateChanges()` emits the CURRENT state immediately on subscribe,
  /// so an already-signed-in user at cold start is handled on the same tick.
  /// The two halves are called INDEPENDENTLY and each swallows its own
  /// failure, on purpose. The wiring half touches static
  /// `FirebaseMessaging.onMessage`/`onMessageOpenedApp` streams, which can
  /// throw when Play Services is wedged; the token half must still run when
  /// it does, because storing the token is what makes push work at all.
  /// NOT THE PRODUCTION DRIVER — see [onSignedIn].
  ///
  /// `main()` deliberately does not call this any more. Driving FCM from a
  /// service-owned auth subscription meant `main()` had to construct a
  /// `SyncNotificationService()` of its own, and that instance was an ORPHAN:
  /// never the object `syncNotificationServiceProvider` builds, so its stream
  /// subscriptions could never be cancelled by that provider's `ref.onDispose`.
  /// The production driver is now an `authStateProvider` listener in
  /// `_MyAppState.build()`, which calls [onSignedIn] on the PROVIDER instance.
  ///
  /// DO NOT re-add a call to this from `main()` or from a widget: combined with
  /// that listener it would double-drive every sign-in.
  ///
  /// Retained because it is the entry point the late-sign-in regression suite
  /// drives (`test/features/neighborhood/
  /// sync_notification_token_on_late_signin_test.dart`) — a plain Stream seam
  /// needs no ProviderContainer, so those tests exercise [onSignedIn], the real
  /// shared core, against fakes. Unlike the production listener it does NOT
  /// filter anonymous sessions; that guard lives at the call site.
  void startAuthWatch() {
    _authSub ??= _auth.authStateChanges().listen((user) {
      if (user == null) return;
      onSignedIn();
    });
  }

  /// Bootstrap FCM for a user who has just become present.
  ///
  /// Called once per sign-in from the `authStateProvider` listener in
  /// `_MyAppState.build()`, on the provider instance. Safe to call repeatedly.
  ///
  /// THE CALLER excludes `null` and ANONYMOUS users. Anonymous sessions are the
  /// staff-PIN bootstrap, not a real user: they have no neighborhood membership
  /// to notify, and prompting them would put the notification dialog in front
  /// of an installer mid-commissioning.
  ///
  /// The two halves are called INDEPENDENTLY and each swallows its own failure,
  /// on purpose. The wiring half touches static
  /// `FirebaseMessaging.onMessage`/`onMessageOpenedApp` streams, which can
  /// throw when Play Services is wedged; the token half must still run when it
  /// does, because storing the token is what makes push work at all. It also
  /// covers the permission-denied case, where [initialize] returns early: a
  /// denied LOCAL-display permission is not a reason to leave the server
  /// without a token.
  void onSignedIn() {
    // Wiring half: permission + token re-run on every call; only the stream
    // listeners are attach-once.
    initialize().catchError((Object e) {
      debugPrint('[SyncNotification] initialize() failed: $e');
    });
    // Token half: runs on EVERY sign-in, so a second account on the same
    // device also gets its token written.
    _refreshAndStoreToken();
  }

  /// Initialize FCM: request permission, get token, attach stream listeners.
  ///
  /// Safe to call at any time and from anywhere; normally reached via
  /// [onSignedIn]. Returns without doing anything — and WITHOUT burning the
  /// idempotency flag — when no user is signed in.
  ///
  /// RE-ENTRANT BY DESIGN. Only the STREAM LISTENERS are attach-once; the
  /// permission request and the token write re-run on every call. That is what
  /// re-points the token at a second account signing in on the same device.
  Future<void> initialize() async {
    if (_initializing) return;

    // No user means there is nothing to attach a token to. Do not prompt, and
    // do not mark initialization as done: the authStateProvider listener in
    // _MyAppState.build() will call back the moment a user appears.
    if (_uid == null) {
      debugPrint('[SyncNotification] initialize() deferred — no signed-in user');
      return;
    }

    _initializing = true;
    try {
      // Request permission. On Android 13+ this is the POST_NOTIFICATIONS
      // dialog. On iOS this is now the ONLY code that can ever raise the
      // notification prompt: NotificationsService.init() used to raise it from
      // a bare DarwinInitializationSettings() before runApp(), and that was
      // turned off explicitly (see the comment there).
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        // DELIBERATELY DOES NOT LATCH.
        //
        // The previous code set _initialized = true BEFORE this check, so that
        // a denial would not re-prompt on every auth change. That reasoning no
        // longer holds and the behaviour was actively harmful: now that the
        // iOS Darwin prompt is off, this call is the sole grant path on iOS, so
        // latching here made "declined once, later enabled in OS Settings"
        // permanently broken for the rest of the process — the token would
        // never be stored and push would stay silently dead.
        //
        // Re-prompting is not a risk: once the OS has an answer, both platforms
        // return the stored answer without showing a dialog again.
        debugPrint('[SyncNotification] Permission denied');
        return;
      }

      debugPrint(
        '[SyncNotification] Permission: ${settings.authorizationStatus}',
      );

      // Get and store the FCM token. Runs on EVERY call, including when the
      // listeners below are already attached — that is what re-stores the
      // token under a newly signed-in uid.
      await _refreshAndStoreToken();

      // ── Everything below is ATTACH-ONCE ──────────────────────────────
      if (_initialized) return;
      _initialized = true;

      // Listen for token refresh.
      //
      // _storeToken does a Firestore write and can throw (offline, rules). A
      // bare call left that as an unhandled async error, which
      // PlatformDispatcher.onError in main.dart turns into a debug_errors
      // document — noise in the app's only crash sink, generated by a
      // background refresh the user never triggered.
      _tokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) {
        unawaited(
          _storeToken(newToken).catchError((Object e) {
            debugPrint('[SyncNotification] Token refresh store failed: $e');
          }),
        );
      });

      // Foreground message handler
      _foregroundMessageSub =
          FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Background message tap handler (app brought to foreground)
      _messageOpenedSub =
          FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);

      debugPrint('[SyncNotification] Initialized');
    } finally {
      _initializing = false;
    }
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

  // ── Group Autopilot Notifications ────────────────────────────────────

  /// Notify opted-in members that the host set Game Day Autopilot for the group.
  Future<void> notifyGroupAutopilotSet({
    required String groupId,
    required List<String> participantUids,
    required String hostName,
    required String teamName,
  }) async {
    await notifyParticipants(
      groupId: groupId,
      participantUids: participantUids,
      title: 'Game Day Autopilot',
      body:
          "$hostName set Game Day Autopilot for $teamName — you're included. "
          'Tap to opt out.',
      type: SyncNotificationType.groupAutopilotSet,
      data: {'groupId': groupId, 'teamName': teamName},
    );
  }

  /// Notify all members that group autopilot was cancelled.
  Future<void> notifyGroupAutopilotCancelled({
    required String groupId,
    required List<String> participantUids,
    required String reason,
  }) async {
    await notifyParticipants(
      groupId: groupId,
      participantUids: participantUids,
      title: 'Group Autopilot Cancelled',
      body: reason,
      type: SyncNotificationType.groupAutopilotCancelled,
      data: {'groupId': groupId},
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
      case SyncNotificationType.groupAutopilotSet:
        return _kGroupAutopilotSetId;
      case SyncNotificationType.groupAutopilotCancelled:
        return _kGroupAutopilotCancelledId;
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
      case SyncNotificationType.groupAutopilotSet:
      case SyncNotificationType.groupAutopilotCancelled:
        return true; // Always send group autopilot notifications
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
        case SyncNotificationType.groupAutopilotSet:
        case SyncNotificationType.groupAutopilotCancelled:
          eligible.add(uid); // Always notify about group autopilot changes
          break;
      }
    }
    return eligible;
  }

  // ── Cleanup ────────────────────────────────────────────────────────

  void dispose() {
    _tokenRefreshSub?.cancel();
    _foregroundMessageSub?.cancel();
    _messageOpenedSub?.cancel();
    _authSub?.cancel();
    _authSub = null;
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

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_router.dart';

class NotificationsService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Global navigator key used for deep-link navigation from notification taps.
  /// Must be set to the same key used by GoRouter (called from main.dart).
  static GlobalKey<NavigatorState>? navigatorKey;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );

      // Handle FCM data messages (server-sent push notifications like weekly brief).
      // onMessageOpenedApp: user tapped the notification while app was in background.
      // getInitialMessage: app was terminated and opened via the notification.
      if (!kIsWeb) {
        FirebaseMessaging.onMessageOpenedApp.listen(_handleFcmTap);
        final initial = await FirebaseMessaging.instance.getInitialMessage();
        if (initial != null) {
          // Delay slightly so the navigator is mounted before pushing.
          Future.delayed(const Duration(milliseconds: 500), () {
            _handleFcmTap(initial);
          });
        }
      }

      _initialized = true;
    } catch (e) {
      debugPrint('Notifications init failed: $e');
    }
  }

  /// Handle taps on server-sent FCM push notifications.
  ///
  /// The weekly brief Cloud Function sends data: { type: "weeklyBrief",
  /// route: "/autopilot-schedule", date: "2026-04-06" }.
  static void _handleFcmTap(RemoteMessage message) {
    try {
      final data = message.data;
      final type = data['type'] as String?;

      debugPrint('FCM notification tapped: type=$type data=$data');

      if (type == 'weekly_brief' || type == 'weeklyBrief') {
        final dateStr = data['date'] as String?;
        final route = data['route'] as String?;
        final date = dateStr != null ? DateTime.tryParse(dateStr) : null;
        final context = navigatorKey?.currentContext;
        if (context != null) {
          context.push(
            route ?? AppRoutes.autopilotSchedule,
            extra: date,
          );
        }
        return;
      }

      // Fallback: if a route is provided, navigate to it directly.
      final route = data['route'] as String?;
      if (route != null) {
        final context = navigatorKey?.currentContext;
        if (context != null) {
          context.push(route);
        }
      }
    } catch (e) {
      debugPrint('FCM tap handler failed: $e');
    }
  }

  /// Handle notification tap responses (deep links).
  static void _onNotificationResponse(NotificationResponse response) {
    try {
      final payload = response.payload;
      if (payload == null || payload.isEmpty) return;

      debugPrint('Notification tapped with payload: $payload');

      // Autopilot weekly brief payload is an ISO date string (e.g. "2026-03-16")
      final date = DateTime.tryParse(payload);
      if (date != null) {
        // Navigate to autopilot schedule with that date pre-selected
        final context = navigatorKey?.currentContext;
        if (context != null) {
          context.push(AppRoutes.autopilotSchedule, extra: date);
        }
        return;
      }

      // Commercial notification deep-links (prefixed with "commercial:")
      if (payload.startsWith('commercial:')) {
        final route = payload.substring('commercial:'.length);
        final context = navigatorKey?.currentContext;
        if (context != null) {
          context.push(route);
        }
        return;
      }
    } catch (e) {
      debugPrint('Notification response handler failed: $e');
    }
  }

  static Future<void> showWelcomeHome(String patternName) async {
    try {
      const android = AndroidNotificationDetails(
        'welcome_home',
        'Welcome Home',
        channelDescription: 'Geofence arrival notifications',
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(''),
      );
      const iOS = DarwinNotificationDetails();
      const details = NotificationDetails(android: android, iOS: iOS);
      await _plugin.show(1001, 'Welcome Home!', 'Lights set to $patternName.', details);
    } catch (e) {
      debugPrint('Show notification failed: $e');
    }
  }

  /// Show a smart suggestion notification
  static Future<void> showSuggestion(String title, String description) async {
    try {
      const android = AndroidNotificationDetails(
        'suggestions',
        'Smart Suggestions',
        channelDescription: 'Lumina AI suggestions and recommendations',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        styleInformation: BigTextStyleInformation(''),
      );
      const iOS = DarwinNotificationDetails();
      const details = NotificationDetails(android: android, iOS: iOS);
      await _plugin.show(2001, title, description, details);
    } catch (e) {
      debugPrint('Show suggestion notification failed: $e');
    }
  }

  /// Show an event reminder notification
  static Future<void> showEventReminder(String eventName) async {
    try {
      const android = AndroidNotificationDetails(
        'events',
        'Event Reminders',
        channelDescription: 'Reminders for upcoming events and game days',
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(''),
      );
      const iOS = DarwinNotificationDetails();
      const details = NotificationDetails(android: android, iOS: iOS);
      await _plugin.show(
        3001,
        '$eventName is Tomorrow!',
        'Your custom pattern is ready to use.',
        details,
      );
    } catch (e) {
      debugPrint('Show event reminder failed: $e');
    }
  }

  /// Show a habit detection notification
  static Future<void> showHabitDetected(String habitDescription) async {
    try {
      const android = AndroidNotificationDetails(
        'habits',
        'Habit Detection',
        channelDescription: 'Notifications about detected usage patterns',
        importance: Importance.low,
        priority: Priority.low,
        styleInformation: BigTextStyleInformation(''),
      );
      const iOS = DarwinNotificationDetails();
      const details = NotificationDetails(android: android, iOS: iOS);
      await _plugin.show(
        4001,
        'Lumina Noticed a Pattern',
        habitDescription,
        details,
      );
    } catch (e) {
      debugPrint('Show habit notification failed: $e');
    }
  }

  // ===========================================================================
  // COMMERCIAL NOTIFICATIONS
  // ===========================================================================
  //
  // Phase 3a (2026-05-06): all 5 deep-link payloads below route to
  // AppRoutes.dashboard (residential home), not AppRoutes.commercialHome.
  // Commercial customers no longer auto-route to the parallel /commercial
  // shell at sign-in (route_guards.dart commercial fork removed in the
  // same change), so notification taps must land them in the same place
  // sign-in does — residential home — to avoid inconsistent navigation.
  // Phase 4 will refine each payload to a specific residential-side
  // feature surface (alerts banner, events list, schedule conflict
  // panel, etc.) as those surfaces are built. See
  // docs/commercial_ux_audit.md and memory Item #37.

  static const _commercialChannel = AndroidNotificationDetails(
    'commercial',
    'Commercial Alerts',
    channelDescription: 'Alerts for commercial lighting management',
    importance: Importance.high,
    priority: Priority.high,
    styleInformation: BigTextStyleInformation(''),
  );
  static const _commercialDetails =
      NotificationDetails(android: _commercialChannel, iOS: DarwinNotificationDetails());

  /// CONTROLLER_OFFLINE — a controller at a location is not responding.
  static Future<void> showControllerOffline(String locationName) async {
    try {
      await _plugin.show(
        6001,
        'Controller Offline',
        'A controller at $locationName is not responding.',
        _commercialDetails,
        payload: 'commercial:${AppRoutes.dashboard}',
      );
    } catch (e) {
      debugPrint('Commercial notification failed: $e');
    }
  }

  /// HOLIDAY_CONFLICT — upcoming holiday that may affect schedule.
  static Future<void> showHolidayConflict(String date) async {
    try {
      await _plugin.show(
        6002,
        'Holiday Schedule Conflict',
        'Upcoming holiday on $date \u2014 confirm your schedule.',
        _commercialDetails,
        payload: 'commercial:${AppRoutes.dashboard}',
      );
    } catch (e) {
      debugPrint('Commercial notification failed: $e');
    }
  }

  /// GAME_DAY_ALERT — team game today, Game Day mode activating.
  static Future<void> showGameDayAlert(
      String teamName, String gameTime, String leadTime) async {
    try {
      await _plugin.show(
        6003,
        'Game Day Alert',
        '$teamName game today at $gameTime \u2014 Game Day mode activating at $leadTime.',
        _commercialDetails,
        payload: 'commercial:${AppRoutes.dashboard}',
      );
    } catch (e) {
      debugPrint('Commercial notification failed: $e');
    }
  }

  /// CORPORATE_PUSH_RECEIVED — org has updated your schedule.
  static Future<void> showCorporatePushReceived(String orgName) async {
    try {
      await _plugin.show(
        6004,
        'Schedule Updated',
        '$orgName has updated your schedule.',
        _commercialDetails,
        payload: 'commercial:${AppRoutes.dashboard}',
      );
    } catch (e) {
      debugPrint('Commercial notification failed: $e');
    }
  }

  /// LOCK_EXPIRING — corporate schedule lock expires in 24 hours.
  static Future<void> showLockExpiring(String locationName) async {
    try {
      await _plugin.show(
        6005,
        'Lock Expiring Soon',
        'Corporate schedule lock at $locationName expires in 24 hours.',
        _commercialDetails,
        payload: 'commercial:${AppRoutes.dashboard}',
      );
    } catch (e) {
      debugPrint('Commercial notification failed: $e');
    }
  }

  /// Show an autopilot weekly schedule preview notification.
  static Future<void> showWeeklyBrief(String title, String body, {String? weekDate}) async {
    try {
      const android = AndroidNotificationDetails(
        'autopilot_weekly',
        'Weekly Schedule Preview',
        channelDescription: 'Sunday evening summary of your upcoming lighting schedule',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        styleInformation: BigTextStyleInformation(''),
        sound: RawResourceAndroidNotificationSound('default'),
        playSound: true,
      );
      const iOS = DarwinNotificationDetails();
      const details = NotificationDetails(android: android, iOS: iOS);
      await _plugin.show(
        8001,
        title,
        body,
        details,
        payload: weekDate,
      );
    } catch (e) {
      debugPrint('Show weekly brief notification failed: $e');
    }
  }

  /// Show a favorites update notification
  static Future<void> showFavoritesUpdated(int count) async {
    try {
      const android = AndroidNotificationDetails(
        'favorites',
        'Favorites',
        channelDescription: 'Updates to your favorite patterns',
        importance: Importance.low,
        priority: Priority.low,
        styleInformation: BigTextStyleInformation(''),
      );
      const iOS = DarwinNotificationDetails();
      const details = NotificationDetails(android: android, iOS: iOS);
      await _plugin.show(
        5001,
        'Favorites Updated',
        'Your top $count patterns have been added to favorites.',
        details,
      );
    } catch (e) {
      debugPrint('Show favorites notification failed: $e');
    }
  }
}

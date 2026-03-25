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
      _initialized = true;
    } catch (e) {
      debugPrint('Notifications init failed: $e');
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
        payload: 'commercial:${AppRoutes.commercialHome}',
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
        payload: 'commercial:${AppRoutes.commercialHome}',
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
        payload: 'commercial:${AppRoutes.commercialHome}',
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
        payload: 'commercial:${AppRoutes.commercialHome}',
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
        payload: 'commercial:${AppRoutes.commercialHome}',
      );
    } catch (e) {
      debugPrint('Commercial notification failed: $e');
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

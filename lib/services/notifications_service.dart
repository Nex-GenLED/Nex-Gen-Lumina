import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationsService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
      await _plugin.initialize(initSettings);
      _initialized = true;
    } catch (e) {
      debugPrint('Notifications init failed: $e');
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

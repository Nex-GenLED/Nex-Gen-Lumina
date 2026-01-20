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
}

import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Register Siri Shortcuts plugin
    SiriShortcutsPlugin.register(with: self.registrar(forPlugin: "SiriShortcutsPlugin")!)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Handle Siri Shortcut user activity
  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    // Let the plugin handle the activity
    return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
  }
}

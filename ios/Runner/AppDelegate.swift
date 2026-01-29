import Flutter
import UIKit
import Intents

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Register Siri Shortcuts plugin
    if let controller = window?.rootViewController as? FlutterViewController {
      SiriShortcutsPlugin.register(with: self.registrar(forPlugin: "SiriShortcutsPlugin")!)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Handle Siri Shortcut / NSUserActivity continuation
  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    // Check if this is a Siri Shortcut activity
    let supportedTypes = [
      "com.nexgen.lumina.applyScene",
      "com.nexgen.lumina.powerOn",
      "com.nexgen.lumina.powerOff",
      "com.nexgen.lumina.setBrightness"
    ]

    if supportedTypes.contains(userActivity.activityType) {
      // Forward to the Siri plugin
      // The plugin will handle this via its application delegate method
      return true
    }

    // Let Flutter handle other activities
    return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
  }

  // Handle URL scheme (lumina://) for deep links from Siri
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    // Let Flutter handle the URL
    return super.application(app, open: url, options: options)
  }
}

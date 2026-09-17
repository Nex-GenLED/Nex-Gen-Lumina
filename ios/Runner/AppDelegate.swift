import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  // Google Maps SDK for iOS API key.
  //
  // S-2, Apple submission audit 2026-09-17. google_maps_flutter is a
  // dependency and FLTGoogleMapsPlugin is registered by
  // GeneratedPluginRegistrant, but GMSServices.provideAPIKey() was never
  // called. The iOS Maps SDK hard-requires it: without this call every
  // GoogleMap widget renders a blank grey tile. Android had the same gap (no
  // com.google.android.geo.API_KEY meta-data), so this was a both-platform
  // omission, not an iOS oversight.
  //
  // This is the same platform-appropriate Firebase client key the Dart side
  // already uses for Places (see features/schedule/geocoding_service.dart,
  // which reads DefaultFirebaseOptions.<platform>.apiKey). It matches
  // DefaultFirebaseOptions.ios.apiKey in lib/firebase_options.dart. Firebase
  // API keys are public client identifiers by design — this is not a secret,
  // and it already ships in the binary via firebase_options.dart.
  //
  // REQUIRES A CONSOLE-SIDE STEP THIS COMMIT CANNOT DO: "Maps SDK for iOS"
  // must be enabled on this key in Google Cloud Console, and the key should
  // carry an iOS-app restriction pinned to the bundle id. Until then the map
  // will still fail, just with an authorization error instead of silence.
  private static let googleMapsApiKey = "AIzaSyAiRUF0Hd2D5wIW1fyLsaO3WQTeJq35wFY"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Must run before any GMSMapView is constructed, i.e. before Flutter can
    // build a GoogleMap widget — hence here rather than lazily.
    GMSServices.provideAPIKey(AppDelegate.googleMapsApiKey)

    GeneratedPluginRegistrant.register(with: self)

    // Register Siri Shortcuts plugin
    if let registrar = self.registrar(forPlugin: "SiriShortcutsPlugin") {
      SiriShortcutsPlugin.register(with: registrar)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

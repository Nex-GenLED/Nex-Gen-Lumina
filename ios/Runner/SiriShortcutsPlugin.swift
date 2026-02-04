import Flutter
import UIKit
import Intents
import IntentsUI
import CoreSpotlight
import UniformTypeIdentifiers

/// Flutter plugin for Siri Shortcuts integration.
///
/// Handles:
/// - Donating user activities to Siri for suggestions
/// - Presenting the "Add to Siri" voice shortcut view controller
/// - Handling incoming Siri shortcut user activities
public class SiriShortcutsPlugin: NSObject, FlutterPlugin {

    private static var channel: FlutterMethodChannel?
    private weak var viewController: UIViewController?

    public static func register(with registrar: FlutterPluginRegistrar) {
        channel = FlutterMethodChannel(
            name: "com.nexgen.lumina/siri",
            binaryMessenger: registrar.messenger()
        )

        let instance = SiriShortcutsPlugin()

        // Get the root view controller
        if let window = UIApplication.shared.delegate?.window,
           let rootVC = window?.rootViewController {
            instance.viewController = rootVC
        }

        registrar.addMethodCallDelegate(instance, channel: channel!)
        registrar.addApplicationDelegate(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "donateShortcut":
            handleDonateShortcut(call: call, result: result)
        case "presentAddToSiri":
            handlePresentAddToSiri(call: call, result: result)
        case "isShortcutsAvailable":
            result(true) // Available on iOS 12+
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Donate Shortcut

    private func handleDonateShortcut(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let sceneId = args["sceneId"] as? String,
              let sceneName = args["sceneName"] as? String,
              let activityType = args["activityType"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing required arguments", details: nil))
            return
        }

        let suggestedPhrase = args["suggestedPhrase"] as? String ?? sceneName

        // Build userInfo with base fields
        var userInfo: [String: Any] = ["sceneId": sceneId, "sceneName": sceneName]

        // Merge any additional userInfo from Flutter (for color shortcuts, etc.)
        if let additionalInfo = args["userInfo"] as? [String: Any] {
            for (key, value) in additionalInfo {
                userInfo[key] = value
            }
        }

        // Create user activity
        let activity = NSUserActivity(activityType: activityType)
        activity.title = sceneName
        activity.userInfo = userInfo
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        activity.suggestedInvocationPhrase = suggestedPhrase
        activity.persistentIdentifier = sceneId

        // Add to Spotlight for search
        let attributes = CSSearchableItemAttributeSet(contentType: .item)
        attributes.title = sceneName
        attributes.contentDescription = "Activate \(sceneName) lighting"
        attributes.keywords = ["lights", "lighting", sceneName]
        activity.contentAttributeSet = attributes

        // Donate the activity
        activity.becomeCurrent()

        result(true)
    }

    // MARK: - Present Add to Siri

    private func handlePresentAddToSiri(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let sceneId = args["sceneId"] as? String,
              let sceneName = args["sceneName"] as? String,
              let activityType = args["activityType"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing required arguments", details: nil))
            return
        }

        let suggestedPhrase = args["suggestedPhrase"] as? String ?? "Set lights to \(sceneName)"

        // Create the shortcut
        let activity = NSUserActivity(activityType: activityType)
        activity.title = sceneName
        activity.userInfo = ["sceneId": sceneId, "sceneName": sceneName]
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        activity.suggestedInvocationPhrase = suggestedPhrase
        activity.persistentIdentifier = sceneId

        if #available(iOS 12.0, *) {
            let shortcut = INShortcut(userActivity: activity)
            let addVoiceShortcutVC = INUIAddVoiceShortcutViewController(shortcut: shortcut)
            addVoiceShortcutVC.delegate = self

            DispatchQueue.main.async { [weak self] in
                self?.viewController?.present(addVoiceShortcutVC, animated: true) {
                    result(true)
                }
            }
        } else {
            result(FlutterError(code: "UNSUPPORTED", message: "Siri Shortcuts require iOS 12+", details: nil))
        }
    }

    // MARK: - Handle Incoming User Activity

    public func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]) -> Void
    ) -> Bool {
        // Check if this is one of our activity types
        let supportedTypes = [
            "com.nexgen.lumina.applyScene",
            "com.nexgen.lumina.powerOn",
            "com.nexgen.lumina.powerOff",
            "com.nexgen.lumina.setBrightness",
            "com.nexgen.lumina.setColor"
        ]

        guard supportedTypes.contains(userActivity.activityType) else {
            return false
        }

        // Notify Flutter of the incoming activity
        var payload: [String: Any] = [
            "activityType": userActivity.activityType
        ]

        if let userInfo = userActivity.userInfo as? [String: Any] {
            payload["userInfo"] = userInfo
        }

        SiriShortcutsPlugin.channel?.invokeMethod("onShortcutActivated", arguments: payload)

        return true
    }
}

// MARK: - INUIAddVoiceShortcutViewControllerDelegate

@available(iOS 12.0, *)
extension SiriShortcutsPlugin: INUIAddVoiceShortcutViewControllerDelegate {

    public func addVoiceShortcutViewController(
        _ controller: INUIAddVoiceShortcutViewController,
        didFinishWith voiceShortcut: INVoiceShortcut?,
        error: Error?
    ) {
        controller.dismiss(animated: true) {
            if let error = error {
                SiriShortcutsPlugin.channel?.invokeMethod(
                    "onAddToSiriResult",
                    arguments: ["success": false, "error": error.localizedDescription]
                )
            } else if let shortcut = voiceShortcut {
                SiriShortcutsPlugin.channel?.invokeMethod(
                    "onAddToSiriResult",
                    arguments: [
                        "success": true,
                        "phrase": shortcut.invocationPhrase
                    ]
                )
            }
        }
    }

    public func addVoiceShortcutViewControllerDidCancel(
        _ controller: INUIAddVoiceShortcutViewController
    ) {
        controller.dismiss(animated: true) {
            SiriShortcutsPlugin.channel?.invokeMethod(
                "onAddToSiriResult",
                arguments: ["success": false, "cancelled": true]
            )
        }
    }
}

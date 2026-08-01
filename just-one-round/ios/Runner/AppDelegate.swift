import Flutter
import Security
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var environmentChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "AppEnvironmentPlugin"
    ) else {
      return
    }
    environmentChannel = FlutterMethodChannel(
      name: "just_one_round/app_environment",
      binaryMessenger: registrar.messenger()
    )
    environmentChannel?.setMethodCallHandler { call, result in
      switch call.method {
      case "isIosSimulator":
#if targetEnvironment(simulator)
        result(true)
#else
        result(false)
#endif
      case "getAppBuildInfo":
        let info = Bundle.main.infoDictionary
        result([
          "version": info?["CFBundleShortVersionString"] as? String ?? "1.0.0",
          "build_number": info?["CFBundleVersion"] as? String ?? "1",
          "platform": "ios",
        ])
      case "getDeviceInstallId":
        result(self.deviceInstallId())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func deviceInstallId() -> String {
    let service = "\(Bundle.main.bundleIdentifier ?? "just-one-round").device-install-id"
    let account = "primary"
    let lookup: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var item: CFTypeRef?
    if SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess,
       let data = item as? Data,
       let stored = String(data: data, encoding: .utf8) {
      return stored
    }

    let generated = UUID().uuidString.lowercased()
    let insert: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      kSecValueData as String: Data(generated.utf8),
    ]
    SecItemAdd(insert as CFDictionary, nil)
    return generated
  }
}

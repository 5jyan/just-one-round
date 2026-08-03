import Flutter
import AuthenticationServices
import Security
import UIKit

private final class KakaoBrowserLoginPlugin: NSObject,
  FlutterPlugin,
  ASWebAuthenticationPresentationContextProviding
{
  private var webAuthenticationSession: ASWebAuthenticationSession?
  private var pendingResult: FlutterResult?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = KakaoBrowserLoginPlugin()
    let channel = FlutterMethodChannel(
      name: "just_one_round/kakao_browser_login",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "authorize",
          let arguments = call.arguments as? [String: Any],
          let urlString = arguments["url"] as? String,
          let callbackScheme = arguments["callbackScheme"] as? String,
          let url = URL(string: urlString),
          !callbackScheme.isEmpty else {
      result(FlutterError(
        code: "INVALID_ARGUMENT",
        message: "Invalid Kakao browser login arguments.",
        details: nil
      ))
      return
    }

    guard pendingResult == nil else {
      result(FlutterError(
        code: "LOGIN_IN_PROGRESS",
        message: "A Kakao login is already in progress.",
        details: nil
      ))
      return
    }

    pendingResult = result
    let session = ASWebAuthenticationSession(
      url: url,
      callbackURLScheme: callbackScheme
    ) { [weak self] callbackURL, error in
      guard let self else { return }
      let completion = self.pendingResult
      self.pendingResult = nil
      self.webAuthenticationSession = nil

      if let callbackURL {
        completion?(callbackURL.absoluteString)
      } else if error is ASWebAuthenticationSessionError {
        completion?(FlutterError(
          code: "CANCELED",
          message: "Kakao browser login was canceled.",
          details: nil
        ))
      } else {
        completion?(FlutterError(
          code: "WEB_AUTH_ERROR",
          message: error?.localizedDescription ?? "Kakao browser login failed.",
          details: nil
        ))
      }
    }
    session.presentationContextProvider = self
    session.prefersEphemeralWebBrowserSession = false
    webAuthenticationSession = session

    guard session.start() else {
      webAuthenticationSession = nil
      pendingResult = nil
      result(FlutterError(
        code: "WEB_AUTH_START_ERROR",
        message: "Kakao browser login could not be started.",
        details: nil
      ))
      return
    }
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    for connectedScene in UIApplication.shared.connectedScenes {
      guard let windowScene = connectedScene as? UIWindowScene else { continue }
      if let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) {
        return keyWindow
      }
      if let firstWindow = windowScene.windows.first {
        return firstWindow
      }
    }
    return ASPresentationAnchor()
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var environmentChannel: FlutterMethodChannel?
  private var transientDeviceInstallId: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let kakaoBrowserRegistrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "KakaoBrowserLoginPlugin"
    ) {
      KakaoBrowserLoginPlugin.register(with: kakaoBrowserRegistrar)
    }

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
    if let transientDeviceInstallId {
      return transientDeviceInstallId
    }

    let service = "\(Bundle.main.bundleIdentifier ?? "just-one-round").device-install-id"
    let account = "primary"
    let lookup: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    func readStoredId() -> String? {
      var item: CFTypeRef?
      guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data else {
        return nil
      }
      return String(data: data, encoding: .utf8)
    }

    if let stored = readStoredId() {
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
    let status = SecItemAdd(insert as CFDictionary, nil)
    if status == errSecDuplicateItem, let stored = readStoredId() {
      return stored
    }

    if status != errSecSuccess {
      // Keep a stable value for this process if Keychain is temporarily unavailable.
      transientDeviceInstallId = generated
    }
    return generated
  }
}

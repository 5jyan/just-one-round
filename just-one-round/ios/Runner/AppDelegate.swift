import Flutter
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
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

package com.justoneround.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val environmentChannel = "just_one_round/app_environment"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            environmentChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isIosSimulator" -> result.success(false)
                "getAppBuildInfo" -> result.success(
                    mapOf(
                        "version" to BuildConfig.VERSION_NAME,
                        "build_number" to BuildConfig.VERSION_CODE.toString(),
                        "platform" to "android",
                    ),
                )
                else -> result.notImplemented()
            }
        }
    }
}

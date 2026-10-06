package com.justoneround.app

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val environmentChannel = "just_one_round/app_environment"
    private val notificationSettingsChannel = "just_one_round/notification_settings"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            environmentChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isIosSimulator" -> result.success(false)
                "getAppBuildInfo" -> {
                    val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        packageManager.getPackageInfo(
                            packageName,
                            PackageManager.PackageInfoFlags.of(0),
                        )
                    } else {
                        @Suppress("DEPRECATION")
                        packageManager.getPackageInfo(packageName, 0)
                    }
                    result.success(
                        mapOf(
                            "version" to (packageInfo.versionName ?: "1.0.0"),
                            "build_number" to packageInfo.longVersionCode.toString(),
                            "platform" to "android",
                        ),
                    )
                }
                "getDeviceInstallId" -> {
                    result.success(
                        Settings.Secure.getString(
                            contentResolver,
                            Settings.Secure.ANDROID_ID,
                        ),
                    )
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            notificationSettingsChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "open" -> {
                    val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        }
                    } else {
                        Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:$packageName"),
                        )
                    }
                    try {
                        startActivity(intent)
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}

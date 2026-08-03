import java.io.FileInputStream
import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val admobAppIdOverride = project.findProperty("ADMOB_APP_ID")?.toString()
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use(keystoreProperties::load)
}
val uploadKeystoreFile = file(
    System.getenv("ANDROID_UPLOAD_KEYSTORE") ?: "upload-keystore.jks",
)
val uploadStorePassword = System.getenv("ANDROID_UPLOAD_STORE_PASSWORD")
val uploadKeyAlias = System.getenv("ANDROID_UPLOAD_KEY_ALIAS") ?: "upload"
val dartDefines = project.findProperty("dart-defines")
    ?.toString()
    ?.split(",")
    ?.mapNotNull { encoded ->
        runCatching {
            String(Base64.getDecoder().decode(encoded), Charsets.UTF_8)
        }.getOrNull()
    }
    ?.mapNotNull { value ->
        val separator = value.indexOf('=')
        if (separator <= 0) null
        else value.substring(0, separator) to value.substring(separator + 1)
    }
    ?.toMap()
    ?: emptyMap()
val kakaoNativeAppKey = project.findProperty("KAKAO_NATIVE_APP_KEY")?.toString()
    ?: System.getenv("KAKAO_NATIVE_APP_KEY")
    ?: dartDefines["KAKAO_NATIVE_APP_KEY"]
    ?: "8f22d14ad0934753e6de50e73edaee82"
val kakaoCustomScheme = project.findProperty("KAKAO_CUSTOM_SCHEME")?.toString()
    ?: System.getenv("KAKAO_CUSTOM_SCHEME")
    ?: dartDefines["KAKAO_CUSTOM_SCHEME"]
    ?: kakaoNativeAppKey.takeIf { it.isNotBlank() }?.let { "kakao$it" }
    ?: "kakao8f22d14ad0934753e6de50e73edaee82"
val keyPropertiesStoreFile = keystoreProperties.getProperty("storeFile")
    ?.let { file(it) }
val keyPropertiesSigningConfigured = keystorePropertiesFile.exists() &&
    !keystoreProperties.getProperty("storePassword").isNullOrBlank() &&
    !keystoreProperties.getProperty("keyPassword").isNullOrBlank() &&
    !keystoreProperties.getProperty("keyAlias").isNullOrBlank() &&
    keyPropertiesStoreFile?.exists() == true
val environmentSigningConfigured = uploadKeystoreFile.exists() &&
    !uploadStorePassword.isNullOrBlank()
val releaseSigningConfigured =
    keyPropertiesSigningConfigured || environmentSigningConfigured

val verifyReleaseSigning = tasks.register("verifyReleaseSigning") {
    doLast {
        if (!releaseSigningConfigured) {
            throw GradleException(
                "Release signing is not configured. Provide android/key.properties " +
                    "or ANDROID_UPLOAD_STORE_PASSWORD with the upload keystore.",
            )
        }
    }
}

tasks.configureEach {
    if (name == "assembleRelease" || name == "bundleRelease") {
        dependsOn(verifyReleaseSigning)
    }
}

android {
    namespace = "com.justoneround.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.justoneround.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["ADMOB_APP_ID"] =
            admobAppIdOverride ?: "ca-app-pub-3940256099942544~3347511713"
        manifestPlaceholders["KAKAO_CUSTOM_SCHEME"] = kakaoCustomScheme
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        } else if (uploadKeystoreFile.exists() && !uploadStorePassword.isNullOrEmpty()) {
            create("release") {
                keyAlias = uploadKeyAlias
                keyPassword = uploadStorePassword
                storeFile = uploadKeystoreFile
                storePassword = uploadStorePassword
            }
        }
    }

    buildTypes {
        release {
            manifestPlaceholders["ADMOB_APP_ID"] =
                admobAppIdOverride ?: "ca-app-pub-8518567556283844~6404200741"
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Google Mobile Ads currently pulls in WorkManager 2.7.0, which crashes
    // during AndroidX Startup on modern release builds before Flutter starts.
    implementation("androidx.work:work-runtime:2.11.2")
}

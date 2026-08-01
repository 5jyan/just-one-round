import java.io.FileInputStream
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

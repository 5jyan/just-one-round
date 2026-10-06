import java.io.FileInputStream
import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Local/test builds remain usable without production Firebase credentials.
// Supplying google-services.json automatically enables native Firebase setup.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

val admobAppIdOverride = project.findProperty("ADMOB_APP_ID")?.toString()

fun nonBlankEnvironment(name: String): String? =
    System.getenv(name)?.takeIf(String::isNotBlank)

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val keyPropertiesLoaded = if (keystorePropertiesFile.isFile) {
    runCatching {
        FileInputStream(keystorePropertiesFile).use(keystoreProperties::load)
        true
    }.getOrDefault(false)
} else {
    false
}

val keyPropertiesStorePath = keystoreProperties.getProperty("storeFile")
    ?.takeIf(String::isNotBlank)
val keyPropertiesStoreFile = keyPropertiesStorePath?.let(::file)
val keyPropertiesStorePassword = keystoreProperties.getProperty("storePassword")
    ?.takeIf(String::isNotBlank)
val keyPropertiesKeyAlias = keystoreProperties.getProperty("keyAlias")
    ?.takeIf(String::isNotBlank)
val keyPropertiesKeyPassword = keystoreProperties.getProperty("keyPassword")
    ?.takeIf(String::isNotBlank)
val keyPropertiesSigningConfigured = keyPropertiesLoaded &&
    keyPropertiesStoreFile?.isFile == true &&
    keyPropertiesStorePassword != null &&
    keyPropertiesKeyAlias != null &&
    keyPropertiesKeyPassword != null

val androidUploadKeychainService = "just-one-round-android-upload-key-20260731"
val androidUploadKeychainAccount = "upload"

fun readMacKeychainSecret(service: String, account: String): String? {
    if (!System.getProperty("os.name").contains("Mac", ignoreCase = true)) {
        return null
    }
    return runCatching {
        val process = ProcessBuilder(
            "/usr/bin/security",
            "find-generic-password",
            "-s",
            service,
            "-a",
            account,
            "-w",
        ).redirectError(ProcessBuilder.Redirect.DISCARD).start()
        val value = process.inputStream.bufferedReader().use {
            it.readText().trimEnd('\r', '\n')
        }
        if (process.waitFor() == 0) value.takeIf(String::isNotBlank) else null
    }.getOrNull()
}

val defaultUploadKeystoreFile = rootProject.file("app/upload-keystore.jks")
val uploadKeystorePathOverride = nonBlankEnvironment("ANDROID_UPLOAD_KEYSTORE")
fun resolveUploadKeystore(path: String) = when {
    path.startsWith("/") -> file(path)
    path.startsWith("android/") -> rootProject.projectDir.parentFile.resolve(path)
    path.startsWith("app/") -> rootProject.file(path)
    else -> file(path)
}
val uploadKeystoreFile = uploadKeystorePathOverride?.let(::resolveUploadKeystore)
    ?: defaultUploadKeystoreFile
val uploadKeyAlias = nonBlankEnvironment("ANDROID_UPLOAD_KEY_ALIAS") ?: "upload"
val fallbackStorePassword = if (keyPropertiesSigningConfigured) {
    null
} else {
    nonBlankEnvironment("ANDROID_UPLOAD_STORE_PASSWORD")
        ?: readMacKeychainSecret(
            service = androidUploadKeychainService,
            account = androidUploadKeychainAccount,
        )
}
val fallbackKeyPassword = if (keyPropertiesSigningConfigured) {
    null
} else {
    nonBlankEnvironment("ANDROID_UPLOAD_KEY_PASSWORD") ?: fallbackStorePassword
}
val environmentSigningConfigured = uploadKeystoreFile.isFile &&
    !fallbackStorePassword.isNullOrBlank() &&
    !fallbackKeyPassword.isNullOrBlank()
val releaseSigningConfigured = keyPropertiesSigningConfigured || environmentSigningConfigured

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
val firebasePushEnabledForRelease =
    dartDefines["ENABLE_FIREBASE_PUSH"]?.toBoolean() ?: true
val verifyFirebasePush = tasks.register("verifyFirebasePush") {
    doLast {
        if (firebasePushEnabledForRelease && !file("google-services.json").exists()) {
            throw GradleException(
                "Firebase push is enabled for release, but android/app/google-services.json " +
                    "is missing. Run flutterfire configure or explicitly build with " +
                    "--dart-define=ENABLE_FIREBASE_PUSH=false.",
            )
        }
    }
}
val kakaoNativeAppKey = project.findProperty("KAKAO_NATIVE_APP_KEY")?.toString()
    ?: System.getenv("KAKAO_NATIVE_APP_KEY")
    ?: dartDefines["KAKAO_NATIVE_APP_KEY"]
    ?: "8f22d14ad0934753e6de50e73edaee82"
val kakaoCustomScheme = project.findProperty("KAKAO_CUSTOM_SCHEME")?.toString()
    ?: System.getenv("KAKAO_CUSTOM_SCHEME")
    ?: dartDefines["KAKAO_CUSTOM_SCHEME"]
    ?: kakaoNativeAppKey.takeIf { it.isNotBlank() }?.let { "kakao$it" }
    ?: "kakao8f22d14ad0934753e6de50e73edaee82"
val verifyReleaseSigning = tasks.register("verifyReleaseSigning") {
    doLast {
        if (!releaseSigningConfigured) {
            throw GradleException(
                """
                Release signing is not configured. android/key.properties is optional, but if it is present it must be complete: non-blank storeFile, storePassword, keyAlias, keyPassword, and an existing keystore. Fallbacks checked in order: (1) complete android/key.properties, (2) non-blank ANDROID_UPLOAD_STORE_PASSWORD with optional ANDROID_UPLOAD_KEY_PASSWORD, ANDROID_UPLOAD_KEYSTORE, and ANDROID_UPLOAD_KEY_ALIAS, (3) the macOS Keychain item service $androidUploadKeychainService / account $androidUploadKeychainAccount. The default fallback keystore is android/app/upload-keystore.jks and the default alias is upload. Safe checks from the repository root (do not print secrets): test -f android/key.properties; test -f android/app/upload-keystore.jks; test -n "${'$'}{ANDROID_UPLOAD_STORE_PASSWORD:-}"; security find-generic-password -s $androidUploadKeychainService -a $androidUploadKeychainAccount -w >/dev/null.
                """.trimIndent(),
            )
        }
    }
}

tasks.configureEach {
    if (name == "assembleRelease" || name == "bundleRelease") {
        dependsOn(verifyReleaseSigning)
        dependsOn(verifyFirebasePush)
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
        if (keyPropertiesSigningConfigured) {
            create("release") {
                keyAlias = keyPropertiesKeyAlias!!
                keyPassword = keyPropertiesKeyPassword!!
                storeFile = keyPropertiesStoreFile!!
                storePassword = keyPropertiesStorePassword!!
            }
        } else if (environmentSigningConfigured) {
            create("release") {
                keyAlias = uploadKeyAlias
                keyPassword = fallbackKeyPassword!!
                storeFile = uploadKeystoreFile
                storePassword = fallbackStorePassword!!
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

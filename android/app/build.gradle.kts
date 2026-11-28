import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes from android/key.properties locally, or from environment
// variables in CI. Both point at the same long-lived key so an APK can upgrade an
// already installed copy; a throwaway key produces INSTALL_FAILED_UPDATE_INCOMPATIBLE.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

fun signingValue(property: String, env: String): String? {
    val value = keystoreProperties.getProperty(property) ?: System.getenv(env)
    return value?.takeIf { it.isNotBlank() }
}

val releaseStoreFile = signingValue("storeFile", "KEYSTORE_PATH")
val releaseStorePassword = signingValue("storePassword", "KEYSTORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "KEYSTORE_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "KEYSTORE_KEY_PASSWORD")
val hasReleaseSigning =
    releaseStoreFile != null &&
        releaseStorePassword != null &&
        releaseKeyAlias != null &&
        releaseKeyPassword != null

// Sideload builds must declare REQUEST_INSTALL_PACKAGES so the updater can hand
// a downloaded APK to the system installer; Google Play rejects apps that ship
// it without that being core functionality. The manifest asks for a placeholder
// name instead of the permission itself, and only self-update builds (Gradle
// sees ENABLE_SELF_UPDATE=true as an environment variable or -P property)
// substitute the real permission. Everyone else gets an undefined no-op
// permission name, which Android ignores at install time.
val selfUpdateEnabled =
    listOf(
        project.findProperty("ENABLE_SELF_UPDATE"),
        System.getenv("ENABLE_SELF_UPDATE"),
    ).any { it == "true" }

android {
    namespace = "com.photospot.photospot"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.photospot.photospot"
        // Flutter's defaults: minSdk from the Flutter SDK, current target SDK.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Play-safe by default; real REQUEST_INSTALL_PACKAGES only for
        // self-update builds (see selfUpdateEnabled above).
        manifestPlaceholders["installPackagesPermission"] =
            if (selfUpdateEnabled) {
                "android.permission.REQUEST_INSTALL_PACKAGES"
            } else {
                "com.photospot.photospot.permission.NOTHING_INSTALL_PACKAGES"
            }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                // Local builds without a key still work; store uploads need the
                // real key, and CI logs a warning in that case.
                signingConfigs.getByName("debug")
            }
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

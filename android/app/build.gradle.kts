import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load key.properties for release signing with safe fallback
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
var hasValidKeystore = false

if (keystorePropertiesFile.exists()) {
    try {
        keystoreProperties.load(FileInputStream(keystorePropertiesFile))
        val storePassword = keystoreProperties["storePassword"] as? String
        val keyPassword = keystoreProperties["keyPassword"] as? String
        val keyAlias = keystoreProperties["keyAlias"] as? String
        val storeFileStr = keystoreProperties["storeFile"] as? String

        if (!storePassword.isNullOrBlank() && storePassword != "?" &&
            !keyPassword.isNullOrBlank() && keyPassword != "?" &&
            !keyAlias.isNullOrBlank() && !storeFileStr.isNullOrBlank()) {
            val sFile = file(storeFileStr)
            if (sFile.exists() && sFile.length() > 0) {
                hasValidKeystore = true
            }
        }
    } catch (e: Exception) {
        hasValidKeystore = false
    }
}

// Load version.properties for central app versioning
val versionPropertiesFile = rootProject.file("version.properties")
val versionProperties = Properties()
if (versionPropertiesFile.exists()) {
    versionProperties.load(FileInputStream(versionPropertiesFile))
}

android {
    namespace = "com.example.music_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.music_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = if (versionPropertiesFile.exists() && versionProperties.containsKey("VERSION_CODE")) {
            (versionProperties["VERSION_CODE"] as String).trim().toInt()
        } else {
            flutter.versionCode
        }
        versionName = if (versionPropertiesFile.exists() && versionProperties.containsKey("VERSION_NAME")) {
            (versionProperties["VERSION_NAME"] as String).trim()
        } else {
            flutter.versionName
        }
    }

    signingConfigs {
        if (hasValidKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasValidKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

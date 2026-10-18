import java.util.Properties
import java.io.FileInputStream
import java.security.KeyStore

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
val isCI = System.getenv("CI") == "true" || System.getenv("GITHUB_ACTIONS") == "true"

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
                // Verify password and alias using Java KeyStore API (supports PKCS12 and JKS)
                val ks = try {
                    KeyStore.getInstance("PKCS12").apply {
                        FileInputStream(sFile).use { fis -> load(fis, storePassword.toCharArray()) }
                    }
                } catch (e: Exception) {
                    KeyStore.getInstance(KeyStore.getDefaultType()).apply {
                        FileInputStream(sFile).use { fis -> load(fis, storePassword.toCharArray()) }
                    }
                }
                if (ks.containsAlias(keyAlias)) {
                    hasValidKeystore = true
                } else {
                    val msg = "AURA ERROR: Keystore alias '$keyAlias' not found in ${sFile.absolutePath}"
                    if (isCI) throw GradleException(msg) else println(msg)
                }
            } else {
                val msg = "AURA ERROR: Keystore file '$storeFileStr' does not exist or is empty (resolved: ${sFile.absolutePath})"
                if (isCI) throw GradleException(msg) else println(msg)
            }
        } else {
            val msg = "AURA ERROR: key.properties is missing required fields (storePassword, keyPassword, keyAlias, storeFile)"
            if (isCI) throw GradleException(msg) else println(msg)
        }
    } catch (e: Exception) {
        val msg = "AURA ERROR: Release keystore validation failed (${e.message})."
        if (isCI) {
            throw GradleException(msg, e)
        } else {
            println("$msg Falling back to debug signing.")
            hasValidKeystore = false
        }
    }
} else if (isCI) {
    throw GradleException("AURA ERROR: key.properties not found in CI build! Release APK cannot be signed.")
}

// Load version.properties for central app versioning (prioritizes root version.properties, with android/ fallback)
val versionPropertiesFile = run {
    val fInRoot = rootProject.file("../version.properties")
    if (fInRoot.exists()) fInRoot else rootProject.file("version.properties")
}
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
        minSdk = maxOf(flutter.minSdkVersion, 21)
        targetSdk = flutter.targetSdkVersion
        versionCode = if (versionPropertiesFile.exists() && versionProperties.containsKey("VERSION_CODE")) {
            (versionProperties["VERSION_CODE"] as String).trim().toInt()
        } else if (flutter.versionCode > 0) {
            flutter.versionCode
        } else {
            70
        }
        versionName = if (versionPropertiesFile.exists() && versionProperties.containsKey("VERSION_NAME")) {
            (versionProperties["VERSION_NAME"] as String).trim()
        } else if (!flutter.versionName.isNullOrBlank()) {
            flutter.versionName
        } else {
            "7.0"
        }
    }

    signingConfigs {
        if (hasValidKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            if (isCI && !hasValidKeystore) {
                throw GradleException("AURA ERROR: Release build type cannot use debug signing in CI.")
            }
            signingConfig = if (hasValidKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
        debug {
            // Unify debug signing with release key when keystore exists to prevent signature mismatch conflicts during updates
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

if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

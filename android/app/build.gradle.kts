plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.epcs.csai"
    compileSdk = flutter.compileSdkVersion

    // NDK 28 is the highest version required across all plugins (jni requires 28.2.13676358).
    // NDK versions are backward-compatible, so this satisfies flutter_litert_lm (27) too.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.epcs.csai"
        // minSdk 26 is required by LiteRT GPU (same as llama-cpp-dart CPU AAR).
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Signing with debug keys for now - replace with release keystore before publishing.
            signingConfig = signingConfigs.getByName("debug")

            // R8 keep rules - suppresses missing JP2Decoder from PdfBox
            // (JPEG2000 support is optional and not bundled on Android).
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    // llama-cpp-dart.aar is still needed for Qwen3 4B (GGUF path).
    // Download from https://github.com/netdur/llama_cpp_dart/releases
    // and place at android/app/libs/llama-cpp-dart.aar
    implementation(files("libs/llama-cpp-dart.aar"))

    // flutter_litert_lm brings its own native AAR via its own build.gradle.
    // No extra implementation() line needed here for LiteRT.
}

flutter {
    source = "../.."
}

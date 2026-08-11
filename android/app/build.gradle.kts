plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.gpt2_chat"
    compileSdk = flutter.compileSdkVersion

    // NDK 27 is required by the flutter_litert_lm native layer.
    // Previously flutter.ndkVersion (~25) was used for llama-cpp-dart.
    // Both llama_cpp_dart and flutter_litert_lm work with NDK 27.
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.gpt2_chat"
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

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.gpt2_chat"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.gpt2_chat"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // minSdk 26, required by the plain CPU-only llama-cpp-dart.aar.
        // (We briefly tried bumping this to 31 for the Hexagon AAR's GPU
        // path, but that AAR's OpenCL backend failed at runtime on real
        // hardware with "libOpenCL.so not found" — most Android phones
        // don't expose their GPU vendor's OpenCL driver to apps. Reverted
        // to the CPU AAR, so this drops back down too.)
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // llama_cpp_dart's native binary — download from
    // https://github.com/netdur/llama_cpp_dart/releases and place at
    // android/app/libs/llama-cpp-dart.aar (see README.md "Native library setup").
    implementation(files("libs/llama-cpp-dart.aar"))
}

flutter {
    source = "../.."
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "__PKG__"
    compileSdk = 35

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }

    defaultConfig {
        applicationId = "__PKG__"
        minSdk = 26          // Filament needs OpenGL ES 3.0; Stockfish plugin needs 21+
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk { abiFilters += listOf("arm64-v8a") }   // nearly all current phones; add "armeabi-v7a" / "x86_64" if you need them
    }

    buildTypes {
        release {
            // Sideload build: signed with the debug key. Replace with your own keystore for Google Play.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    packaging { jniLibs { pickFirsts += listOf("**/libc++_shared.so") } }
}

flutter { source = "../.." }

dependencies {
    // 3D renderer + glTF loader (native code, Apache-2.0)
    implementation("com.google.android.filament:filament-android:__FILAMENT__")
    implementation("com.google.android.filament:gltfio-android:__FILAMENT__")
    implementation("androidx.core:core-ktx:1.13.1")
}

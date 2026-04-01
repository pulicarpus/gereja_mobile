import java.io.File

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.puli.gkiimobile" 
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // KONFIGURASI KUNCI PERMANEN (KEYSTORE)
    signingConfigs {
        create("release") {
            // File ini akan dibuat otomatis oleh GitHub Actions di folder yang sama
            storeFile = file("gereja-app.jks")
            storePassword = "lovela150811"
            keyAlias = "gereja-key"
            keyPassword = "lovela150811"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        @Suppress("DEPRECATION")
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.puli.gkiimobile"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // Memastikan build debug juga pakai kunci yang sama agar SHA-1 konsisten
        signingConfig = signingConfigs.getByName("release")
    }

    buildTypes {
        release {
            // Menggunakan kunci permanen untuk rilis
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
        debug {
            // Sangat penting: Debug juga harus pakai kunci yang sama supaya Google Login jalan saat testing
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

// FORCED AAPT2 BYPASS UNTUK ARM64 (REDMI PAD)
tasks.withType<com.android.build.gradle.tasks.ProcessAndroidResources> {
    doFirst {
        val manualAapt2 = File("/usr/bin/aapt2")
        if (manualAapt2.exists()) {
            System.setProperty("android.aapt2FromMaven", "false")
            System.setProperty("android.aapt2.executable", manualAapt2.absolutePath)
            project.extensions.extraProperties.set("android.enableResourceOptimizations", false)
            println("--- INFO: MEMAKSA AAPT2 DARI ${manualAapt2.absolutePath} ---")
        }
    }
}
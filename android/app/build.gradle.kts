import java.io.File

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    // Sesuaikan dengan package name proyek Bos
    namespace = "com.gereja.app" 
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // Perbaikan jvmTarget agar tidak deprecated
    kotlinOptions {
        @Suppress("DEPRECATION")
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.gereja.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
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
            // Beritahu Gradle lokasi fisik AAPT2 yang sehat
            System.setProperty("android.aapt2FromMaven", "false")
            System.setProperty("android.aapt2.executable", manualAapt2.absolutePath)
            
            // Bypass optimasi resource yang sering memicu error daemon x86
            project.extensions.extraProperties.set("android.enableResourceOptimizations", false)
            
            println("--- INFO: MEMAKSA AAPT2 DARI ${manualAapt2.absolutePath} ---")
        }
    }
}
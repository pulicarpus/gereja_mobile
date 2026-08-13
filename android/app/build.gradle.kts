import java.io.File

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    // Namespace untuk Package Name baru
    namespace = "com.puli.gkiimobile" 
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        create("release") {
            // File jks harus ada di folder android/app/ agar tidak error
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
        // ID Aplikasi yang akan didaftarkan ke Firebase
        applicationId = "com.puli.gkiimobile"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        signingConfig = signingConfigs.getByName("release")
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
        debug {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Import the Firebase BoM
    implementation(platform("com.google.firebase:firebase-bom:33.0.0"))
    implementation("com.google.firebase:firebase-analytics")
}

// KHUSUS REDMI PAD (AAPT2 BYPASS) - JANGAN DIHAPUS
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
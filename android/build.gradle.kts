// android/build.gradle.kts (Level Proyek)

plugins {
    // KOSONGKAN SEMUA ANGKA VERSI DISINI BOS!
    id("com.android.application") apply false
    id("com.android.library") apply false
    id("org.jetbrains.kotlin.android") apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Pengaturan folder build agar tidak memenuhi memori internal tablet Bos
val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

// Buildscript tetap dipertahankan untuk kompatibilitas plugin lama
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // Ini adalah "jembatan" untuk membaca google-services.json Bos
        classpath("com.google.gms:google-services:4.4.1")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
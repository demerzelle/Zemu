plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

android {
    namespace = "com.zemu.tv"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.zemu.tv"
        minSdk = 24
        targetSdk = 35
        versionCode = 2
        versionName = "1.0.1"

    }

    buildTypes {
        release {
            // Shrunk and optimized: noticeably faster on low-end TV boxes.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // Signed with the debug key so `assembleRelease` produces an installable APK.
            // Replace with your own signing config before distributing.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
    }
    // SoundPool reads sound effects straight out of the APK, so they must stay uncompressed.
    androidResources {
        noCompress += listOf("wav", "ogg", "mp3", "m4a")
    }
    lint {
        abortOnError = false
        checkReleaseBuilds = false
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.animation:animation")
    implementation("androidx.compose.material:material-icons-core")
    implementation("androidx.compose.ui:ui-tooling-preview")
    debugImplementation("androidx.compose.ui:ui-tooling")

    implementation("androidx.tv:tv-material:1.0.0")

    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.navigation:navigation-compose:2.8.5")
    implementation("androidx.datastore:datastore-preferences:1.1.1")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("io.coil-kt:coil-compose:2.7.0")
    implementation("com.google.zxing:core:3.5.3")

    implementation("androidx.media3:media3-exoplayer:1.5.1")
    implementation("androidx.media3:media3-exoplayer-hls:1.5.1")
    implementation("androidx.media3:media3-ui:1.5.1")
    // Android TV home screen "Play Next" row.
    implementation("androidx.tvprovider:tvprovider:1.1.0")
    // Applies the bundled startup profiles (Compose, the app) on sideloaded installs, so ART precompiles hot code.
    implementation("androidx.profileinstaller:profileinstaller:1.4.1")
    // Software audio decoding (DTS, TrueHD, E-AC3, ...) for TVs without those decoders. Built by Jellyfin from media3's ffmpeg extension.
    implementation("org.jellyfin.media3:media3-ffmpeg-decoder:1.5.0+1")

    testImplementation("junit:junit:4.13.2")
}

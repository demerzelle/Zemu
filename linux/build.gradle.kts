import org.jetbrains.compose.desktop.application.dsl.TargetFormat

plugins {
    kotlin("jvm") version "2.1.0"
    id("org.jetbrains.kotlin.plugin.compose") version "2.1.0"
    id("org.jetbrains.kotlin.plugin.serialization") version "2.1.0"
    id("org.jetbrains.compose") version "1.7.3"
}

// Same version as the Android app (release.sh bumps it there).
val zemuVersion = Regex("versionName = \"([^\"]+)\"").find(file("../app/build.gradle.kts").readText())!!.groupValues[1]
version = zemuVersion

// Java 17+ runs it (Ubuntu 22.04's default-jre and newer).
kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }
java { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }

/**
 * Small edits to shared files, applied to copies at build time so the Android sources stay the one
 * source of truth. The build fails if a patch no longer matches.
 */
val patches: Map<String, List<Pair<String, String>>> = mapOf(
    // Esc / Backspace need the nav controller to go back.
    "com/zemu/tv/ui/AppShell.kt" to listOf(
        """    val nav = rememberNavController()
""" to """    val nav = rememberNavController()
    com.zemu.tv.desktop.DesktopNav.controller = nav
""",
        // A steady logo glow: the breathing one repaints the whole window 60 times a second on desktop.
        """            val pulse = androidx.compose.animation.core.rememberInfiniteTransition(label = "logoGlow")
            val glow by pulse.animateFloat(
                0.35f, 1f,
                androidx.compose.animation.core.infiniteRepeatable(
                    androidx.compose.animation.core.tween(2600, easing = androidx.compose.animation.core.FastOutSlowInEasing),
                    androidx.compose.animation.core.RepeatMode.Reverse,
                ),
                label = "logoGlowAlpha",
            )""" to """            val glow = 0.7f""",
    ),
    // No animated themes on Linux: they're the heaviest part of the UI on slow machines.
    "com/zemu/tv/ui/theme/DynamicThemes.kt" to listOf(
        """fun of(name: String) = entries.firstOrNull { it.name == (RENAMED[name] ?: name) } ?: NONE""" to
            """fun of(@Suppress("UNUSED_PARAMETER") name: String) = NONE""",
    ),
    "com/zemu/tv/ui/settings/SettingsScreen.kt" to listOf(
        """    group("animated", "Animated themes"""" to """    if (false) group("animated", "Animated themes"""",
        """ On Android 12 and newer, menus also blur what's behind them.""" to "",
    ),
    "com/zemu/tv/ui/kids/KidsMode.kt" to listOf(
        """DynamicTheme.entries.filter { !it.hidden }.forEach""" to """DynamicTheme.entries.filter { it == com.zemu.tv.ui.theme.DynamicTheme.NONE }.forEach""",
    ),
    // Android-only APIs in otherwise shared files.
    "com/zemu/tv/ui/theme/Theme.kt" to listOf(
        """    val effect = android.graphics.RenderEffect.createColorFilterEffect(android.graphics.ColorMatrixColorFilter(m))
    return graphicsLayer { renderEffect = effect.asComposeRenderEffect() }""" to """    return this""",
        """    val view = androidx.compose.ui.platform.LocalView.current
    androidx.compose.runtime.SideEffect {
        val window = (view.parent as? androidx.compose.ui.window.DialogWindowProvider)?.window ?: return@SideEffect
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_BLUR_BEHIND)
        window.attributes = window.attributes.apply { blurBehindRadius = 48 }
        window.setDimAmount(0.3f)
    }""" to "",
    ),
    "com/zemu/tv/ui/components/QrCode.kt" to listOf(
        "import android.graphics.Bitmap\n" to "",
        """Bitmap.createBitmap(pixels, m.width, m.height, Bitmap.Config.ARGB_8888).asImageBitmap()""" to
            """java.awt.image.BufferedImage(m.width, m.height, java.awt.image.BufferedImage.TYPE_INT_ARGB).apply { setRGB(0, 0, m.width, m.height, pixels, 0, m.width) }.toComposeImageBitmap()""",
        "import androidx.compose.ui.graphics.asImageBitmap" to "import androidx.compose.ui.graphics.toComposeImageBitmap",
    ),
    "com/zemu/tv/ui/components/CardMenu.kt" to listOf(
        """e.nativeKeyEvent.repeatCount > 0 -> true""" to """false -> true""",
    ),
    "com/zemu/tv/ui/details/DetailsScreen.kt" to listOf("import android.content.Intent\n" to ""),
    // No speech recognizer on desktop.
    "com/zemu/tv/ui/search/SearchScreen.kt" to listOf(
        """import android.content.Intent
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
""" to "",
        """        val voiceIntent = remember {
            Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                .putExtra(RecognizerIntent.EXTRA_PROMPT, "Search movies and series")
        }
        // Only devices with a speech recognizer (a mic remote, Google Assistant, ...) get the button.
        val canVoice = remember {
            SpeechRecognizer.isRecognitionAvailable(context) ||
                context.packageManager.queryIntentActivities(voiceIntent, 0).isNotEmpty()
        }
        val voice = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
            r.data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()?.let(vm::setQuery)
        }
""" to """        val canVoice = false
""",
        """runCatching { voice.launch(voiceIntent) }""" to "",
    ),
)
val patchedDir = layout.buildDirectory.dir("patched")
val patchShared by tasks.registering {
    inputs.property("patches", patches.toString())
    inputs.files(patches.keys.map { "../app/src/main/java/$it" })
    outputs.dir(patchedDir)
    doLast {
        patches.forEach { (path, edits) ->
            var text = file("../app/src/main/java/$path").readText()
            edits.forEach { (old, new) ->
                check(old in text) { "Patch for $path no longer matches: $old" }
                text = text.replace(old, new)
            }
            patchedDir.get().file(path).asFile.apply { parentFile.mkdirs() }.writeText(text)
        }
    }
}
tasks.named("compileKotlin") { dependsOn(patchShared) }

// The Android app's Kotlin is shared; files that are Android-only are replaced in src/main/kotlin.
val androidOnly = listOf(
    "com/zemu/tv/ZemuApp.kt",
    "com/zemu/tv/MainActivity.kt",
    "com/zemu/tv/AppContainer.kt",
    "com/zemu/tv/player/",
    "com/zemu/tv/launcher/",
    "com/zemu/tv/data/Downloads.kt",
    "com/zemu/tv/data/Updater.kt",
    "com/zemu/tv/data/ProfileStore.kt",
    "com/zemu/tv/streams/DeviceCapabilities.kt",
    "com/zemu/tv/ui/settings/ConfigureActivity.kt",
    "com/zemu/tv/ui/components/ZemuLoader.kt",
    "com/zemu/tv/ui/components/Haptics.kt",
    "com/zemu/tv/ui/SoundFx.kt",
) + patches.keys // the patched copies replace these
sourceSets.main {
    kotlin.srcDirs("../app/src/main/java", patchedDir)
    kotlin.exclude { e ->
        val shared = e.file.path.contains("/app/src/main/java/")
        shared && androidOnly.any { e.relativePath.pathString == it || (it.endsWith("/") && e.relativePath.pathString.startsWith(it)) }
    }
    resources.srcDirs("../app/src/main/assets", "../app/src/main/res/drawable-nodpi", "../app/src/main/res/font", "src/main/resources")
}

dependencies {
    implementation(compose.desktop.currentOs)
    // Linux natives for both PCs and ARM boards (Raspberry Pi etc.), whatever OS builds the jar.
    implementation(compose.desktop.linux_x64)
    implementation(compose.desktop.linux_arm64)
    implementation(compose.material3)
    implementation("org.jetbrains.compose.material:material-icons-core:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-swing:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.google.zxing:core:3.5.3")
    implementation("androidx.datastore:datastore-preferences-core:1.1.1")
    implementation("org.jetbrains.androidx.lifecycle:lifecycle-viewmodel-compose:2.8.4")
    implementation("org.jetbrains.androidx.lifecycle:lifecycle-runtime-compose:2.8.4")
    implementation("org.jetbrains.androidx.navigation:navigation-compose:2.8.0-alpha12")
    implementation("io.coil-kt.coil3:coil-compose:3.0.4")
    implementation("io.coil-kt.coil3:coil-network-okhttp:3.0.4")
    testImplementation(kotlin("test"))
}

compose.desktop {
    application {
        mainClass = "com.zemu.tv.desktop.MainKt"
        jvmArgs += listOf("-Xss2m", "-Xmx512m", "-XX:+UseSerialGC", "-XX:TieredStopAtLevel=1")
        nativeDistributions {
            // jpackage only builds packages for the OS it runs on.
            if (System.getProperty("os.name").startsWith("Linux")) targetFormats(TargetFormat.Deb, TargetFormat.Rpm, TargetFormat.AppImage)
            packageName = "zemu"
            packageVersion = zemuVersion
            description = "Stremio-addon streaming client"
            vendor = "Zemu"
            modules("java.net.http", "jdk.unsupported", "java.naming", "java.sql")
            linux {
                iconFile.set(project.file("packaging/zemu.png"))
                shortcut = true
                appCategory = "AudioVideo"
                debMaintainer = "zemu@users.noreply.github.com"
            }
        }
    }
}

tasks.jar { manifest { attributes("Implementation-Version" to zemuVersion) } }

/** One runnable jar with the Linux x64 and ARM64 natives only (works from any build OS). */
val linuxJar by tasks.registering(Jar::class) {
    archiveFileName.set("zemu.jar")
    destinationDirectory.set(layout.buildDirectory.dir("linux"))
    manifest { attributes("Main-Class" to "com.zemu.tv.desktop.MainKt", "Implementation-Version" to zemuVersion) }
    duplicatesStrategy = DuplicatesStrategy.EXCLUDE
    from(sourceSets.main.get().output)
    dependsOn(configurations.runtimeClasspath)
    from({
        configurations.runtimeClasspath.get()
            .filterNot { Regex("skiko-awt-runtime-(macos|windows)").containsMatchIn(it.name) }
            .map { if (it.isDirectory) it else zipTree(it) }
    })
    exclude("META-INF/*.SF", "META-INF/*.DSA", "META-INF/*.RSA", "META-INF/versions/9/module-info.class")
}

/** Zemu-Linux-<version>.tar.gz: the jar, installer, launcher entry and icon (what GitHub Releases carries). */
val linuxTarball by tasks.registering(Tar::class) {
    archiveFileName.set("Zemu-Linux-$zemuVersion.tar.gz")
    destinationDirectory.set(layout.buildDirectory.dir("linux"))
    compression = Compression.GZIP
    into("zemu") {
        from(linuxJar)
        from("packaging") { filePermissions { unix("755") }; include("install.sh") }
        from("packaging") { exclude("install.sh") }
    }
}

tasks.test {
    // Tests get their own data and cache folders.
    environment("XDG_DATA_HOME", layout.buildDirectory.dir("tmp/test-data").get().asFile.path)
    environment("XDG_CACHE_HOME", layout.buildDirectory.dir("tmp/test-cache").get().asFile.path)
    systemProperty("zemu.testClip", layout.buildDirectory.file("testvid/clip.mkv").get().asFile.path)
}

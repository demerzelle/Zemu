package com.zemu.tv

import android.app.Application
import android.content.Context
import com.zemu.tv.data.ProfileStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json

class ZemuApp : Application(), coil.ImageLoaderFactory {
    lateinit var container: AppContainer
        private set
    lateinit var profiles: ProfileStore
        private set

    /** App updates (shared by every profile). */
    val updater by lazy { com.zemu.tv.data.Updater(this) }

    /** The profile picker is shown once per app launch when there's more than one profile. */
    var profileChosen = false

    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onCreate() {
        super.onCreate()
        profiles = ProfileStore(this, Json { ignoreUnknownKeys = true }, appScope)
        val active = profiles.activeIdBlocking().takeIf { id -> profiles.profiles.value.any { it.id == id } } ?: ProfileStore.DEFAULT_ID
        container = AppContainer(this, active)
    }

    /**
     * Images: half-size pixels (RGB_565) and a bounded memory cache keep the low-memory TV boxes from
     * pausing for garbage collection while rows of posters scroll by.
     */
    override fun newImageLoader(): coil.ImageLoader = coil.ImageLoader.Builder(this)
        .allowRgb565(true)
        .crossfade(150)
        .memoryCache { coil.memory.MemoryCache.Builder(this).maxSizePercent(0.2).build() }
        .diskCache { coil.disk.DiskCache.Builder().directory(cacheDir.resolve("images")).maxSizeBytes(300L * 1024 * 1024).build() }
        .build()

    /** Swaps every per-profile object (settings, addons, history, ...) for the given profile's. */
    fun switchProfile(id: String) {
        profileChosen = true
        if (id == container.profileId) return
        runBlocking { profiles.setActive(id) }
        container.appScope.cancel()
        container = AppContainer(this, id)
    }
}

val Context.app: ZemuApp get() = applicationContext as ZemuApp
val Context.container: AppContainer get() = app.container

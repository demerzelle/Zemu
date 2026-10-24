package com.zemu.tv

import android.content.Context
import com.zemu.tv.data.ProfileStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json

/** The desktop app object: one per process, and the [Context] the shared code sees. */
object ZemuApp : Context() {
    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    val profiles: ProfileStore by lazy { ProfileStore(this, Json { ignoreUnknownKeys = true }, appScope) }

    var container: AppContainer = lazyContainer()
        private set

    /** App updates (shared by every profile). */
    val updater by lazy { com.zemu.tv.data.Updater(this) }

    /** The profile picker is shown once per app launch when there's more than one profile. */
    var profileChosen = false

    private fun lazyContainer(): AppContainer {
        val active = profiles.activeIdBlocking().takeIf { id -> profiles.profiles.value.any { it.id == id } } ?: ProfileStore.DEFAULT_ID
        return AppContainer(this, active)
    }

    /** Swaps every per-profile object (settings, addons, history, ...) for the given profile's. */
    fun switchProfile(id: String) {
        profileChosen = true
        if (id == container.profileId) return
        runBlocking { profiles.setActive(id) }
        container.appScope.cancel()
        container = AppContainer(this, id)
    }
}

val Context.app: ZemuApp get() = ZemuApp
val Context.container: AppContainer get() = ZemuApp.container

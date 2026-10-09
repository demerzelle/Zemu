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

class ZemuApp : Application() {
    lateinit var container: AppContainer
        private set
    lateinit var profiles: ProfileStore
        private set

    /** The profile picker is shown once per app launch when there's more than one profile. */
    var profileChosen = false

    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onCreate() {
        super.onCreate()
        profiles = ProfileStore(this, Json { ignoreUnknownKeys = true }, appScope)
        val active = profiles.activeIdBlocking().takeIf { id -> profiles.profiles.value.any { it.id == id } } ?: ProfileStore.DEFAULT_ID
        container = AppContainer(this, active)
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

val Context.app: ZemuApp get() = applicationContext as ZemuApp
val Context.container: AppContainer get() = app.container

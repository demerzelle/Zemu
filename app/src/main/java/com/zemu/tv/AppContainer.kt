package com.zemu.tv

import android.content.Context
import com.zemu.tv.data.AddonClient
import com.zemu.tv.data.AddonRepository
import com.zemu.tv.data.SkipSegments
import com.zemu.tv.data.StreamRepository
import com.zemu.tv.data.Tmdb
import com.zemu.tv.data.UserStore
import com.zemu.tv.recommend.Recommender
import com.zemu.tv.recommend.TasteProfile
import com.zemu.tv.streams.DeviceCapabilities
import com.zemu.tv.streams.FilterState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import okhttp3.Cache
import okhttp3.OkHttpClient
import java.io.File
import java.util.concurrent.TimeUnit

/** Manual dependency container; one instance per process. */
class AppContainer(context: Context, val profileId: String = com.zemu.tv.data.ProfileStore.DEFAULT_ID) {
    val appContext: Context = context.applicationContext
    val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    val json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
        isLenient = true
    }

    val http: OkHttpClient = OkHttpClient.Builder()
        .cache(Cache(File(context.cacheDir, "http"), 50L * 1024 * 1024))
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(25, TimeUnit.SECONDS)
        .build()

    val client = AddonClient(http, json)
    val userStore = UserStore(context, json, appScope, profileId)
    val downloads = com.zemu.tv.data.Downloads(context, json)
    val addons = AddonRepository(client, userStore, json, appScope)
    val streams = StreamRepository(addons, client, userStore)
    val recommender = Recommender(addons)
    val tmdb = Tmdb(http, json) { userStore.settings.value.tmdbApiKey }
    val skipSegments = SkipSegments(http, json)
    val trakt = com.zemu.tv.data.Trakt(http, json, userStore, appScope)
    val scores = com.zemu.tv.data.Scores(http, json) { userStore.settings.value.omdbApiKey }
    val kids = com.zemu.tv.data.KidsGate(context, http, json, tmdb, scores, (context.applicationContext as ZemuApp).profiles.kids)
    val freeCast = com.zemu.tv.data.FreeCast(http, json)
    val screensaverImages = com.zemu.tv.data.ScreensaverImages(context, http, json, tmdb) { userStore.settings.value.fanartApiKey }

    /** Home's discovery rows (recommendations and catalogs), published for the screensaver. */
    val discovery = MutableStateFlow(com.zemu.tv.ui.home.DiscoveryPool())

    /**
     * A fresh mix of suggestions for each screensaver run: mostly personal recommendations, the
     * rest from catalogs, minus anything already watched. Falls back to My List before Home loads.
     */
    fun screensaverTitles(count: Int = 30): List<com.zemu.tv.data.Meta> {
        val seen = userStore.watched.value
        val pool = discovery.value
        val daily = pool.recommended.filter { it.id !in seen }.distinctBy { it.id }.shuffled()
        val catalogs = pool.catalogs.filter { it.id !in seen }.distinctBy { it.id }.shuffled()
        val picked = (daily.take(count * 2 / 3) + catalogs).distinctBy { it.id }.take(count)
        return picked.ifEmpty { userStore.myList.value.shuffled().take(count) }
    }
    val debridAuth = com.zemu.tv.data.DebridAuth(http, json)
    /** Shows you've watched that have episodes out since you last watched them. */
    val newEpisodes = com.zemu.tv.data.NewEpisodes(addons, userStore, appScope)

    init {
        appScope.launch { keepDebridFresh() }
    }


    /** Saves the account and installs Torrentio set up with it (replacing any other Torrentio). */
    suspend fun linkDebrid(account: com.zemu.tv.data.DebridAccount): String {
        userStore.saveDebrid(account)
        return addons.install(account.torrentioUrl).fold(
            onSuccess = { streams.invalidate(); "${account.service.label} linked. Torrentio is set up with your account." },
            onFailure = { "${account.service.label} linked, but Torrentio couldn't be installed: ${it.message}" },
        )
    }

    suspend fun unlinkDebrid() {
        val account = userStore.debridNow() ?: return
        userStore.saveDebrid(null)
        addons.addons.value.filter { it.transportUrl.contains("${account.service.torrentio}=${account.token}") }
            .forEach { addons.remove(it.transportUrl) }
        streams.invalidate()
    }

    /** Code-approved Real-Debrid logins expire; renew them shortly before and update Torrentio's URL. */
    private suspend fun keepDebridFresh() {
        addons.ready.first { it }
        while (true) {
            val a = userStore.debridNow()?.takeIf { it.renewable } ?: return
            val wait = a.expiresAt - System.currentTimeMillis() - 30 * 60_000L
            if (wait > 0) { kotlinx.coroutines.delay(wait.coerceAtMost(6 * 3600_000L)); continue }
            val fresh = debridAuth.refresh(a)
            if (fresh == null) { kotlinx.coroutines.delay(10 * 60_000L); continue }
            val old = addons.addons.value.firstOrNull { it.transportUrl.contains("${a.service.torrentio}=${a.token}") }
            userStore.saveDebrid(fresh)
            if (old != null) {
                addons.install(fresh.torrentioUrl)
                if (addons.addons.value.any { it.transportUrl == old.transportUrl }) addons.remove(old.transportUrl)
                streams.invalidate()
            }
        }
    }
    /** What this TV reported; [capabilities] adds the user's overrides from Settings → This TV. */
    val detectedCapabilities: DeviceCapabilities by lazy { DeviceCapabilities.detect(context) }
    val capabilities: DeviceCapabilities
        get() = userStore.settings.value.let { detectedCapabilities.withOverrides(it.deviceOverrides, it.maxResolutionOverride) }

    /** Stream filters persist across titles for the session, like a "sticky" preference. */
    val streamFilter = MutableStateFlow(FilterState())

    /** Text sent from the phone page: an addon URL installs it, anything else is tried as a TMDB key. */
    suspend fun handleRemoteInput(text: String): String {
        if (text.startsWith("tmdb:")) return saveTmdbKey(text.removePrefix("tmdb:"))
        if (text.startsWith("debrid.")) {
            val svc = com.zemu.tv.data.DebridService.entries.firstOrNull { it.name == text.substringAfter("debrid.").substringBefore(':') }
                ?: return "Unknown debrid service."
            val key = text.substringAfter(':').trim()
            if (!debridAuth.verify(svc, key)) return "${svc.label} didn't accept that key. Copy it from ${svc.keyPage}."
            return linkDebrid(com.zemu.tv.data.DebridAccount(svc, key))
        }
        val t = text.trim()
        val looksLikeUrl = t.startsWith("http") || t.startsWith("stremio://") || t.contains("manifest.json") || t.contains('/')
        if (looksLikeUrl) {
            return addons.install(t).fold(
                onSuccess = { a -> streams.invalidate(); "Installed ${a.manifest.name} ${a.manifest.version}" },
                onFailure = { "Couldn't install: ${it.message ?: "invalid manifest"}" },
            )
        }
        return saveTmdbKey(t)
    }

    suspend fun saveTmdbKey(key: String): String {
        val old = userStore.settings.value.tmdbApiKey
        userStore.updateSettings { it.copy(tmdbApiKey = key.trim()) }
        // Wait for the setting to land, then check it against TMDB.
        kotlinx.coroutines.delay(200)
        return if (key.isBlank()) "TMDB key removed"
        else if (tmdb.validate()) "TMDB key saved. Cast photos and filmographies are on."
        else {
            userStore.updateSettings { it.copy(tmdbApiKey = old) }
            "That TMDB key didn't work. Copy the \"API Key\" or \"API Read Access Token\" from themoviedb.org → Settings → API."
        }
    }

    init {
        // Keep the TV "Play Next" row and the phone widget in sync with Continue Watching.
        appScope.launch {
            kotlinx.coroutines.flow.combine(userStore.history, userStore.watched) { h, w ->
                h.filter { it.progress in 0.01f..0.95f && it.meta.id !in w }.distinctBy { it.meta.id }
            }.distinctUntilChanged().collect { list ->
                kotlinx.coroutines.delay(500)
                com.zemu.tv.launcher.WatchNext.update(appContext, list)
            }
        }
    }

    fun tasteProfile(): TasteProfile =
        TasteProfile.from(userStore.history.value, userStore.myList.value, userStore.ratedMetas.value, userStore.ratings.value)

}

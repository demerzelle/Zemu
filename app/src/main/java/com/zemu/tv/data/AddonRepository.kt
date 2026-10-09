package com.zemu.tv.data

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json

data class AddonCatalogSource(val key: String, val name: String, val base: String, val type: String, val id: String)

class AddonRepository(
    private val client: AddonClient,
    private val store: UserStore,
    private val json: Json,
    scope: CoroutineScope,
) {
    private val _addons = MutableStateFlow<List<Addon>>(emptyList())
    val addons: StateFlow<List<Addon>> = _addons.asStateFlow()

    private val _ready = MutableStateFlow(false)
    val ready: StateFlow<Boolean> = _ready.asStateFlow()

    private val lock = Mutex()

    init {
        scope.launch {
            val saved = store.addons.first()
            if (saved == null) installDefaults()
            else _addons.value = saved.mapNotNull { decode(it) }
            _ready.value = true
        }
    }

    private fun decode(a: InstalledAddon): Addon? =
        runCatching { Addon(a.transportUrl, AddonManifest.parse(json, a.manifestJson)) }.getOrNull()

    /** Installs the defaults if nothing is installed yet (e.g. first launch was offline). */
    suspend fun ensureDefaults() {
        if (_addons.value.isEmpty()) installDefaults()
    }

    private suspend fun installDefaults() = lock.withLock {
        val installed = DEFAULT_ADDONS.mapNotNull { url ->
            runCatching { client.fetchManifest(url) }.getOrNull()?.let { (raw, m) -> InstalledAddon(url, raw) to Addon(url, m) }
        }
        if (installed.isNotEmpty()) {
            store.saveAddons(installed.map { it.first })
            _addons.value = installed.map { it.second }
        }
    }

    val kitsu: Addon? get() = _addons.value.firstOrNull { it.manifest.id == KITSU_ID }

    /** Installs the Kitsu addon the first time the Anime page is opened. */
    suspend fun ensureKitsu(): Addon? = kitsu ?: install(KITSU_URL).getOrNull()

    suspend fun install(input: String): Result<Addon> = runCatching {
        val url = AddonClient.normalizeTransportUrl(input)
        val (raw, manifest) = client.fetchManifest(url)
        lock.withLock {
            val addon = Addon(url, manifest)
            // Replace an existing install of the same addon id (e.g. re-configured Torrentio).
            val next = _addons.value.filterNot { it.manifest.id == manifest.id || it.transportUrl == url } + addon
            persist(next, extra = url to raw)
            _addons.value = next
            addon
        }
    }

    suspend fun remove(transportUrl: String) = lock.withLock {
        val next = _addons.value.filterNot { it.transportUrl == transportUrl }
        persist(next)
        _addons.value = next
    }

    private suspend fun persist(list: List<Addon>, extra: Pair<String, String>? = null) {
        val saved = store.addons.first().orEmpty().associateBy { it.transportUrl }
        store.saveAddons(list.mapNotNull { a ->
            if (extra != null && a.transportUrl == extra.first) InstalledAddon(a.transportUrl, extra.second)
            else saved[a.transportUrl]
        })
    }

    val cinemeta: Addon? get() = _addons.value.firstOrNull { it.manifest.id == CINEMETA_ID }

    val hasStreamAddons: Boolean get() = _addons.value.any { it.manifest.hasResource("stream") }

    fun addonsFor(resource: String, type: String, id: String?): List<Addon> =
        _addons.value.filter { it.manifest.supports(resource, type, id) }

    suspend fun catalog(addon: Addon, type: String, catalogId: String, extra: Map<String, String> = emptyMap()): List<Meta> =
        client.catalog(addon.baseUrl, type, catalogId, extra)

    suspend fun catalogDetailed(addon: Addon, type: String, catalogId: String, extra: Map<String, String>): List<Meta> =
        client.catalogDetailed(addon.baseUrl, type, catalogId, extra)

    fun isInstalled(manifestId: String) = _addons.value.any { it.manifest.id == manifestId }

    /** Addon catalogs to browse: those published by installed addons (Cinemeta: Official, Community) plus stremio-addons.net. */
    fun addonCatalogSources(): List<AddonCatalogSource> {
        val fromInstalled = _addons.value.flatMap { a ->
            a.manifest.addonCatalogs.filter { it.type == "all" }.map {
                AddonCatalogSource("${a.manifest.id}/${it.id}", (it.name ?: it.id).replaceFirstChar { c -> c.uppercase() }, a.baseUrl, it.type, it.id)
            }
        }
        val extra = AddonCatalogSource("stremio-addons.net", "stremio-addons.net", "https://stremio-addons.net/api", "all", "stremio-addons.net")
        return (fromInstalled + extra).distinctBy { it.key }
    }

    suspend fun browse(source: AddonCatalogSource): List<CatalogAddon> = client.addonCatalog(source.base, source.type, source.id)

    /** Addons that can provide catalogs or details, in preference order. */
    fun metaProviders(): List<Addon> {
        val preferred = store.settings.value.metaProvider
        return _addons.value.filter { it.manifest.hasResource("meta") || it.manifest.catalogs.isNotEmpty() }
            .sortedByDescending { it.manifest.id == preferred }
    }

    /** True when something besides [excludingId] still provides catalogs. */
    fun hasOtherCatalogProvider(excludingId: String): Boolean =
        _addons.value.any { it.manifest.id != excludingId && it.manifest.catalogs.any { c -> c.type in setOf("movie", "series") && c.requiredExtras.isEmpty() } }

    suspend fun meta(type: String, id: String): Meta? {
        val preferred = store.settings.value.metaProvider
        for (addon in addonsFor("meta", type, id).sortedByDescending { it.manifest.id == preferred }) {
            val m = runCatching { client.meta(addon.baseUrl, type, id) }.getOrNull()
            if (m != null && m.id.isNotBlank()) return m
        }
        return null
    }

    companion object {
        const val CINEMETA_ID = "com.linvo.cinemeta"
        const val KITSU_ID = "community.anime.kitsu"
        const val KITSU_URL = "https://anime-kitsu.strem.fun/manifest.json"
        val DEFAULT_ADDONS = listOf(
            "https://v3-cinemeta.strem.io/manifest.json",
            "https://opensubtitles-v3.strem.io/manifest.json",
        )
    }
}

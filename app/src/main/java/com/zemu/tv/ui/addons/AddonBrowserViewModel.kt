package com.zemu.tv.ui.addons

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.zemu.tv.AppContainer
import com.zemu.tv.data.AddonCatalogSource
import com.zemu.tv.data.AddonManifest
import com.zemu.tv.data.AddonRepository
import com.zemu.tv.ui.settings.RemoteInputServer
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class AddonItem(
    val transportUrl: String,
    val manifest: AddonManifest,
    /** URL of the installed copy (may differ from the catalog's, e.g. a configured install). */
    val installedUrl: String?,
) {
    val installed: Boolean get() = installedUrl != null
    val baseUrl: String get() = (installedUrl ?: transportUrl).substringBefore('?').removeSuffix("/manifest.json").trimEnd('/')
    val configureUrl: String get() = "$baseUrl/configure"
    val canConfigure: Boolean get() = manifest.configurable || manifest.configurationRequired
    val required: Boolean get() = false
    val isCatalogProvider: Boolean get() = manifest.catalogs.any { it.type in setOf("movie", "series") }
}

enum class TypeFilter(val label: String) { ALL("All"), MOVIE("Movies"), SERIES("Series"), CHANNEL("Channels"), TV("TV"), OTHER("Other") }

data class BrowserUi(
    val tabs: List<Pair<String, String>> = listOf(INSTALLED to "Installed"),
    val tab: String = INSTALLED,
    val type: TypeFilter = TypeFilter.ALL,
    val query: String = "",
    val items: List<AddonItem> = emptyList(),
    val loading: Boolean = false,
    val error: String? = null,
    val busy: Set<String> = emptySet(),
    val message: String? = null,
    val remoteAddress: String? = null,
)

const val INSTALLED = "installed"

class AddonBrowserViewModel(private val c: AppContainer) : ViewModel() {
    private val tab = MutableStateFlow(INSTALLED)
    private val type = MutableStateFlow(TypeFilter.ALL)
    private val query = MutableStateFlow("")
    private val catalogs = MutableStateFlow<Map<String, List<Pair<String, AddonManifest>>>>(emptyMap())
    private val sources = MutableStateFlow<List<AddonCatalogSource>>(emptyList())
    private val misc = MutableStateFlow(BrowserUi())

    private val server = RemoteInputServer { text ->
        c.handleRemoteInput(text).also { misc.value = misc.value.copy(message = it) }
    }

    val state: StateFlow<BrowserUi> = combine(
        combine(tab, type, query) { t, ty, q -> Triple(t, ty, q) },
        catalogs, sources, c.addons.addons, misc,
    ) { (t, ty, q), cats, srcs, installed, m ->
        val byId = installed.associateBy { it.manifest.id }
        val raw: List<AddonItem> = if (t == INSTALLED) {
            installed.map { AddonItem(it.transportUrl, it.manifest, it.transportUrl) }
        } else {
            cats[t].orEmpty().map { (url, manifest) -> AddonItem(url, manifest, byId[manifest.id]?.transportUrl) }
        }
        val items = raw.filter { item ->
            val types = item.manifest.types.map { it.lowercase() }
            val typeOk = when (ty) {
                TypeFilter.ALL -> true
                TypeFilter.MOVIE -> "movie" in types
                TypeFilter.SERIES -> "series" in types || "anime" in types
                TypeFilter.CHANNEL -> "channel" in types
                TypeFilter.TV -> "tv" in types
                TypeFilter.OTHER -> types.none { it in setOf("movie", "series", "channel", "tv") }
            }
            val qOk = q.isBlank() || item.manifest.name.contains(q, true) || item.manifest.description.orEmpty().contains(q, true)
            typeOk && qOk
        }
        m.copy(
            tabs = listOf(INSTALLED to "Installed (${installed.size})") + srcs.map { it.key to it.name },
            tab = t, type = ty, query = q, items = items,
        )
    }.stateIn(viewModelScope, SharingStarted.Eagerly, BrowserUi())

    init {
        viewModelScope.launch {
            c.addons.ready.first { it }
            sources.value = c.addons.addonCatalogSources()
        }
    }

    fun startServer() = misc.value.let { misc.value = it.copy(remoteAddress = server.start(viewModelScope)) }
    fun stopServer() = server.stop()

    fun selectTab(key: String) {
        tab.value = key
        if (key != INSTALLED && key !in catalogs.value) loadCatalog(key)
    }

    fun setType(t: TypeFilter) { type.value = t }
    fun setQuery(q: String) { query.value = q }

    private fun loadCatalog(key: String) = viewModelScope.launch {
        val source = sources.value.firstOrNull { it.key == key } ?: return@launch
        misc.value = misc.value.copy(loading = true, error = null)
        runCatching { c.addons.browse(source) }
            .onSuccess { list -> catalogs.value = catalogs.value + (key to list.map { it.transportUrl to it.manifest }) }
            .onFailure { misc.value = misc.value.copy(error = "Couldn't load ${source.name}: ${it.message}") }
        misc.value = misc.value.copy(loading = false)
    }

    fun retry() {
        if (tab.value != INSTALLED) loadCatalog(tab.value)
    }

    fun install(item: AddonItem) = viewModelScope.launch {
        setBusy(item.manifest.id, true)
        installNow(item.transportUrl)
        setBusy(item.manifest.id, false)
    }

    fun installUrl(url: String) = viewModelScope.launch { installNow(url) }

    private suspend fun installNow(url: String): String {
        val msg = c.addons.install(url).fold(
            onSuccess = { a ->
                c.streams.invalidate()
                "Installed ${a.manifest.name} ${a.manifest.version}"
            },
            onFailure = { "Couldn't install: ${it.message ?: "invalid manifest"}" },
        )
        misc.value = misc.value.copy(message = msg)
        return msg
    }

    /** Warning to show before uninstalling, or null if it's safe. */
    fun uninstallWarning(item: AddonItem): String? =
        if (item.isCatalogProvider && !c.addons.hasOtherCatalogProvider(item.manifest.id))
            "${item.manifest.name} is your only catalog/metadata provider. Without it, Home, Movies and Series will be empty until you install another one (for example a TMDB or Cinemeta-compatible addon)."
        else null

    fun uninstall(item: AddonItem) = viewModelScope.launch {
        val url = item.installedUrl ?: return@launch
        setBusy(item.manifest.id, true)
        c.addons.remove(url)

        setBusy(item.manifest.id, false)
        misc.value = misc.value.copy(message = "Uninstalled ${item.manifest.name}")
    }

    private fun setBusy(id: String, on: Boolean) {
        val cur = misc.value
        misc.value = cur.copy(busy = if (on) cur.busy + id else cur.busy - id)
    }

    override fun onCleared() = server.stop()
}

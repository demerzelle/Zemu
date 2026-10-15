package com.zemu.tv.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.preferencesDataStoreFile
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json

/** One DataStore per file for the whole process (DataStore requires a single instance per file). */
object DataStores {
    private val stores = HashMap<String, DataStore<Preferences>>()

    @Synchronized
    fun get(context: Context, name: String): DataStore<Preferences> = stores.getOrPut(name) {
        PreferenceDataStoreFactory.create(produceFile = { context.applicationContext.preferencesDataStoreFile(name) })
    }
}

/** Per-profile data. The original "zemu" file belongs to the first (default) profile. */
class UserStore(context: Context, private val json: Json, scope: CoroutineScope, profileId: String = ProfileStore.DEFAULT_ID) {
    private val ds = DataStores.get(context, if (profileId == ProfileStore.DEFAULT_ID) "zemu" else "zemu_p_$profileId")

    private object Keys {
        val addons = stringPreferencesKey("addons")
        val settings = stringPreferencesKey("settings")
        val myList = stringPreferencesKey("my_list")
        val history = stringPreferencesKey("history")
        val watched = stringPreferencesKey("watched")
        val ratings = stringPreferencesKey("ratings")
        val ratedMetas = stringPreferencesKey("rated_metas")
        val debrid = stringPreferencesKey("debrid")
        val lastStreams = stringPreferencesKey("last_streams")
        val recentSearches = stringPreferencesKey("recent_searches")
        val homeRows = stringPreferencesKey("home_rows")
        val pageRows = stringPreferencesKey("page_rows")
    }

    private val ratingSer = MapSerializer(String.serializer(), Int.serializer())

    private val idSetSer = ListSerializer(String.serializer())

    private val addonListSer = ListSerializer(InstalledAddon.serializer())
    private val metaListSer = ListSerializer(Meta.serializer())
    private val historySer = ListSerializer(WatchEntry.serializer())

    private fun <T> Preferences.decode(key: Preferences.Key<String>, ser: KSerializer<T>): T? =
        this[key]?.let { runCatching { json.decodeFromString(ser, it) }.getOrNull() }

    /** null until the first save, so first launch can install default addons. */
    val addons: Flow<List<InstalledAddon>?> = ds.data.map { it.decode(Keys.addons, addonListSer) }

    val settings: StateFlow<AppSettings> = ds.data
        .map { it.decode(Keys.settings, AppSettings.serializer()) ?: AppSettings() }
        .stateIn(scope, SharingStarted.Eagerly, AppSettings())

    /** The linked debrid account, if any. */
    val debrid: StateFlow<DebridAccount?> = ds.data
        .map { it.decode(Keys.debrid, DebridAccount.serializer()) }
        .stateIn(scope, SharingStarted.Eagerly, null)

    suspend fun debridNow(): DebridAccount? = ds.data.first().decode(Keys.debrid, DebridAccount.serializer())

    suspend fun saveDebrid(account: DebridAccount?) {
        ds.edit { if (account == null) it.remove(Keys.debrid) else it[Keys.debrid] = json.encodeToString(DebridAccount.serializer(), account) }
    }

    val myList: StateFlow<List<Meta>> = ds.data
        .map { it.decode(Keys.myList, metaListSer).orEmpty() }
        .stateIn(scope, SharingStarted.Eagerly, emptyList())

    val history: StateFlow<List<WatchEntry>> = ds.data
        .map { it.decode(Keys.history, historySer).orEmpty() }
        .stateIn(scope, SharingStarted.Eagerly, emptyList())

    /** Titles marked watched (by meta id). */
    val watched: StateFlow<Set<String>> = ds.data
        .map { it.decode(Keys.watched, idSetSer).orEmpty().toSet() }
        .stateIn(scope, SharingStarted.Eagerly, emptySet())

    suspend fun setWatched(meta: Meta, watched: Boolean) {
        ds.edit { p ->
            val cur = p.decode(Keys.watched, idSetSer).orEmpty().toMutableList()
            cur.remove(meta.id)
            if (watched) cur.add(0, meta.id)
            p[Keys.watched] = json.encodeToString(idSetSer, cur.take(2000))
        }
    }

    /** Thumbs up (1) / down (-1) per meta id; feeds recommendations. */
    val ratings: StateFlow<Map<String, Int>> = ds.data
        .map { it.decode(Keys.ratings, ratingSer).orEmpty() }
        .stateIn(scope, SharingStarted.Eagerly, emptyMap())

    /** Genres of rated titles, so ratings keep working after history is cleared. */
    val ratedMetas: StateFlow<List<Meta>> = ds.data
        .map { it.decode(Keys.ratedMetas, metaListSer).orEmpty() }
        .stateIn(scope, SharingStarted.Eagerly, emptyList())

    suspend fun rate(meta: Meta, value: Int) {
        ds.edit { p ->
            val cur = p.decode(Keys.ratings, ratingSer).orEmpty().toMutableMap()
            if (value == 0) cur.remove(meta.id) else cur[meta.id] = value
            p[Keys.ratings] = json.encodeToString(ratingSer, cur)
            val metas = p.decode(Keys.ratedMetas, metaListSer).orEmpty().filterNot { it.id == meta.id }
            p[Keys.ratedMetas] = json.encodeToString(metaListSer, if (value == 0) metas else (listOf(meta.slim()) + metas).take(300))
        }
    }

    suspend fun removeFromHistory(metaId: String) {
        ds.edit { p ->
            val cur = p.decode(Keys.history, historySer).orEmpty()
            p[Keys.history] = json.encodeToString(historySer, cur.filterNot { it.meta.id == metaId })
        }
    }

    suspend fun saveAddons(list: List<InstalledAddon>) {
        ds.edit { it[Keys.addons] = json.encodeToString(addonListSer, list) }
    }

    suspend fun updateSettings(transform: (AppSettings) -> AppSettings) {
        ds.edit { p ->
            val cur = p.decode(Keys.settings, AppSettings.serializer()) ?: AppSettings()
            p[Keys.settings] = json.encodeToString(AppSettings.serializer(), transform(cur))
        }
    }

    suspend fun toggleMyList(meta: Meta) {
        ds.edit { p ->
            val cur = p.decode(Keys.myList, metaListSer).orEmpty()
            val next = if (cur.any { it.id == meta.id }) cur.filterNot { it.id == meta.id } else listOf(meta.slim()) + cur
            p[Keys.myList] = json.encodeToString(metaListSer, next)
        }
    }

    /** [finished]: the player saw the credits start; null = judge by how much was played. */
    suspend fun recordProgress(entry: WatchEntry, finished: Boolean? = null) {
        ds.edit { p ->
            val cur = p.decode(Keys.history, historySer).orEmpty()
            val next = (listOf(entry.copy(meta = entry.meta.slim())) + cur.filterNot { it.meta.id == entry.meta.id }).take(150)
            p[Keys.history] = json.encodeToString(historySer, next)
            val done = entry.meta.type != "series" && (finished ?: (entry.durationMs > 0 && entry.progress > 0.92f))
            if (done || (finished == false && entry.progress >= 0.01f) || entry.progress in 0.01f..0.9f) {
                val watched = p.decode(Keys.watched, idSetSer).orEmpty().toMutableList()
                watched.remove(entry.meta.id)
                if (done) watched.add(0, entry.meta.id)
                p[Keys.watched] = json.encodeToString(idSetSer, watched)
            }
        }
    }

    private val lastStreamSer = MapSerializer(String.serializer(), LastStream.serializer())

    /** The stream last played for each title, so it can be picked again while it's still cached. */
    val lastStreams: StateFlow<Map<String, LastStream>> = ds.data
        .map { it.decode(Keys.lastStreams, lastStreamSer).orEmpty() }
        .stateIn(scope, SharingStarted.Eagerly, emptyMap())

    suspend fun rememberStream(metaId: String, stream: LastStream) {
        ds.edit { p ->
            val cur = p.decode(Keys.lastStreams, lastStreamSer).orEmpty()
            // Newest first; keep the map small.
            val next = linkedMapOf(metaId to stream).apply { putAll(cur.filterKeys { it != metaId }.entries.take(199).associate { it.toPair() }) }
            p[Keys.lastStreams] = json.encodeToString(lastStreamSer, next)
        }
    }

    /** Home's row order and favorite rows. */
    val homeRows: StateFlow<RowPrefs> = ds.data
        .map { it.decode(Keys.homeRows, RowPrefs.serializer()) ?: RowPrefs() }
        .stateIn(scope, SharingStarted.Eagerly, RowPrefs())

    suspend fun saveHomeRows(prefs: RowPrefs) {
        ds.edit { it[Keys.homeRows] = json.encodeToString(RowPrefs.serializer(), prefs) }
    }

    private val pageRowsSer = MapSerializer(String.serializer(), RowPrefs.serializer())

    /** Row order and favorites of the Movies, Series and Anime pages, by page. */
    val pageRows: StateFlow<Map<String, RowPrefs>> = ds.data
        .map { it.decode(Keys.pageRows, pageRowsSer).orEmpty() }
        .stateIn(scope, SharingStarted.Eagerly, emptyMap())

    suspend fun saveRowPrefs(page: String, prefs: RowPrefs) {
        if (page == "home") return saveHomeRows(prefs)
        ds.edit { p ->
            val cur = p.decode(Keys.pageRows, pageRowsSer).orEmpty()
            p[Keys.pageRows] = json.encodeToString(pageRowsSer, cur + (page to prefs))
        }
    }

    /** Searches that led to opening a title, newest first. */
    val recentSearches: StateFlow<List<String>> = ds.data
        .map { it.decode(Keys.recentSearches, idSetSer).orEmpty() }
        .stateIn(scope, SharingStarted.Eagerly, emptyList())

    suspend fun addRecentSearch(q: String) {
        val t = q.trim().takeIf { it.length >= 2 } ?: return
        ds.edit { p ->
            val cur = p.decode(Keys.recentSearches, idSetSer).orEmpty()
            p[Keys.recentSearches] = json.encodeToString(idSetSer, (listOf(t) + cur.filterNot { it.equals(t, ignoreCase = true) }).take(10))
        }
    }

    suspend fun clearRecentSearches() {
        ds.edit { it.remove(Keys.recentSearches) }
    }

    suspend fun clearHistory() {
        ds.edit { it.remove(Keys.history) }
    }
}

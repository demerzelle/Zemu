package com.zemu.tv.data

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

/** A show you've been watching that has [count] episodes out since you last watched it. */
data class NewEpisodesItem(val meta: Meta, val count: Int, val latestRelease: Long) {
    val badge: String get() = "$count NEW"
}

/** The next episode of a show you follow that hasn't come out yet. */
data class UpcomingItem(val meta: Meta, val season: Int, val episode: Int, val at: Long) {
    /** "Fri Oct 17 · S2 E5", or "Today" / "Tomorrow". */
    val badge: String get() {
        val day = java.time.Instant.ofEpochMilli(at).atZone(java.time.ZoneId.systemDefault()).toLocalDate()
        val today = LocalDate.now()
        val whenText = when (day) {
            today -> "Today"
            today.plusDays(1) -> "Tomorrow"
            else -> day.format(java.time.format.DateTimeFormatter.ofPattern("EEE MMM d", java.util.Locale.getDefault()))
        }
        return "$whenText · S$season E$episode"
    }
}

/**
 * Finds shows in your history with episodes released after your last watch: past the episode you
 * were on, and already out. Rechecked when your history changes and every few hours.
 */
class NewEpisodes(private val addons: AddonRepository, private val store: UserStore, scope: CoroutineScope) {
    private val _items = MutableStateFlow<List<NewEpisodesItem>>(emptyList())
    val items: StateFlow<List<NewEpisodesItem>> = _items.asStateFlow()
    private val _upcoming = MutableStateFlow<List<UpcomingItem>>(emptyList())
    /** Coming up in the next 60 days, soonest first: shows in your history and My List. */
    val upcoming: StateFlow<List<UpcomingItem>> = _upcoming.asStateFlow()

    init {
        scope.launch {
            addons.ready.first { it }
            kotlinx.coroutines.flow.combine(store.history, store.myList) { h, l -> h to l }
                .map { (h, l) -> h.filter { it.meta.type == "series" }.map { it.meta.id to it.videoId } + l.filter { it.type == "series" }.map { it.id to "" } }
                .distinctUntilChanged()
                .debounce(1500)
                .collectLatest {
                    while (true) {
                        _items.value = runCatching { check() }.getOrDefault(_items.value)
                        _upcoming.value = runCatching { upcoming() }.getOrDefault(_upcoming.value)
                        delay(6 * 3600_000L)
                    }
                }
        }
    }

    private suspend fun check(): List<NewEpisodesItem> = coroutineScope {
        val now = System.currentTimeMillis()
        val gate = Semaphore(6)
        store.history.value.filter { it.meta.type == "series" }.distinctBy { it.meta.id }.take(40).map { entry ->
            async {
                gate.withPermit {
                    val meta = runCatching { addons.meta("series", entry.meta.id) }.getOrNull() ?: return@withPermit null
                    val ordered = meta.videos.filter { (it.season ?: 1) > 0 }
                        .sortedWith(compareBy({ it.season ?: 0 }, { it.episodeNumber }))
                    val at = ordered.indexOfFirst { it.id == entry.videoId }
                    if (at < 0) return@withPermit null
                    val fresh = ordered.drop(at + 1).mapNotNull { v -> releasedAt(v)?.takeIf { it in (entry.updatedAt + 1)..now } }
                    if (fresh.isEmpty()) null else NewEpisodesItem(meta.slim(), fresh.size, fresh.max())
                }
            }
        }.awaitAll().filterNotNull().sortedByDescending { it.latestRelease }
    }

    private suspend fun upcoming(): List<UpcomingItem> = coroutineScope {
        val now = System.currentTimeMillis()
        val until = now + 60L * 24 * 3600_000L
        val gate = Semaphore(6)
        val shows = (store.history.value.map { it.meta } + store.myList.value).filter { it.type == "series" }.distinctBy { it.id }.take(50)
        shows.map { show ->
            async {
                gate.withPermit {
                    val meta = runCatching { addons.meta("series", show.id) }.getOrNull() ?: return@withPermit null
                    val next = meta.videos.filter { (it.season ?: 1) > 0 }
                        .mapNotNull { v -> releasedAt(v)?.takeIf { it in (now + 1)..until }?.let { v to it } }
                        .minByOrNull { it.second } ?: return@withPermit null
                    UpcomingItem(meta.slim(), next.first.season ?: 1, next.first.episodeNumber, next.second)
                }
            }
        }.awaitAll().filterNotNull().sortedBy { it.at }
    }

    private fun releasedAt(v: Video): Long? {
        val r = v.released?.takeIf { it.isNotBlank() } ?: return null
        return runCatching { Instant.parse(r).toEpochMilli() }.getOrNull()
            ?: runCatching { LocalDate.parse(r.take(10)).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli() }.getOrNull()
    }
}

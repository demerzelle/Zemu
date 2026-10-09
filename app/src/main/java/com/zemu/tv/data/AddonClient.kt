package com.zemu.tv.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.IOException
import java.net.URLEncoder

/** Thin HTTP client for the Stremio addon protocol: `/{resource}/{type}/{id}[/{extra}].json`. */
class AddonClient(private val http: OkHttpClient, private val json: Json) {

    suspend fun fetchManifest(transportUrl: String): Pair<String, AddonManifest> {
        val raw = get(transportUrl)
        return raw to AddonManifest.parse(json, raw)
    }

    suspend fun catalog(base: String, type: String, id: String, extra: Map<String, String> = emptyMap()): List<Meta> =
        json.decodeFromString(CatalogResponse.serializer(), get(resourceUrl(base, "catalog", type, id, extra)))
            .metas.filter { it.id.isNotBlank() }.distinctBy { it.id }

    /** Catalogs like Cinemeta's `last-videos` answer with `metasDetailed` (full metas incl. videos). */
    suspend fun catalogDetailed(base: String, type: String, id: String, extra: Map<String, String> = emptyMap()): List<Meta> =
        json.decodeFromString(CatalogDetailedResponse.serializer(), get(resourceUrl(base, "catalog", type, id, extra)))
            .metasDetailed.filter { it.id.isNotBlank() }

    /** Lists addons from an addon catalog (`/addon_catalog/{type}/{id}.json`). Unparseable entries are skipped. */
    suspend fun addonCatalog(base: String, type: String, id: String): List<CatalogAddon> {
        val root = json.parseToJsonElement(get(resourceUrl(base, "addon_catalog", type, id))).jsonObject
        val list = root["addons"] as? JsonArray ?: return emptyList()
        return list.mapNotNull { el ->
            runCatching {
                val o = el.jsonObject
                val url = (o["transportUrl"] as JsonPrimitive).content
                CatalogAddon(url, AddonManifest.fromObject(json, o["manifest"]!!.jsonObject))
            }.getOrNull()
        }.distinctBy { it.transportUrl }
    }

    suspend fun meta(base: String, type: String, id: String): Meta? =
        json.decodeFromString(MetaResponse.serializer(), get(resourceUrl(base, "meta", type, id))).meta

    suspend fun streams(base: String, type: String, id: String): List<Stream> =
        json.decodeFromString(StreamResponse.serializer(), get(resourceUrl(base, "stream", type, id))).streams

    suspend fun subtitles(base: String, type: String, id: String): List<SubtitleTrack> =
        json.decodeFromString(SubtitlesResponse.serializer(), get(resourceUrl(base, "subtitles", type, id))).subtitles

    private suspend fun get(url: String): String = withContext(Dispatchers.IO) {
        http.newCall(Request.Builder().url(url).build()).execute().use { resp ->
            if (!resp.isSuccessful) throw IOException("HTTP ${resp.code} for $url")
            resp.body?.string() ?: throw IOException("Empty body for $url")
        }
    }

    companion object {
        private fun enc(s: String) = URLEncoder.encode(s, "UTF-8").replace("+", "%20")

        fun resourceUrl(base: String, resource: String, type: String, id: String, extra: Map<String, String> = emptyMap()): String {
            val idPart = enc(id).replace("%3A", ":")
            val extraPart = if (extra.isEmpty()) "" else "/" + extra.entries.joinToString("&") { "${enc(it.key)}=${enc(it.value)}" }
            return "$base/$resource/${enc(type)}/$idPart$extraPart.json"
        }

        /** Accepts `stremio://`, bare hosts, and URLs with or without `/manifest.json`. */
        fun normalizeTransportUrl(input: String): String {
            var url = input.trim()
            if (url.startsWith("stremio://")) url = "https://" + url.removePrefix("stremio://")
            if (!url.startsWith("http://") && !url.startsWith("https://")) url = "https://$url"
            val path = url.substringBefore('?')
            if (!path.endsWith("/manifest.json")) url = path.trimEnd('/') + "/manifest.json" +
                (url.substringAfter('?', "").let { if (it.isEmpty()) "" else "?$it" })
            return url
        }
    }
}

package com.zemu.tv.data

import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject

data class ResourceDef(val name: String, val types: List<String>?, val idPrefixes: List<String>?)

@Serializable
data class ExtraDef(
    val name: String = "",
    val isRequired: Boolean = false,
    @Serializable(with = LenientStringListSerializer::class) val options: List<String> = emptyList(),
)

@Serializable
data class CatalogDef(
    val type: String = "",
    val id: String = "",
    val name: String? = null,
    val extra: List<ExtraDef> = emptyList(),
    val extraRequired: List<String> = emptyList(),
    val extraSupported: List<String> = emptyList(),
) {
    val requiredExtras: Set<String> get() = (extra.filter { it.isRequired }.map { it.name } + extraRequired).toSet()
    fun supportsExtra(name: String) = extra.any { it.name == name } || name in extraSupported
    fun optionsFor(name: String): List<String> = extra.firstOrNull { it.name == name }?.options.orEmpty()
}

@Serializable
data class AddonCatalogDef(val type: String = "", val id: String = "", val name: String? = null)

data class AddonManifest(
    val id: String,
    val name: String,
    val version: String,
    val description: String?,
    val logo: String?,
    val types: List<String>,
    val idPrefixes: List<String>?,
    val resources: List<ResourceDef>,
    val catalogs: List<CatalogDef>,
    val addonCatalogs: List<AddonCatalogDef> = emptyList(),
    /** Has a `/configure` page. */
    val configurable: Boolean = false,
    /** Can't be installed without configuring first. */
    val configurationRequired: Boolean = false,
) {
    fun hasResource(resource: String) = resources.any { it.name == resource }

    fun supports(resource: String, type: String, id: String?): Boolean {
        val res = resources.firstOrNull { it.name == resource } ?: return false
        val types = res.types ?: this.types
        if (types.isNotEmpty() && type !in types) return false
        val prefixes = res.idPrefixes ?: idPrefixes
        if (id != null && !prefixes.isNullOrEmpty() && prefixes.none { id.startsWith(it) }) return false
        return true
    }

    companion object {
        fun parse(json: Json, raw: String): AddonManifest = fromObject(json, json.parseToJsonElement(raw).jsonObject)

        fun fromObject(json: Json, o: JsonObject): AddonManifest {
            fun str(key: String, from: JsonObject = o) = (from[key] as? JsonPrimitive)?.contentOrNull
            fun strList(e: JsonElement?): List<String>? =
                (e as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull }

            val resources = (o["resources"] as? JsonArray).orEmpty().mapNotNull { r ->
                when (r) {
                    is JsonPrimitive -> ResourceDef(r.content, null, null)
                    is JsonObject -> {
                        val n = str("name", r) ?: return@mapNotNull null
                        ResourceDef(n, strList(r["types"]), strList(r["idPrefixes"]))
                    }
                    else -> null
                }
            }
            val catalogs = (o["catalogs"] as? JsonArray)?.let {
                runCatching { json.decodeFromJsonElement(ListSerializer(CatalogDef.serializer()), it) }.getOrNull()
            }.orEmpty()

            val hints = o["behaviorHints"] as? JsonObject
            fun hint(key: String) = (hints?.get(key) as? JsonPrimitive)?.contentOrNull == "true"
            val addonCatalogs = (o["addonCatalogs"] as? JsonArray)?.let {
                runCatching { json.decodeFromJsonElement(ListSerializer(AddonCatalogDef.serializer()), it) }.getOrNull()
            }.orEmpty()

            return AddonManifest(
                id = str("id") ?: error("Manifest has no id"),
                name = str("name") ?: str("id")!!,
                version = str("version") ?: "",
                description = str("description")?.replace(Regex("<[^>]+>"), "")?.replace(Regex("\\s+"), " ")?.trim(),
                logo = str("logo"),
                types = strList(o["types"]).orEmpty(),
                idPrefixes = strList(o["idPrefixes"]),
                resources = resources,
                catalogs = catalogs,
                addonCatalogs = addonCatalogs,
                configurable = hint("configurable"),
                configurationRequired = hint("configurationRequired"),
            )
        }
    }
}

data class Addon(val transportUrl: String, val manifest: AddonManifest) {
    val baseUrl: String = transportUrl.substringBefore('?').removeSuffix("/manifest.json").trimEnd('/')
    val configureUrl: String get() = "$baseUrl/configure"
}

/** An entry from an addon catalog (Stremio's "addon_catalog" resource). */
data class CatalogAddon(val transportUrl: String, val manifest: AddonManifest) {
    val baseUrl: String = transportUrl.substringBefore('?').removeSuffix("/manifest.json").trimEnd('/')
    val configureUrl: String get() = "$baseUrl/configure"
}

package com.zemu.tv.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import okhttp3.FormBody
import okhttp3.OkHttpClient
import okhttp3.Request

/**
 * Debrid services Zemu can link. [torrentio] is the service's name in a Torrentio config URL;
 * [codeLogin] means the TV can be approved with a code on the service's website.
 */
enum class DebridService(val label: String, val keyPage: String, val torrentio: String, val codeLogin: Boolean) {
    REAL_DEBRID("Real-Debrid", "real-debrid.com/apitoken", "realdebrid", true),
    ALL_DEBRID("AllDebrid", "alldebrid.com/apikeys", "alldebrid", true),
    PREMIUMIZE("Premiumize", "premiumize.me/account", "premiumize", false),
    TORBOX("TorBox", "torbox.app/settings", "torbox", false),
    DEBRID_LINK("Debrid-Link", "debrid-link.com/webapp/apikey", "debridlink", false),
}

/** A linked account. Code-approved Real-Debrid logins expire and carry what's needed to renew them. */
@Serializable
data class DebridAccount(
    val service: DebridService,
    val token: String,
    val refreshToken: String? = null,
    val clientId: String? = null,
    val clientSecret: String? = null,
    val expiresAt: Long = 0,
) {
    val renewable: Boolean get() = refreshToken != null && clientId != null && clientSecret != null

    /** Torrentio set up for this account. Its own debrid catalog is left off so Home stays tidy. */
    val torrentioUrl: String get() = "https://torrentio.strem.fun/debridoptions=nocatalog|${service.torrentio}=$token/manifest.json"
}

/** A pending code login: the user opens [url] and enters [userCode], or scans [directUrl]. */
class DeviceLogin(
    val service: DebridService,
    val userCode: String,
    val url: String,
    val directUrl: String,
    val expiresAt: Long,
    val intervalMs: Long,
    internal val poll: suspend () -> DebridAccount?,
) {
    /** The account once the user has approved, null while still waiting. */
    suspend fun check(): DebridAccount? = poll()
}

class DebridAuthException(message: String) : Exception(message)

/** Code logins (Real-Debrid device code, AllDebrid PIN) and API key checks. */
class DebridAuth(private val http: OkHttpClient, private val json: Json) {

    suspend fun start(service: DebridService): DeviceLogin = when (service) {
        DebridService.REAL_DEBRID -> startRealDebrid()
        DebridService.ALL_DEBRID -> startAllDebrid()
        else -> throw DebridAuthException("${service.label} doesn't support code login. Paste your API key instead.")
    }

    private suspend fun startRealDebrid(): DeviceLogin {
        val o = get("$RD_OAUTH/device/code?client_id=$RD_CLIENT_ID&new_credentials=yes")
        o.rdError()?.let { throw DebridAuthException(it) }
        val deviceCode = o.str("device_code") ?: throw DebridAuthException("Real-Debrid didn't return a code.")
        val now = System.currentTimeMillis()
        return DeviceLogin(
            service = DebridService.REAL_DEBRID,
            userCode = o.str("user_code").orEmpty(),
            url = o.str("verification_url") ?: "https://real-debrid.com/device",
            directUrl = o.str("direct_verification_url") ?: o.str("verification_url") ?: "https://real-debrid.com/device",
            expiresAt = now + (o.long("expires_in") ?: 600) * 1000,
            intervalMs = ((o.long("interval") ?: 5) * 1000).coerceAtLeast(3000),
        ) {
            val creds = get("$RD_OAUTH/device/credentials?client_id=$RD_CLIENT_ID&code=$deviceCode")
            val id = creds.str("client_id")
            val secret = creds.str("client_secret")
            if (id == null || secret == null) null else rdToken(id, secret, deviceCode)
        }
    }

    private suspend fun rdToken(clientId: String, secret: String, code: String): DebridAccount {
        val body = FormBody.Builder()
            .add("client_id", clientId).add("client_secret", secret).add("code", code)
            .add("grant_type", "http://oauth.net/grant_type/device/1.0").build()
        val o = call(Request.Builder().url("$RD_OAUTH/token").post(body).build())
        o.rdError()?.let { throw DebridAuthException(it) }
        val token = o.str("access_token") ?: throw DebridAuthException("Real-Debrid didn't return a token.")
        return DebridAccount(
            DebridService.REAL_DEBRID, token,
            refreshToken = o.str("refresh_token"), clientId = clientId, clientSecret = secret,
            expiresAt = System.currentTimeMillis() + (o.long("expires_in") ?: 3600) * 1000,
        )
    }

    /** New token for a code-approved Real-Debrid login, or null if it can't be renewed. */
    suspend fun refresh(a: DebridAccount): DebridAccount? {
        if (!a.renewable) return null
        return runCatching { rdToken(a.clientId!!, a.clientSecret!!, a.refreshToken!!) }.getOrNull()
    }

    private suspend fun startAllDebrid(): DeviceLogin {
        val o = get("$AD_API/pin/get?agent=$AGENT")
        val data = o["data"]?.jsonObject ?: throw DebridAuthException(adError(o) ?: "AllDebrid didn't return a PIN.")
        val pin = data.str("pin").orEmpty()
        val check = data.str("check").orEmpty()
        val checkUrl = data.str("check_url") ?: "$AD_API/pin/check?check=$check&pin=$pin&agent=$AGENT"
        return DeviceLogin(
            service = DebridService.ALL_DEBRID,
            userCode = pin,
            url = data.str("base_url") ?: "https://alldebrid.com/pin/",
            directUrl = data.str("user_url") ?: "https://alldebrid.com/pin/?pin=$pin",
            expiresAt = System.currentTimeMillis() + (data.long("expires_in") ?: 600) * 1000,
            intervalMs = 5000,
        ) {
            val d = get(checkUrl)["data"]?.jsonObject
            val key = d?.str("apikey")
            if (d?.get("activated")?.jsonPrimitive?.booleanOrNull == true && !key.isNullOrBlank()) DebridAccount(DebridService.ALL_DEBRID, key) else null
        }
    }

    /** True if the service accepts [key] as an API key. */
    suspend fun verify(service: DebridService, key: String): Boolean = runCatching {
        val k = key.trim()
        val o = when (service) {
            DebridService.REAL_DEBRID -> call(Request.Builder().url("https://api.real-debrid.com/rest/1.0/user").bearer(k).build())
            DebridService.ALL_DEBRID -> call(Request.Builder().url("$AD_API/user?agent=$AGENT").bearer(k).build())
            DebridService.PREMIUMIZE -> get("https://www.premiumize.me/api/account/info?apikey=$k")
            DebridService.TORBOX -> call(Request.Builder().url("https://api.torbox.app/v1/api/user/me").bearer(k).build())
            DebridService.DEBRID_LINK -> call(Request.Builder().url("https://debrid-link.com/api/v2/account/infos").bearer(k).build())
        }
        when (service) {
            // From a VPN Real-Debrid refuses every call, so the key can't be checked here; Torrentio checks it from its servers.
            DebridService.REAL_DEBRID -> o.str("username") != null || o.str("error") == "permission_denied"
            DebridService.ALL_DEBRID, DebridService.PREMIUMIZE -> o.str("status") == "success"
            DebridService.TORBOX, DebridService.DEBRID_LINK -> o["success"]?.jsonPrimitive?.booleanOrNull == true
        }
    }.getOrDefault(false)

    private fun Request.Builder.bearer(key: String) = header("Authorization", "Bearer $key")

    private suspend fun get(url: String) = call(Request.Builder().url(url).build())

    private suspend fun call(request: Request): JsonObject = withContext(Dispatchers.IO) {
        http.newCall(request.newBuilder().header("User-Agent", "Zemu").build()).execute().use { r ->
            val text = r.body?.string().orEmpty()
            runCatching { json.parseToJsonElement(text).jsonObject }.getOrElse { JsonObject(emptyMap()) }
        }
    }

    private fun JsonObject.str(k: String) = this[k]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() }
    private fun JsonObject.long(k: String) = this[k]?.jsonPrimitive?.longOrNull

    private fun JsonObject.rdError(): String? = when (str("error")) {
        null -> null
        "permission_denied" -> "Real-Debrid refused the request from this network. It blocks most VPNs and some providers. " +
            "Turn the VPN off and try again, or paste your API key from your phone instead."
        else -> "Real-Debrid: ${str("error")}"
    }

    private fun adError(o: JsonObject): String? = o["error"]?.jsonObject?.str("message")?.let { "AllDebrid: $it" }

    private companion object {
        const val AGENT = "zemu"
        const val AD_API = "https://api.alldebrid.com/v4"
        const val RD_OAUTH = "https://api.real-debrid.com/oauth/v2"
        /** Real-Debrid's public client id for open-source apps. */
        const val RD_CLIENT_ID = "X35EXNSAZVT6O"
    }
}

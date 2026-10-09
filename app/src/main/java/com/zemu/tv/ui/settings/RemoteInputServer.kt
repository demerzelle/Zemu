package com.zemu.tv.ui.settings

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.Inet4Address
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import java.net.URLDecoder

/**
 * Tiny LAN web page so long text (addon URLs, API keys) can be pasted from a phone instead of
 * typed with a remote, and profile pictures can be uploaded. Only runs while Settings or the
 * Addons screen is open.
 *
 * @param profiles when set, the page offers a profile-picture upload for these (id to name).
 */
class RemoteInputServer(
    private val profiles: (() -> List<Pair<String, String>>)? = null,
    private val onAvatar: (suspend (profileId: String, bytes: ByteArray) -> String)? = null,
    private val onText: suspend (String) -> String,
) {
    private var server: ServerSocket? = null

    fun start(scope: CoroutineScope): String? {
        if (server != null) return address()
        val socket = runCatching { ServerSocket(PORT) }.recoverCatching { ServerSocket(0) }.getOrNull() ?: return null
        server = socket
        scope.launch(Dispatchers.IO) {
            while (isActive && !socket.isClosed) {
                val client = runCatching { socket.accept() }.getOrNull() ?: break
                launch { runCatching { handle(client) }; runCatching { client.close() } }
            }
        }
        return address()
    }

    fun stop() {
        runCatching { server?.close() }
        server = null
    }

    private fun address(): String? {
        val port = server?.localPort ?: return null
        val ip = runCatching {
            NetworkInterface.getNetworkInterfaces().toList()
                .filter { it.isUp && !it.isLoopback }
                .flatMap { it.inetAddresses.toList() }
                .firstOrNull { it is Inet4Address && it.isSiteLocalAddress }?.hostAddress
        }.getOrNull() ?: return null
        return "http://$ip:$port"
    }

    private fun InputStream.readLineBytes(): String? {
        val out = ByteArrayOutputStream()
        while (true) {
            val b = read()
            if (b < 0) return if (out.size() == 0) null else out.toString(Charsets.UTF_8.name())
            if (b == '\n'.code) break
            if (b != '\r'.code) out.write(b)
            if (out.size() > 8192) break
        }
        return out.toString(Charsets.UTF_8.name())
    }

    private suspend fun handle(client: Socket) {
        client.soTimeout = 15_000
        val input = client.getInputStream().buffered()
        val requestLine = input.readLineBytes() ?: return
        var contentLength = 0
        var contentType = ""
        while (true) {
            val line = input.readLineBytes() ?: break
            if (line.isEmpty()) break
            val name = line.substringBefore(':').trim().lowercase()
            val value = line.substringAfter(':', "").trim()
            if (name == "content-length") contentLength = value.toIntOrNull() ?: 0
            if (name == "content-type") contentType = value
        }
        var message: String? = null
        // "?kind=..." preselects what's being pasted (the TV's QR codes use it).
        var kind = requestLine.split(' ').getOrNull(1).orEmpty().substringAfter("?", "").split('&')
            .firstOrNull { it.startsWith("kind=") }?.substringAfter('=').orEmpty()
        if (requestLine.startsWith("POST")) {
            val body = ByteArray(contentLength.coerceIn(0, MAX_BODY))
            var read = 0
            while (read < body.size) {
                val n = input.read(body, read, body.size - read)
                if (n < 0) break
                read += n
            }
            message = if (contentType.startsWith("multipart/form-data")) {
                handleUpload(body.copyOf(read), contentType)
            } else {
                val fields = String(body, 0, read, Charsets.UTF_8).split('&')
                    .associate { it.substringBefore('=') to URLDecoder.decode(it.substringAfter('=', ""), "UTF-8") }
                val text = fields["url"]
                kind = fields["kind"].orEmpty()
                if (text.isNullOrBlank()) "Please paste something first."
                else onText(if (kind == "auto" || kind.isEmpty()) text.trim() else "$kind:${text.trim()}")
            }
        }
        val bytes = page(message, kind).toByteArray(Charsets.UTF_8)
        val out = client.getOutputStream()
        out.write("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: ${bytes.size}\r\nConnection: close\r\n\r\n".toByteArray())
        out.write(bytes)
        out.flush()
    }

    /** Minimal multipart parser: picks out the "profile" field and the "photo" file. */
    private suspend fun handleUpload(body: ByteArray, contentType: String): String {
        val avatar = onAvatar ?: return "Uploads aren't available here."
        val boundary = contentType.substringAfter("boundary=", "").trim('"').takeIf { it.isNotEmpty() } ?: return "Upload failed."
        val delimiter = "--$boundary".toByteArray()
        val parts = mutableListOf<ByteArray>()
        var start = indexOf(body, delimiter, 0)
        while (start >= 0) {
            val partStart = start + delimiter.size + 2 // skip CRLF
            val next = indexOf(body, delimiter, partStart)
            if (next < 0) break
            parts += body.copyOfRange(partStart, (next - 2).coerceAtLeast(partStart)) // drop CRLF before delimiter
            start = next
        }
        var profileId: String? = null
        var image: ByteArray? = null
        for (part in parts) {
            val headerEnd = indexOf(part, "\r\n\r\n".toByteArray(), 0)
            if (headerEnd < 0) continue
            val headers = String(part, 0, headerEnd, Charsets.UTF_8)
            val content = part.copyOfRange(headerEnd + 4, part.size)
            when {
                headers.contains("name=\"profile\"") -> profileId = String(content, Charsets.UTF_8).trim()
                headers.contains("name=\"photo\"") && content.isNotEmpty() -> image = content
            }
        }
        if (profileId.isNullOrBlank() || image == null) return "Choose a profile and a photo first."
        return avatar(profileId, image)
    }

    private fun indexOf(data: ByteArray, pattern: ByteArray, from: Int): Int {
        outer@ for (i in from..data.size - pattern.size) {
            for (j in pattern.indices) if (data[i + j] != pattern[j]) continue@outer
            return i
        }
        return -1
    }

    private fun esc(s: String) = s.replace("&", "&amp;").replace("<", "&lt;").replace("\"", "&quot;")

    private fun page(message: String?, kind: String): String {
        val kinds = listOf("auto" to "Addon URL or TMDB key (detect)", "tmdb" to "TMDB API key") +
            com.zemu.tv.data.DebridService.entries.map { "debrid.${it.name}" to "${it.label} API key (${it.keyPage})" }
        val kindOptions = kinds.joinToString("") { (v, label) -> "<option value=\"$v\"${if (v == kind) " selected" else ""}>${esc(label)}</option>" }
        val msg = message?.let { "<p class=msg>${esc(it)}</p>" }.orEmpty()
        val upload = profiles?.invoke()?.takeIf { onAvatar != null && it.isNotEmpty() }?.let { list ->
            val options = list.joinToString("") { (id, name) -> "<option value=\"${esc(id)}\">${esc(name)}</option>" }
            """<h2>Profile picture</h2><p>Pick a profile and upload a photo from this device.</p>
<form method=post action="/" enctype="multipart/form-data"><select name=profile>$options</select>
<input type=file name=photo accept="image/*"><button>Upload picture</button></form>"""
        }.orEmpty()
        return """<!doctype html><html><head><meta name=viewport content="width=device-width,initial-scale=1">
<title>Zemu</title><style>
body{font-family:system-ui,sans-serif;background:#0a0a0e;color:#fff;margin:0;padding:24px;max-width:640px}
h1{color:#e50914;margin:0 0 8px}h2{margin:28px 0 4px}p{color:#b8b8c2;line-height:1.5}
input,select{width:100%;box-sizing:border-box;padding:14px;border-radius:10px;border:1px solid #333;background:#17171e;color:#fff;font-size:16px;margin-top:8px}
button{margin-top:12px;width:100%;padding:14px;border:0;border-radius:10px;background:#e50914;color:#fff;font-size:16px;font-weight:700}
.msg{background:#17171e;padding:12px;border-radius:10px;color:#fff}</style></head><body>
<h1>Zemu</h1>$msg<p>Paste a Stremio addon manifest URL (for example your configured debrid addon) to install it on your TV,
your debrid service API key to link your account,
or your free TMDB API key (themoviedb.org → Settings → API) to turn on cast photos, studios and filmographies.</p>
<form method=post action="/"><select name=kind>$kindOptions</select>
<input name=url placeholder="Paste here"><button>Send to TV</button></form>
$upload
</body></html>"""
    }

    companion object {
        const val PORT = 8765
        private const val MAX_BODY = 12 * 1024 * 1024
    }
}

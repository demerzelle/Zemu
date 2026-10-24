package android.net

import java.net.URLDecoder
import java.net.URLEncoder

/** The URL encoding helpers the shared code uses. */
object Uri {
    fun encode(s: String?): String = URLEncoder.encode(s.orEmpty(), Charsets.UTF_8).replace("+", "%20")
    fun decode(s: String?): String = URLDecoder.decode(s.orEmpty().replace("+", "%2B"), Charsets.UTF_8)
}

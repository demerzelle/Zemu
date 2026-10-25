import com.zemu.tv.desktop.useSystemAddressOrder
import okhttp3.OkHttpClient
import okhttp3.Request
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Zemu and mpv must reach the internet from the same address, or IP-locked stream links fail.
 * Compares the address Zemu's HTTP client is seen from with curl's (which picks like mpv). Needs
 * the network, so it only runs with ZEMU_NET_TEST=1.
 */
class AddressOrderTest {
    @Test
    fun sameAddressAsCurl() {
        if (System.getenv("ZEMU_NET_TEST") != "1") return
        useSystemAddressOrder()
        val ours = OkHttpClient().newCall(Request.Builder().url("https://ifconfig.co").header("User-Agent", "curl/8").build()).execute().use { it.body!!.string().trim() }
        val curl = ProcessBuilder("curl", "-s", "https://ifconfig.co").start().inputStream.bufferedReader().readText().trim()
        assertEquals(curl, ours)
    }
}

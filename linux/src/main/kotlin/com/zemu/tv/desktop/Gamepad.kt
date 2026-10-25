package com.zemu.tv.desktop

import com.zemu.tv.player.MpvSession
import java.awt.EventQueue
import java.awt.KeyboardFocusManager
import java.awt.Window
import java.awt.event.KeyEvent
import java.io.File
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Xbox (and other) controllers on Linux, read straight from the kernel's input devices: buttons
 * and D-pad from /dev/input/eventN, the left stick from the matching /dev/input/jsN (which scales
 * every controller's stick the same way). Desktop users get uaccess to these, so no root or extra
 * software is needed. Hot-plugging works: the devices are looked up again until one appears.
 *
 * In Zemu: D-pad / left stick move, A selects (hold for options), B or View goes back, X or Menu
 * opens a title's options, Y opens Search. While a video plays, the buttons go to mpv instead
 * (see [MpvSession.gamepad]).
 */
object Gamepad {
    enum class Button { UP, DOWN, LEFT, RIGHT, A, B, X, Y, LB, RB, VIEW, MENU }

    // Linux input event codes (linux/input-event-codes.h).
    private const val EV_KEY = 1
    private const val EV_ABS = 3
    private const val ABS_HAT0X = 16
    private const val ABS_HAT0Y = 17
    private val keyButtons = mapOf(
        304 to Button.A, 305 to Button.B,
        // Xbox drivers report X as BTN_X (307) and Y as BTN_Y (308).
        307 to Button.X, 308 to Button.Y,
        310 to Button.LB, 311 to Button.RB,
        314 to Button.VIEW, 315 to Button.MENU, 158 to Button.VIEW,
        544 to Button.UP, 545 to Button.DOWN, 546 to Button.LEFT, 547 to Button.RIGHT,
    )

    /** The main window, for sending keys to Zemu only while it's the active window. */
    @Volatile var window: Window? = null

    fun start() {
        if (!System.getProperty("os.name").startsWith("Linux")) return
        Thread(::watch, "gamepad").apply { isDaemon = true }.start()
    }

    /** Finds a controller (a device with a joystick handler), reads it until it goes away, repeats. */
    private fun watch() {
        while (true) {
            val (event, js) = find() ?: run { Thread.sleep(3_000); null } ?: continue
            js?.let { path -> Thread({ runCatching { readStick(path) } }, "gamepad-stick").apply { isDaemon = true }.start() }
            runCatching { readEvents(event) }
            release()
            Thread.sleep(1_000)
        }
    }

    private fun find(): Pair<String, String?>? {
        val blocks = runCatching { File("/proc/bus/input/devices").readText() }.getOrNull()?.split("\n\n") ?: return null
        val pads = blocks.mapNotNull { b ->
            val handlers = b.lineSequence().firstOrNull { it.startsWith("H: Handlers=") }?.substringAfter('=')?.split(' ').orEmpty()
            val js = handlers.firstOrNull { it.startsWith("js") } ?: return@mapNotNull null
            val event = handlers.firstOrNull { it.startsWith("event") } ?: return@mapNotNull null
            val name = b.lineSequence().firstOrNull { it.startsWith("N: Name=") }.orEmpty()
            Triple(name, "/dev/input/$event", "/dev/input/$js")
        }
        val pick = pads.firstOrNull { "box" in it.first.lowercase() } ?: pads.firstOrNull() ?: return null
        System.err.println("Gamepad: using ${pick.first.substringAfter('=')} (${pick.second}, ${pick.third})")
        return pick.second.takeIf { File(it).canRead() }?.let { it to pick.third.takeIf { File(it).canRead() } }
    }

    private fun readEvents(path: String) {
        // struct input_event: a timeval (16 bytes on 64-bit, 8 on 32-bit), then type, code, value.
        val time = if (System.getProperty("os.arch").contains("64")) 16 else 8
        val buf = ByteArray(time + 8)
        File(path).inputStream().use { input ->
            while (true) {
                readFully(input, buf)
                val b = ByteBuffer.wrap(buf).order(ByteOrder.LITTLE_ENDIAN)
                val type = b.getShort(time).toInt() and 0xFFFF
                val code = b.getShort(time + 2).toInt() and 0xFFFF
                val value = b.getInt(time + 4)
                when (type) {
                    EV_KEY -> keyButtons[code]?.let { if (value == 1) press(it) else if (value == 0) up(it) }
                        ?: if (value == 1) System.err.println("Gamepad: unmapped button code $code") else Unit
                    EV_ABS -> when (code) {
                        ABS_HAT0X -> hat(value, Button.LEFT, Button.RIGHT, horizontal = true)
                        ABS_HAT0Y -> hat(value, Button.UP, Button.DOWN, horizontal = false)
                    }
                }
            }
        }
    }

    /** struct js_event: time u32, value s16, type u8 (2 = axis, 0x80 = initial state), number u8. */
    private fun readStick(path: String) {
        val buf = ByteArray(8)
        var x = 0
        var y = 0
        File(path).inputStream().use { input ->
            while (true) {
                readFully(input, buf)
                val b = ByteBuffer.wrap(buf).order(ByteOrder.LITTLE_ENDIAN)
                val value = b.getShort(4).toInt()
                val type = buf[6].toInt() and 0x7F
                val axis = buf[7].toInt() and 0xFF
                if (type != 2 || axis > 1 || (buf[6].toInt() and 0x80) != 0) continue
                if (axis == 0) x = value else y = value
                // Past half-way counts as a press; back under a third releases it.
                stick(Button.LEFT, x < -16000, x > -10000)
                stick(Button.RIGHT, x > 16000, x < 10000)
                stick(Button.UP, y < -16000, y > -10000)
                stick(Button.DOWN, y > 16000, y < 10000)
            }
        }
    }

    private val stickHeld = HashSet<Button>()

    private fun stick(b: Button, pressed: Boolean, released: Boolean) {
        if (pressed && stickHeld.add(b)) press(b)
        else if (released && stickHeld.remove(b)) up(b)
    }

    private var hatX: Button? = null
    private var hatY: Button? = null

    private fun hat(value: Int, neg: Button, pos: Button, horizontal: Boolean) {
        val now = if (value < 0) neg else if (value > 0) pos else null
        val was = if (horizontal) hatX else hatY
        if (now == was) return
        was?.let(::up)
        now?.let(::press)
        if (horizontal) hatX = now else hatY = now
    }

    private fun readFully(input: InputStream, buf: ByteArray) {
        var n = 0
        while (n < buf.size) {
            val r = input.read(buf, n, buf.size - n)
            if (r < 0) throw java.io.EOFException()
            n += r
        }
    }

    // ---- Turning buttons into actions ----

    private val directions = setOf(Button.UP, Button.DOWN, Button.LEFT, Button.RIGHT)
    @Volatile private var repeating: Button? = null
    @Volatile private var repeatId = 0

    private fun press(b: Button) {
        if (MpvSession.gamepad(b)) {
            if (b in directions) repeat(b) { MpvSession.gamepad(b) }
            return
        }
        when (b) {
            Button.UP, Button.DOWN, Button.LEFT, Button.RIGHT -> { key(arrow(b), true); key(arrow(b), false); repeat(b) { key(arrow(b), true); key(arrow(b), false) } }
            // Held like a remote's OK: a long hold opens the title's options.
            Button.A -> key(KeyEvent.VK_ENTER, true)
            Button.B, Button.VIEW -> { key(KeyEvent.VK_ESCAPE, true); key(KeyEvent.VK_ESCAPE, false) }
            Button.X, Button.MENU -> longPressEnter()
            Button.Y -> EventQueue.invokeLater { if (window?.isActive == true) DesktopNav.controller?.navigate("search") }
            Button.LB, Button.RB -> {}
        }
    }

    private fun up(b: Button) {
        if (repeating == b) { repeating = null; repeatId++ }
        if (b == Button.A) key(KeyEvent.VK_ENTER, false)
    }

    /** Holding a direction keeps moving: after 400 ms, every 110 ms. */
    private fun repeat(b: Button, action: () -> Unit) {
        val id = ++repeatId
        repeating = b
        Thread {
            Thread.sleep(400)
            while (repeating == b && repeatId == id) { action(); Thread.sleep(110) }
        }.apply { isDaemon = true }.start()
    }

    private fun longPressEnter() {
        key(KeyEvent.VK_ENTER, true)
        Thread { Thread.sleep(700); key(KeyEvent.VK_ENTER, false) }.apply { isDaemon = true }.start()
    }

    private fun release() {
        repeating = null; repeatId++
        stickHeld.clear(); hatX = null; hatY = null
    }

    private fun arrow(b: Button) = when (b) {
        Button.UP -> KeyEvent.VK_UP
        Button.DOWN -> KeyEvent.VK_DOWN
        Button.LEFT -> KeyEvent.VK_LEFT
        else -> KeyEvent.VK_RIGHT
    }

    /** Sends a key to whatever has focus in Zemu's window, as if typed; nothing when Zemu isn't active. */
    private fun key(code: Int, down: Boolean) = EventQueue.invokeLater {
        val w = window ?: return@invokeLater
        if (!w.isActive) return@invokeLater
        val target = KeyboardFocusManager.getCurrentKeyboardFocusManager().focusOwner ?: w.mostRecentFocusOwner ?: w
        val char = if (code == KeyEvent.VK_ENTER) '\n' else KeyEvent.CHAR_UNDEFINED
        target.dispatchEvent(KeyEvent(target, if (down) KeyEvent.KEY_PRESSED else KeyEvent.KEY_RELEASED, System.currentTimeMillis(), 0, code, char))
    }
}

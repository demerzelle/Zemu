package android.graphics

object Color {
    fun argb(a: Int, r: Int, g: Int, b: Int) = (a shl 24) or (r shl 16) or (g shl 8) or b

    fun colorToHSV(color: Int, hsv: FloatArray) {
        val f = java.awt.Color.RGBtoHSB((color shr 16) and 255, (color shr 8) and 255, color and 255, null)
        hsv[0] = f[0] * 360f; hsv[1] = f[1]; hsv[2] = f[2]
    }
}

/** Android's named system typefaces; on desktop they map to the bundled default family. */
class Typeface private constructor(val name: String, val style: Int) {
    companion object {
        const val NORMAL = 0
        const val BOLD = 1
        fun create(name: String, style: Int) = Typeface(name, style)
    }
}

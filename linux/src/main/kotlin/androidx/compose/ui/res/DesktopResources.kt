package androidx.compose.ui.res

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.painter.BitmapPainter
import androidx.compose.ui.graphics.painter.Painter

@Composable
fun painterResource(id: Int): Painter = remember(id) {
    val path = com.zemu.tv.R.paths.getValue(id)
    BitmapPainter(com.zemu.tv.R::class.java.classLoader.getResourceAsStream(path)!!.use { loadImageBitmap(it) })
}

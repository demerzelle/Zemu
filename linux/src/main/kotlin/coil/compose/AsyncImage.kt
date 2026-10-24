package coil.compose

import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale

// Zemu's Android code uses Coil 2; on desktop the same calls go to Coil 3.

@Composable
fun AsyncImage(
    model: Any?,
    contentDescription: String?,
    modifier: Modifier = Modifier,
    onError: ((coil3.compose.AsyncImagePainter.State.Error) -> Unit)? = null,
    alignment: Alignment = Alignment.Center,
    contentScale: ContentScale = ContentScale.Fit,
) = coil3.compose.AsyncImage(
    model = model, contentDescription = contentDescription, modifier = modifier,
    onError = onError, alignment = alignment, contentScale = contentScale,
)

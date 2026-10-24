package coil.request

import coil3.PlatformContext

object ImageRequest {
    class Builder(@Suppress("UNUSED_PARAMETER") context: android.content.Context) {
        private val b = coil3.request.ImageRequest.Builder(PlatformContext.INSTANCE)
        fun data(data: Any?) = apply { b.data(if (data is java.io.File) okio.Path.Companion.run { data.toOkioPath() } else data) }
        // No fade-in on desktop: Coil 3's crossfade left posters half-faded here, and it costs redraws on slow PCs.
        @Suppress("UNUSED_PARAMETER") fun crossfade(on: Boolean) = this
        fun memoryCacheKey(key: String?) = apply { b.memoryCacheKey(key) }
        fun diskCacheKey(key: String?) = apply { b.diskCacheKey(key) }
        fun build() = b.build()
    }
}

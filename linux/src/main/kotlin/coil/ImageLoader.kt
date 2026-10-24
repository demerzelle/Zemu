package coil

import coil3.PlatformContext
import coil3.SingletonImageLoader

val android.content.Context.imageLoader: coil3.ImageLoader get() = SingletonImageLoader.get(PlatformContext.INSTANCE)

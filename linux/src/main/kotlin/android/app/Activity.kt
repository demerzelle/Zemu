package android.app

/** Never an instance on desktop; `(context as? Activity)?.finish()` is a no-op. */
abstract class Activity : android.content.Context() { abstract fun finish() }

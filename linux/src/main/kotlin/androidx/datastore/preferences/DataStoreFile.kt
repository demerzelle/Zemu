package androidx.datastore.preferences

import android.content.Context
import java.io.File

fun Context.preferencesDataStoreFile(name: String): File = File(filesDir, "datastore/$name.preferences_pb")

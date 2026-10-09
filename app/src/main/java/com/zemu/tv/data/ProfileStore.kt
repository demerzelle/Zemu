package com.zemu.tv.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import java.io.File
import java.util.UUID

/** [avatar] is "preset:<index>" or "file:<absolute path>". */
@Serializable
data class Profile(val id: String, val name: String, val avatar: String = "preset:0")

/** The list of profiles and which one is active. Each profile's own data lives in its [UserStore]. */
class ProfileStore(private val context: Context, private val json: Json, scope: CoroutineScope) {
    private val ds = DataStores.get(context, "zemu_profiles")
    private val listKey = stringPreferencesKey("profiles")
    private val activeKey = stringPreferencesKey("active")
    private val skipPickerKey = stringPreferencesKey("skip_picker")
    private val ser = ListSerializer(Profile.serializer())

    private fun decode(raw: String?): List<Profile> =
        raw?.let { runCatching { json.decodeFromString(ser, it) }.getOrNull() }?.ifEmpty { null } ?: listOf(DEFAULT)

    val profiles: StateFlow<List<Profile>> = ds.data.map { decode(it[listKey]) }
        .stateIn(scope, SharingStarted.Eagerly, runBlocking { decode(ds.data.first()[listKey]) })

    /** Open straight into the last used profile instead of asking who's watching. */
    val skipPicker: StateFlow<Boolean> = ds.data.map { it[skipPickerKey] == "true" }
        .stateIn(scope, SharingStarted.Eagerly, runBlocking { ds.data.first()[skipPickerKey] == "true" })

    suspend fun setSkipPicker(skip: Boolean) = ds.edit { it[skipPickerKey] = skip.toString() }

    fun activeIdBlocking(): String = runBlocking { ds.data.first()[activeKey] } ?: DEFAULT_ID

    suspend fun setActive(id: String) = ds.edit { it[activeKey] = id }

    private suspend fun save(list: List<Profile>) = ds.edit { it[listKey] = json.encodeToString(ser, list) }

    suspend fun add(name: String, avatar: String): Profile {
        val p = Profile(UUID.randomUUID().toString().take(8), name.ifBlank { "Profile ${profiles.value.size + 1}" }, avatar)
        save(profiles.value + p)
        return p
    }

    suspend fun update(profile: Profile) = save(profiles.value.map { if (it.id == profile.id) profile else it })

    /** Deletes a profile and all of its data. The default profile can't be deleted. */
    suspend fun delete(id: String) {
        if (id == DEFAULT_ID) return
        save(profiles.value.filterNot { it.id == id })
        avatarFile(id).delete()
        File(context.filesDir, "datastore/zemu_p_$id.preferences_pb").delete()
    }

    fun avatarFile(id: String) = File(File(context.filesDir, "avatars").apply { mkdirs() }, "$id.jpg")

    /** Decodes, crops to a square, downsizes and re-encodes an uploaded image. Returns the avatar value. */
    fun saveAvatarImage(id: String, bytes: ByteArray): String? {
        val src = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
        val side = minOf(src.width, src.height)
        val square = Bitmap.createBitmap(src, (src.width - side) / 2, (src.height - side) / 2, side, side)
        val scaled = Bitmap.createScaledBitmap(square, 320, 320, true)
        val file = avatarFile(id)
        file.outputStream().use { scaled.compress(Bitmap.CompressFormat.JPEG, 88, it) }
        // A changing value makes image caches reload the new picture.
        return "file:${file.absolutePath}?v=${System.currentTimeMillis()}"
    }

    companion object {
        const val DEFAULT_ID = "default"
        val DEFAULT = Profile(DEFAULT_ID, "Me", "preset:0")
    }
}

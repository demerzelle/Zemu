package com.zemu.tv.data

import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive

/*
 * Community addons are loose about JSON types (a rating may be a number or a string, a director a
 * string or an array). These serializers accept any shape and never throw, so one odd field can't
 * break a whole catalog.
 */

private fun JsonElement.asText(): String = when (this) {
    is JsonNull -> ""
    is JsonPrimitive -> content
    is JsonArray -> joinToString(", ") { it.asText() }
    else -> toString()
}

object LenientStringSerializer : KSerializer<String> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("com.zemu.LenientString", PrimitiveKind.STRING)

    override fun deserialize(decoder: Decoder): String =
        (decoder as JsonDecoder).decodeJsonElement().asText()

    override fun serialize(encoder: Encoder, value: String) = encoder.encodeString(value)
}

object LenientIntSerializer : KSerializer<Int> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("com.zemu.LenientInt", PrimitiveKind.INT)

    override fun deserialize(decoder: Decoder): Int =
        (decoder as JsonDecoder).decodeJsonElement().asText().toDoubleOrNull()?.toInt() ?: 0

    override fun serialize(encoder: Encoder, value: Int) = encoder.encodeInt(value)
}

object LenientLongSerializer : KSerializer<Long> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("com.zemu.LenientLong", PrimitiveKind.LONG)

    override fun deserialize(decoder: Decoder): Long =
        (decoder as JsonDecoder).decodeJsonElement().asText().toDoubleOrNull()?.toLong() ?: 0L

    override fun serialize(encoder: Encoder, value: Long) = encoder.encodeLong(value)
}

object LenientStringListSerializer : KSerializer<List<String>> {
    private val delegate = ListSerializer(String.serializer())
    override val descriptor: SerialDescriptor = delegate.descriptor

    override fun deserialize(decoder: Decoder): List<String> =
        when (val el = (decoder as JsonDecoder).decodeJsonElement()) {
            is JsonArray -> el.map { it.asText() }.filter { it.isNotBlank() }
            is JsonNull -> emptyList()
            is JsonPrimitive -> el.content.split(',').map { it.trim() }.filter { it.isNotBlank() }
            else -> emptyList()
        }

    override fun serialize(encoder: Encoder, value: List<String>) = delegate.serialize(encoder, value)
}

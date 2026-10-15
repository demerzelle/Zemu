package com.zemu.tv.ui.details

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Text
import com.zemu.tv.streams.FacetKind
import com.zemu.tv.streams.FacetOption
import com.zemu.tv.streams.FilterState
import com.zemu.tv.streams.HdrFormat
import com.zemu.tv.streams.Languages
import com.zemu.tv.streams.ParsedStream
import com.zemu.tv.streams.RankedStream
import com.zemu.tv.ui.components.FocusSurface
import com.zemu.tv.ui.components.Tag
import com.zemu.tv.ui.components.TvChip
import com.zemu.tv.ui.theme.Palette

/** Facets shown as buttons, in this order, when they have something to choose between. */
private val barFacets = listOf(
    FacetKind.QUALITY, FacetKind.AUDIO_LANG, FacetKind.SUB_LANG, FacetKind.SIZE, FacetKind.HDR,
    FacetKind.CODEC, FacetKind.AUDIO, FacetKind.CHANNELS, FacetKind.SOURCE, FacetKind.SERVICE, FacetKind.ADDON,
)

@Composable
fun FilterBar(
    filter: FilterState,
    facets: Map<FacetKind, List<FacetOption>>,
    externalSubLangs: Set<String>,
    onSort: () -> Unit,
    onFacet: (FacetKind) -> Unit,
    onToggleDeviceFriendly: () -> Unit,
    onToggleCam: () -> Unit,
    onReset: () -> Unit,
) {
    LazyRow(
        contentPadding = PaddingValues(horizontal = 48.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item { TvChip("Sort: ${filter.sort.label}", selected = false, onClick = onSort) }
        item { TvChip("Plays well on this TV", selected = filter.deviceFriendlyOnly, onClick = onToggleDeviceFriendly) }
        barFacets.forEach { kind ->
            val options = facets[kind].orEmpty()
            val sel = filter.selected[kind].orEmpty()
            if (options.size > 1 || sel.isNotEmpty()) {
                item(key = kind.name) {
                    val label = when {
                        sel.isEmpty() -> kind.label
                        sel.size == 1 -> "${kind.label}: ${options.firstOrNull { it.value in sel }?.label?.substringBefore("  (") ?: sel.first()}"
                        else -> "${kind.label}: ${sel.size}"
                    }
                    TvChip("$label ▾", selected = sel.isNotEmpty(), onClick = { onFacet(kind) })
                }
            }
        }
        item { TvChip("Hide CAM", selected = filter.hideCam, onClick = onToggleCam) }
        if (filter.activeCount > 0) item { TvChip("Reset filters", selected = false, onClick = onReset) }
    }
    if (externalSubLangs.isNotEmpty()) {
        Text(
            "External subtitles available: " + externalSubLangs.take(8).joinToString(", ") { Languages.displayName(it) } +
                if (externalSubLangs.size > 8) " +${externalSubLangs.size - 8} more" else "",
            color = Palette.TextMuted,
            fontSize = 13.sp,
            modifier = Modifier.padding(horizontal = 48.dp),
        )
    }
}

private fun hdrLabel(s: ParsedStream): String? = when {
    HdrFormat.DOLBY_VISION in s.hdr && s.hdr.size > 1 -> "DV · HDR"
    HdrFormat.DOLBY_VISION in s.hdr -> "Dolby Vision"
    HdrFormat.HDR10_PLUS in s.hdr -> "HDR10+"
    HdrFormat.HDR10 in s.hdr -> "HDR"
    HdrFormat.HLG in s.hdr -> "HLG"
    else -> null
}

private fun langList(codes: Set<String>, multi: Boolean): String? {
    val names = codes.take(4).map { Languages.displayName(it) } + if (multi && codes.size <= 1) listOf("Multi") else emptyList()
    if (names.isEmpty()) return null
    return names.joinToString(", ") + if (codes.size > 4) " +${codes.size - 4}" else ""
}

@Composable
fun StreamRow(r: RankedStream, externalSubLangs: Set<String>, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val s = r.stream
    FocusSurface(
        onClick = onClick,
        modifier = modifier.fillMaxWidth().padding(horizontal = 48.dp),
        shape = com.zemu.tv.ui.theme.boxy(RoundedCornerShape(10.dp)),
        containerColor = Palette.Surface.copy(alpha = 0.92f),
        // Colored tags inside: focus is an accent outline here rather than an accent fill.
        focusedContainerColor = Palette.SurfaceHigh,
        focusedContentColor = Palette.Text,
        focusedBorder = Palette.FocusBorder,
        focusedScale = 1.015f,
    ) {
        Row(Modifier.padding(horizontal = 18.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.width(96.dp)) {
                Text(s.resolutionLabel, fontSize = 22.sp, fontWeight = FontWeight.Black)
                hdrLabel(s)?.let { Text(it, color = Palette.Imdb, fontSize = 12.sp, fontWeight = FontWeight.Bold) }
            }
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (r.recommended) {
                        Tag("★ BEST FOR THIS TV", Palette.Match, filled = true)
                        Spacer(Modifier.width(8.dp))
                    } else if (!r.deviceFriendly) {
                        Tag("May not play well", Palette.Cached)
                        Spacer(Modifier.width(8.dp))
                    }
                    Text(s.title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                Spacer(Modifier.size(4.dp))
                val specs = listOfNotNull(
                    s.source.label.takeIf { it != "Unknown" },
                    s.codec.label.takeIf { it != "Unknown" }?.let { if (s.tenBit) "$it 10-bit" else it },
                    s.audio.sortedByDescending { it.rank }.joinToString(" ") { it.label }.ifBlank { null }
                        ?.let { a -> s.channels?.let { "$a $it" } ?: a },
                    s.releaseGroup,
                ).joinToString("  ·  ")
                if (specs.isNotBlank()) Text(specs, color = Palette.TextSecondary, fontSize = 13.sp, maxLines = 1)
                val audio = langList(s.audioLanguages, s.multiAudio)
                val subs = langList(s.subtitleLanguages, s.multiSubs)
                val langLine = listOfNotNull(
                    "🔊 " + (audio ?: "Original audio"),
                    subs?.let { "💬 $it" } ?: if (externalSubLangs.isNotEmpty()) "💬 External only" else null,
                ).joinToString("     ")
                Text(langLine, color = Palette.TextSecondary, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Spacer(Modifier.width(12.dp))
            Column(horizontalAlignment = Alignment.End) {
                Text(s.sizeLabel ?: "—", fontSize = 16.sp, fontWeight = FontWeight.Bold)
                Text("⚡ ${s.debridService ?: "Direct"}", color = Palette.Cached, fontSize = 13.sp, fontWeight = FontWeight.Bold)
                Text(
                    s.addonName + (s.seeders?.let { "  ·  👤 $it" } ?: ""),
                    color = Palette.TextMuted,
                    fontSize = 12.sp,
                    maxLines = 1,
                )
            }
        }
    }
}

fun bestSummary(r: RankedStream?): String? {
    val s = r?.stream ?: return null
    return listOfNotNull(
        s.resolutionLabel,
        hdrLabel(s),
        s.audio.maxByOrNull { it.rank }?.label,
        s.sizeLabel,
        s.debridService?.let { "⚡ $it" },
    ).joinToString(" · ")
}

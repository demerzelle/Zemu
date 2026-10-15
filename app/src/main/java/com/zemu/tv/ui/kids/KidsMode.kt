package com.zemu.tv.ui.kids

import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.ui.graphics.Color
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.tv.material3.Text
import com.zemu.tv.app
import com.zemu.tv.container
import com.zemu.tv.data.KidsSettings
import com.zemu.tv.data.Meta
import com.zemu.tv.data.Ratings
import com.zemu.tv.ui.components.CenteredMessage
import com.zemu.tv.ui.components.FocusSurface
import com.zemu.tv.ui.components.TvButton
import com.zemu.tv.ui.components.TvChip
import com.zemu.tv.ui.theme.DialogBackdropBlur
import com.zemu.tv.ui.theme.Palette
import com.zemu.tv.ui.theme.glassPanel
import kotlinx.coroutines.launch

@Composable
fun rememberKids(): KidsSettings = LocalContext.current.app.profiles.kids.collectAsStateWithLifecycle().value

/**
 * [items] minus titles above the Kids Mode rating. Titles show once their rating is known to be
 * allowed; everything passes when Kids Mode is off.
 */
@Composable
fun <T> kidsSafe(items: List<T>, meta: (T) -> Meta): List<T> {
    val gate = LocalContext.current.container.kids
    val kids = rememberKids()
    if (!kids.on) return items
    return produceState(items.filter { gate.knownAllowed(meta(it)) == true }, items, kids.maxLevel) {
        value = gate.filter(items, meta)
    }.value
}

/** Number pad for the 4-digit parent code. Number keys on the remote work too. */
@Composable
fun ParentCodeDialog(title: String, message: String? = null, onDismiss: () -> Unit, onCode: (String) -> Boolean) {
    var code by remember { mutableStateOf("") }
    var wrong by remember { mutableStateOf(false) }
    val shake = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    val first = remember { FocusRequester() }
    fun type(d: String) {
        if (code.length >= 4) return
        code += d
        wrong = false
        if (code.length == 4) {
            if (!onCode(code)) {
                wrong = true
                code = ""
                scope.launch { for (x in listOf(18f, -14f, 10f, -6f, 0f)) shake.animateTo(x) }
            }
        }
    }
    Dialog(onDismissRequest = onDismiss) {
        DialogBackdropBlur()
        Column(
            Modifier.width(420.dp).glassPanel(RoundedCornerShape(18.dp)).padding(26.dp)
                .onPreviewKeyEvent { e ->
                    if (e.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                    val digit = when (e.key) {
                        Key.Zero, Key.NumPad0 -> "0"; Key.One, Key.NumPad1 -> "1"; Key.Two, Key.NumPad2 -> "2"
                        Key.Three, Key.NumPad3 -> "3"; Key.Four, Key.NumPad4 -> "4"; Key.Five, Key.NumPad5 -> "5"
                        Key.Six, Key.NumPad6 -> "6"; Key.Seven, Key.NumPad7 -> "7"; Key.Eight, Key.NumPad8 -> "8"
                        Key.Nine, Key.NumPad9 -> "9"; else -> null
                    }
                    if (digit != null) { type(digit); true } else false
                },
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text("🔒  $title", fontSize = 22.sp, fontWeight = FontWeight.Bold)
            if (message != null) Text(message, color = Palette.TextSecondary, fontSize = 14.sp, modifier = Modifier.padding(top = 6.dp))
            Row(Modifier.padding(vertical = 18.dp).offset(x = shake.value.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                repeat(4) { i ->
                    Box(
                        Modifier.size(18.dp).background(if (i < code.length) Palette.Accent else Color.Transparent, CircleShape)
                            .border(2.dp, if (i < code.length) Palette.Accent else Palette.TextMuted, CircleShape),
                    )
                }
            }
            Text(if (wrong) "Wrong code, try again" else " ", color = Palette.Accent, fontSize = 14.sp)
            Spacer(Modifier.size(8.dp))
            listOf(listOf("1", "2", "3"), listOf("4", "5", "6"), listOf("7", "8", "9"), listOf("⌫", "0", "✕")).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(vertical = 5.dp)) {
                    row.forEach { k ->
                        FocusSurface(
                            onClick = {
                                when (k) {
                                    "⌫" -> code = code.dropLast(1)
                                    "✕" -> onDismiss()
                                    else -> type(k)
                                }
                            },
                            modifier = Modifier.size(72.dp, 56.dp).then(if (k == "1") Modifier.focusRequester(first) else Modifier),
                            shape = RoundedCornerShape(12.dp),
                        ) { Text(k, fontSize = 24.sp, fontWeight = FontWeight.Bold, modifier = Modifier.align(Alignment.Center)) }
                    }
                }
            }
        }
    }
    LaunchedEffect(Unit) { kotlinx.coroutines.delay(60); runCatching { first.requestFocus() } }
}

/** Asks for the parent code; [onUnlocked] runs once it's right. */
@Composable
fun ParentCheck(title: String, onDismiss: () -> Unit, onUnlocked: () -> Unit) {
    val kids = rememberKids()
    ParentCodeDialog(title, "Enter the parent code", onDismiss) { code ->
        (Ratings.hash(code) == kids.pinHash).also { if (it) onUnlocked() }
    }
}

val KIDS_THEMES = listOf("TODDLER" to "Toddler", "GRADE_SCHOOL" to "Grade School", "YOUNG_ADULT" to "Young Adult")

/**
 * Starting Kids Mode: the highest rating allowed, the kids theme and (the first time) a new
 * parent code, entered twice.
 */
@Composable
fun KidsModeSetup(onDismiss: () -> Unit) {
    val context = LocalContext.current
    val kids = rememberKids()
    var level by remember { mutableIntStateOf(kids.maxLevel) }
    var theme by remember { mutableStateOf(kids.theme) }
    var step by remember { mutableIntStateOf(0) } // 0 = options, 1 = new code, 2 = confirm code
    var firstCode by remember { mutableStateOf("") }
    val first = remember { FocusRequester() }
    fun start(pinHash: String) {
        // The app's scope: this dialog's own scope ends as it closes, which would cancel the save.
        context.container.appScope.launch { context.app.profiles.updateKids { it.copy(on = true, maxLevel = level, theme = theme, pinHash = pinHash) } }
        onDismiss()
    }
    when (step) {
        1 -> ParentCodeDialog("Create a parent code", "4 digits. You'll need it to leave Kids Mode.", onDismiss) { firstCode = it; step = 2; true }
        2 -> ParentCodeDialog("Enter it again", null, onDismiss) { code ->
            (code == firstCode).also { if (it) start(Ratings.hash(code)) }
        }
        else -> Dialog(onDismissRequest = onDismiss, properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false)) {
            DialogBackdropBlur()
            Column(Modifier.width(680.dp).glassPanel(RoundedCornerShape(18.dp)).padding(26.dp)) {
                Text("Kids Mode", fontSize = 26.sp, fontWeight = FontWeight.Bold)
                Text(
                    "Only titles rated up to your pick show and play. Settings and profiles lock, and leaving needs the parent code. Titles without a US rating are hidden. Ratings come from TMDB, so a TMDB key is needed (anime uses Kitsu).",
                    color = Palette.TextSecondary, fontSize = 14.sp, modifier = Modifier.padding(top = 6.dp, bottom = 16.dp),
                )
                Text("Highest rating allowed", fontWeight = FontWeight.SemiBold)
                Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Ratings.LEVELS.forEachIndexed { i, label ->
                        TvChip(label, level == i, { level = i }, if (i == level) Modifier.focusRequester(first) else Modifier)
                    }
                }
                Text(
                    "Movies up to ${Ratings.LEVELS[level]}, shows up to ${Ratings.TV[level].substringAfterLast(", ")}",
                    color = Palette.TextSecondary, fontSize = 13.sp, modifier = Modifier.padding(top = 6.dp, bottom = 14.dp),
                )
                Text("Theme", fontWeight = FontWeight.SemiBold)
                Row(Modifier.padding(vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    KIDS_THEMES.forEach { (key, label) -> TvChip(label, theme == key, { theme = key }) }
                }
                Spacer(Modifier.size(10.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    TvButton("Cancel", onClick = onDismiss)
                    TvButton(if (kids.pinHash.isEmpty()) "Next: parent code" else "Start Kids Mode", primary = true, onClick = {
                        if (kids.pinHash.isEmpty()) step = 1 else start(kids.pinHash)
                    })
                }
                if (kids.pinHash.isNotEmpty()) Text(
                    "Uses your parent code. To change it: Settings → Kids Mode → Change parent code.",
                    color = Palette.TextMuted, fontSize = 12.sp, modifier = Modifier.padding(top = 10.dp),
                )
            }
            LaunchedEffect(Unit) { kotlinx.coroutines.delay(60); runCatching { first.requestFocus() } }
        }
    }
}

/** In Kids Mode, [content] (Settings, add-ons) shows only after the parent code. */
@Composable
fun ParentLock(content: @Composable () -> Unit) {
    val kids = rememberKids()
    var unlocked by remember { mutableStateOf(false) }
    var asking by remember { mutableStateOf(true) }
    if (!kids.on || unlocked) return content()
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        CenteredMessage("🔒 Grown-ups only", "This part of the app needs the parent code in Kids Mode.") {
            TvButton("Enter parent code", primary = true, onClick = { asking = true })
        }
    }
    if (asking) ParentCheck("Parent code", onDismiss = { asking = false }) { unlocked = true }
}

/** In Kids Mode, a title above the allowed rating shows a lock (a parent can let it through). */
@Composable
fun KidsTitleGate(type: String, id: String, content: @Composable () -> Unit) {
    val gate = LocalContext.current.container.kids
    val kids = rememberKids()
    var unlocked by remember { mutableStateOf(false) }
    var asking by remember { mutableStateOf(false) }
    if (!kids.on || unlocked) return content()
    val ok by produceState<Boolean?>(gate.knownAllowed(Meta(id = id, type = type)), id, kids.maxLevel) {
        value = gate.allowed(Meta(id = id, type = type))
    }
    when (ok) {
        true -> content()
        null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("Checking the rating…", color = Palette.TextSecondary) }
        false -> {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CenteredMessage("🙈 Not for Kids Mode", "This title is above the allowed rating, or has no rating. Ask a grown-up.") {
                    TvButton("Parent code", primary = true, onClick = { asking = true })
                }
            }
            if (asking) ParentCheck("Let this one play?", onDismiss = { asking = false }) { unlocked = true }
        }
    }
}

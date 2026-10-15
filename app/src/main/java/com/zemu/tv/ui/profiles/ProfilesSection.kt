package com.zemu.tv.ui.profiles

import com.zemu.tv.ui.theme.DialogBackdropBlur
import com.zemu.tv.ui.theme.glassPanel
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.tv.material3.Border
import androidx.tv.material3.ClickableSurfaceDefaults
import androidx.tv.material3.Surface
import androidx.tv.material3.Text
import com.zemu.tv.LocalSwitchProfile
import com.zemu.tv.app
import com.zemu.tv.data.Profile
import com.zemu.tv.data.ProfileStore
import com.zemu.tv.ui.components.TvButton
import com.zemu.tv.ui.components.TvChip
import com.zemu.tv.ui.components.TvTextField
import com.zemu.tv.ui.components.touchClick
import com.zemu.tv.ui.theme.Palette
import kotlinx.coroutines.launch

/** Settings → Profiles: switch, add, edit, delete. [phoneAddress] is the phone page for photo uploads. */
@Composable
fun ProfilesSection(phoneAddress: String?) {
    val context = LocalContext.current
    val store = context.app.profiles
    val profiles by store.profiles.collectAsStateWithLifecycle()
    val currentId = context.app.container.profileId
    val switch = LocalSwitchProfile.current
    var editing by remember { mutableStateOf<Profile?>(null) }
    var adding by remember { mutableStateOf(false) }

    Text(
        "Each profile has its own addons, history, My List, likes, recommendations and settings. With more than one profile, Zemu asks who's watching at launch.",
        color = Palette.TextSecondary, fontSize = 14.sp, modifier = Modifier.padding(vertical = 6.dp),
    )
    LazyRow(contentPadding = PaddingValues(vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(20.dp)) {
        items(profiles, key = { it.id }) { p ->
            ProfileTile(p, current = p.id == currentId) { editing = p }
        }
        item(key = "add") {
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(110.dp)) {
                val shape = RoundedCornerShape(18.dp)
                Surface(
                    onClick = { adding = true },
                    modifier = Modifier.touchClick({ adding = true }).size(96.dp),
                    shape = ClickableSurfaceDefaults.shape(shape = shape),
                    scale = ClickableSurfaceDefaults.scale(focusedScale = 1.08f),
                    border = ClickableSurfaceDefaults.border(
                        border = Border(BorderStroke(2.dp, Palette.TextMuted), shape = shape),
                        focusedBorder = Border(BorderStroke(3.dp, Palette.FocusBorder), shape = shape),
                    ),
                    colors = ClickableSurfaceDefaults.colors(containerColor = Color.Transparent, focusedContainerColor = Palette.SurfaceHigh),
                ) {
                    Text("+", fontSize = 44.sp, modifier = Modifier.align(Alignment.Center), color = Palette.TextSecondary)
                }
                Spacer(Modifier.height(8.dp))
                Text("Add profile", fontSize = 14.sp, color = Palette.TextSecondary)
            }
        }
    }
    if (profiles.size > 1) {
        val skip by store.skipPicker.collectAsStateWithLifecycle()
        val scope = rememberCoroutineScope()
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            TvButton("Switch profile", onClick = switch)
            TvChip(
                "Open last used profile at launch",
                selected = skip,
                onClick = { scope.launch { store.setSkipPicker(!skip) } },
            )
        }
    }

    if (adding) {
        ProfileEditor(
            title = "Add profile",
            initial = Profile("", "", "preset:${profiles.size % AvatarPresets.all.size}"),
            canDelete = false,
            phoneAddress = null,
            onSave = { name, avatar, kids -> store.add(name, avatar, kids) },
            onDelete = {},
            onDismiss = { adding = false },
        )
    }
    editing?.let { p ->
        ProfileEditor(
            title = "Edit profile",
            initial = p,
            canDelete = p.id != ProfileStore.DEFAULT_ID && p.id != currentId,
            phoneAddress = phoneAddress,
            onSave = { name, avatar, kids -> store.update(p.copy(name = name.ifBlank { p.name }, avatar = avatar, kids = kids)) },
            onDelete = { store.delete(p.id) },
            onDismiss = { editing = null },
        )
    }
}

@Composable
private fun ProfileTile(p: Profile, current: Boolean, onClick: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(110.dp)) {
        val shape = RoundedCornerShape(18.dp)
        Surface(
            onClick = onClick,
            modifier = Modifier.touchClick(onClick).size(96.dp),
            shape = ClickableSurfaceDefaults.shape(shape = shape),
            scale = ClickableSurfaceDefaults.scale(focusedScale = 1.08f),
            border = ClickableSurfaceDefaults.border(
                border = if (current) Border(BorderStroke(3.dp, Palette.Accent), shape = shape) else Border.None,
                focusedBorder = Border(BorderStroke(3.dp, Palette.FocusBorder), shape = shape),
            ),
            colors = ClickableSurfaceDefaults.colors(containerColor = Color.Transparent, focusedContainerColor = Color.Transparent),
        ) {
            Avatar(p.avatar, 96.dp, corner = 18.dp)
        }
        Spacer(Modifier.height(8.dp))
        Text(p.name, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, fontWeight = if (current) FontWeight.Bold else FontWeight.Normal)
        if (current) Text("Current", fontSize = 11.sp, color = Palette.Accent)
    }
}

@Composable
private fun ProfileEditor(
    title: String,
    initial: Profile,
    canDelete: Boolean,
    phoneAddress: String?,
    onSave: suspend (name: String, avatar: String, kids: Boolean) -> Unit,
    onDelete: suspend () -> Unit,
    onDismiss: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    // Keep showing the latest avatar if a photo is uploaded from the phone while this is open.
    val live by context.app.profiles.profiles.collectAsStateWithLifecycle()
    val uploaded = live.firstOrNull { it.id == initial.id }?.avatar?.takeIf { it.startsWith("file:") }
    var name by remember { mutableStateOf(initial.name) }
    var avatar by remember { mutableStateOf(initial.avatar) }
    var kid by remember { mutableStateOf(initial.kids) }
    val kidsSettings = com.zemu.tv.ui.kids.rememberKids()
    // A kid profile needs a parent code to lock it; asked for before saving if there isn't one yet.
    var needCode by remember { mutableStateOf(false) }
    val save = { scope.launch { onSave(name.trim(), avatar, kid); onDismiss() } }
    LaunchedEffect(uploaded) { if (uploaded != null) avatar = uploaded }
    val first = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { first.requestFocus() } }

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        DialogBackdropBlur()
        Column(
            Modifier
                .width(760.dp)
                .glassPanel(RoundedCornerShape(16.dp))
                .padding(24.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Avatar(avatar, 72.dp)
                Spacer(Modifier.width(18.dp))
                Column(Modifier.weight(1f)) {
                    Text(title, fontSize = 22.sp, fontWeight = FontWeight.Black)
                    TvTextField(name, { name = it.take(20) }, "Profile name", Modifier.fillMaxWidth().padding(top = 8.dp).focusRequester(first))
                }
            }
            Spacer(Modifier.height(14.dp))
            Text("Choose a picture", color = Palette.TextSecondary, fontSize = 14.sp)
            LazyVerticalGrid(
                columns = GridCells.Fixed(9),
                modifier = Modifier.height(170.dp).padding(top = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                itemsIndexed(AvatarPresets.all) { i, _ ->
                    val value = "preset:$i"
                    val shape = RoundedCornerShape(12.dp)
                    Surface(
                        onClick = { avatar = value },
                        modifier = Modifier.touchClick({ avatar = value }).size(64.dp),
                        shape = ClickableSurfaceDefaults.shape(shape = shape),
                        scale = ClickableSurfaceDefaults.scale(focusedScale = 1.12f),
                        border = ClickableSurfaceDefaults.border(
                            border = if (avatar == value) Border(BorderStroke(3.dp, Palette.Accent), shape = shape) else Border.None,
                            focusedBorder = Border(BorderStroke(3.dp, Palette.FocusBorder), shape = shape),
                        ),
                        colors = ClickableSurfaceDefaults.colors(containerColor = Color.Transparent, focusedContainerColor = Color.Transparent),
                    ) { Avatar(value, 64.dp, corner = 12.dp) }
                }
            }
            Text(
                if (phoneAddress != null && initial.id.isNotEmpty()) "Custom photo: open  $phoneAddress  on your phone and upload one for this profile."
                else if (initial.id.isEmpty()) "You can upload a custom photo from your phone after creating the profile."
                else "Custom photos can be uploaded from your phone while Settings is open.",
                color = Palette.Info, fontSize = 13.sp, modifier = Modifier.padding(top = 10.dp),
            )
            Spacer(Modifier.height(16.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                if (kidsSettings.enabled || initial.kids) TvChip("🧸 Kid profile", kid, { kid = !kid })
                TvButton("Save", primary = true, onClick = { if (kid && kidsSettings.pinHash.isEmpty()) needCode = true else save() })
                TvButton("Cancel", onClick = onDismiss)
                if (canDelete) TvButton("Delete profile", onClick = { scope.launch { onDelete(); onDismiss() } })
            }
        }
    }
    if (needCode) com.zemu.tv.ui.kids.CreateParentCode(onDismiss = { needCode = false }) { needCode = false; save() }
}

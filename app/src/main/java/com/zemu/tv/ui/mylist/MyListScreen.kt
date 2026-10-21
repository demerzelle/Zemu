package com.zemu.tv.ui.mylist

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import com.zemu.tv.container
import com.zemu.tv.data.Meta
import com.zemu.tv.ui.components.CenteredMessage
import com.zemu.tv.ui.components.SectionedPosterGrid
import com.zemu.tv.ui.kids.kidsSafe

/** My List, with Watch Later as its own section underneath. */
@Composable
fun MyListScreen(onOpen: (Meta) -> Unit) {
    val c = LocalContext.current.container
    val list = kidsSafe(c.userStore.myList.collectAsStateWithLifecycle().value) { it }
    val later = kidsSafe(c.userStore.watchLater.collectAsStateWithLifecycle().value) { it }
    Column(Modifier.fillMaxSize()) {
        Text(
            "My List",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Black,
            modifier = Modifier.padding(start = 48.dp, top = 32.dp),
        )
        if (list.isEmpty() && later.isEmpty()) CenteredMessage("Your list is empty", "Use “My List” or “Watch later” on any title to save it here.")
        else SectionedPosterGrid(listOf(null to list, "Watch Later" to later), onOpen, Modifier.fillMaxSize())
    }
}

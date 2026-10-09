package com.zemu.tv.ui.mylist

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
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
import com.zemu.tv.ui.components.PosterGrid

@Composable
fun MyListScreen(onOpen: (Meta) -> Unit) {
    val c = LocalContext.current.container
    val list by c.userStore.myList.collectAsStateWithLifecycle()
    Column(Modifier.fillMaxSize()) {
        Text(
            "My List",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Black,
            modifier = Modifier.padding(start = 48.dp, top = 32.dp),
        )
        if (list.isEmpty()) CenteredMessage("Your list is empty", "Use “My List” on any title to save it here.")
        else PosterGrid(list, onOpen, Modifier.fillMaxSize())
    }
}

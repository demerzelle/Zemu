package com.zemu.tv.ui.search

import androidx.compose.runtime.Composable

class VoiceSearch(val start: (() -> Unit)?, val listening: Boolean, val message: String?)

// No speech recognizer on desktop, so no mic button.
@Composable
fun rememberVoiceSearch(onText: (String) -> Unit): VoiceSearch = VoiceSearch(null, false, null)

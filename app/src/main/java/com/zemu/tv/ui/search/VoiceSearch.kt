package com.zemu.tv.ui.search

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat

/** Voice search state: [start] is null when the device can't recognise speech. */
class VoiceSearch(val start: (() -> Unit)?, val listening: Boolean, val message: String?)

/**
 * Listens in-app with [SpeechRecognizer], so no system voice screen opens on top of Zemu
 * (on the Shield that screen has its own mic and search box that don't hand results back).
 * Partial results go to [onText] as they're heard.
 */
@Composable
fun rememberVoiceSearch(onText: (String) -> Unit): VoiceSearch {
    val context = LocalContext.current
    val text by rememberUpdatedState(onText)
    var listening by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    val recognizer = remember {
        if (SpeechRecognizer.isRecognitionAvailable(context)) SpeechRecognizer.createSpeechRecognizer(context) else null
    }
    DisposableEffect(recognizer) {
        recognizer?.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) { listening = true; message = "Listening…" }
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() { message = null }
            override fun onEvent(eventType: Int, params: Bundle?) {}
            override fun onPartialResults(partial: Bundle?) { best(partial)?.let(text) }
            override fun onResults(results: Bundle?) { listening = false; message = null; best(results)?.let(text) }
            override fun onError(error: Int) {
                listening = false
                message = when (error) {
                    SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "Didn't catch that. Try again."
                    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Zemu needs the microphone permission for voice search."
                    SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT, SpeechRecognizer.ERROR_SERVER -> "Voice search couldn't reach the speech service."
                    else -> "Voice search stopped. Try again."
                }
            }
        })
        onDispose { recognizer?.destroy() }
    }
    val intent = remember {
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            .putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            .putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            .putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, context.packageName)
    }
    val listen: () -> Unit = {
        if (listening) recognizer?.stopListening()
        else { message = null; runCatching { recognizer?.startListening(intent) }.onFailure { message = "Voice search isn't available." } }
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) listen() else message = "Zemu needs the microphone permission for voice search."
    }
    val start: (() -> Unit)? = recognizer?.let {
        {
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) listen()
            else permission.launch(Manifest.permission.RECORD_AUDIO)
            Unit
        }
    }
    return VoiceSearch(start, listening, message)
}

private fun best(b: Bundle?): String? =
    b?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.takeIf { it.isNotBlank() }

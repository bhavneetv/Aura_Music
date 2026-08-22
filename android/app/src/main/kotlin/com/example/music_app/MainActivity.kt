package com.example.music_app

import android.app.SearchManager
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val CHANNEL = "com.example.music_app/voice_assistant"
    private var methodChannel: MethodChannel? = null
    private var pendingVoiceQuery: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            if (call.method == "getPendingVoiceQuery") {
                result.success(pendingVoiceQuery)
                pendingVoiceQuery = null
            } else {
                result.notImplemented()
            }
        }

        // Process any voice intent received before Flutter was initialized
        pendingVoiceQuery?.let { query ->
            sendVoiceQueryToFlutter(query)
            pendingVoiceQuery = null
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleVoiceIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleVoiceIntent(intent)
    }

    private fun handleVoiceIntent(intent: Intent?) {
        if (intent == null) return

        val action = intent.action
        var query: String? = null

        if (Intent.ACTION_VIEW == action) {
            val data: Uri? = intent.data
            if (data != null && "aura" == data.scheme) {
                query = data.getQueryParameter("query") ?: data.getQueryParameter("q")
            } else {
                query = intent.getStringExtra("query") ?: intent.getStringExtra("media_name")
            }
        } else if ("android.media.action.MEDIA_PLAYBACK_PREPARE" == action ||
                   "android.intent.action.MEDIA_SEARCH" == action) {
            query = intent.getStringExtra(SearchManager.QUERY)
                ?: intent.getStringExtra("query")
                ?: intent.getStringExtra("android.intent.extra.focus")
        }

        if (!query.isNullOrBlank()) {
            if (methodChannel != null) {
                sendVoiceQueryToFlutter(query)
            } else {
                pendingVoiceQuery = query
            }
        }
    }

    private fun sendVoiceQueryToFlutter(query: String) {
        methodChannel?.invokeMethod("onVoiceQuery", mapOf("query" to query))
    }
}

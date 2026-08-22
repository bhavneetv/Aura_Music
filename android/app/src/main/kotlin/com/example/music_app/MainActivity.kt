package com.example.music_app

import android.app.SearchManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val CHANNEL = "com.example.music_app/voice_assistant"
    private var methodChannel: MethodChannel? = null
    private var pendingVoiceQuery: String? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(AudioRoutingPlugin())
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
        try {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            multicastLock = wifi?.createMulticastLock("AuraMulticastLock")
            multicastLock?.setReferenceCounted(true)
            multicastLock?.acquire()
        } catch (e: Exception) {
            e.printStackTrace()
        }
        handleVoiceIntent(intent)
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            if (multicastLock?.isHeld == true) {
                multicastLock?.release()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
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
            if (data != null) {
                val dataStr = data.toString()
                if (dataStr.contains("dp=") || dataStr.contains("p=") || dataStr.contains("ids=") || dataStr.startsWith("aura")) {
                    methodChannel?.invokeMethod("onDeepLink", mapOf("link" to dataStr))
                } else if ("aura" == data.scheme) {
                    query = data.getQueryParameter("query") ?: data.getQueryParameter("q")
                }
            } else {
                query = intent.getStringExtra("query") ?: intent.getStringExtra("media_name")
            }
        } else if (Intent.ACTION_SEARCH == action || "android.media.action.MEDIA_SEARCH" == action) {
            query = intent.getStringExtra(SearchManager.QUERY) ?: intent.getStringExtra("query")
        }

        if (!query.isNullOrEmpty()) {
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

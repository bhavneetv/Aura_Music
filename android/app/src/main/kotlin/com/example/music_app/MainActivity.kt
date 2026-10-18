package com.example.music_app

import android.app.SearchManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : AudioServiceActivity() {
    private val CHANNEL = "com.example.music_app/voice_assistant"
    private val INSTALLER_CHANNEL = "com.example.music_app/app_installer"
    private var methodChannel: MethodChannel? = null
    private var pendingVoiceQuery: String? = null
    private var pendingDeepLink: String? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(AudioRoutingPlugin())
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            if (call.method == "getPendingVoiceQuery") {
                result.success(pendingVoiceQuery)
                pendingVoiceQuery = null
            } else if (call.method == "getPendingDeepLink") {
                result.success(pendingDeepLink)
                pendingDeepLink = null
            } else {
                result.notImplemented()
            }
        }

        val installerChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALLER_CHANNEL)
        installerChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "canRequestPackageInstalls" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        result.success(packageManager.canRequestPackageInstalls())
                    } else {
                        result.success(true)
                    }
                }
                "openInstallPermissionSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                data = Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            e.printStackTrace()
                            result.error("SETTINGS_ERROR", e.localizedMessage, null)
                        }
                    } else {
                        result.success(true)
                    }
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        installApk(filePath, result)
                    } else {
                        result.error("INVALID_PATH", "File path is null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Keep pendingVoiceQuery and pendingDeepLink intact so Flutter can fetch them via
        // getPendingVoiceQuery and getPendingDeepLink once Dart engine is fully booted.
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
                if (dataStr.contains("dp=") || dataStr.contains("p=") || dataStr.contains("ids=") || dataStr.contains("dpc=") || dataStr.startsWith("aura")) {
                    if (methodChannel != null) {
                        sendDeepLinkToFlutter(dataStr)
                    } else {
                        pendingDeepLink = dataStr
                    }
                } else if ("aura" == data.scheme || "auramusic" == data.scheme) {
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

    private fun sendDeepLinkToFlutter(link: String) {
        methodChannel?.invokeMethod("onDeepLink", mapOf("link" to link))
    }

    private fun installApk(filePath: String, result: MethodChannel.Result) {
        try {
            val file = File(filePath)
            if (!file.exists()) {
                result.error("FILE_NOT_FOUND", "APK file not found at $filePath", null)
                return
            }

            val apkUri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                FileProvider.getUriForFile(
                    applicationContext,
                    "${applicationContext.packageName}.fileProvider",
                    file
                )
            } else {
                Uri.fromFile(file)
            }

            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(apkUri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }

            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            e.printStackTrace()
            result.error("INSTALL_ERROR", e.localizedMessage, null)
        }
    }
}

package com.example.music_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AudioRoutingPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private var context: Context? = null
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var audioManager: AudioManager? = null
    private var audioDeviceCallback: AudioDeviceCallback? = null

    private val routeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            intent?.action?.let { action ->
                if (action == Intent.ACTION_HEADSET_PLUG ||
                    action == AudioManager.ACTION_AUDIO_BECOMING_NOISY ||
                    action == "android.bluetooth.adapter.action.STATE_CHANGED" ||
                    action == "android.bluetooth.device.action.ACL_CONNECTED" ||
                    action == "android.bluetooth.device.action.ACL_DISCONNECTED") {
                    
                    if (action == "android.bluetooth.device.action.ACL_CONNECTED" ||
                        action == Intent.ACTION_HEADSET_PLUG) {
                        clearSpeakerOverride()
                    }
                    sendRouteUpdate()
                }
            }
        }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        audioManager = context?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager

        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "com.example.music_app/audio_routing")
        methodChannel?.setMethodCallHandler(this)

        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "com.example.music_app/audio_routing_events")
        eventChannel?.setStreamHandler(this)

        registerReceivers()
    }

    override fun onDetachedFromEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        unregisterReceivers()
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        context = null
    }

    private fun registerReceivers() {
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_HEADSET_PLUG)
            addAction(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
            addAction("android.bluetooth.adapter.action.STATE_CHANGED")
            addAction("android.bluetooth.device.action.ACL_CONNECTED")
            addAction("android.bluetooth.device.action.ACL_DISCONNECTED")
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context?.registerReceiver(routeReceiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                context?.registerReceiver(routeReceiver, filter)
            }
        } catch (_: Exception) {}

        // Modern, reliable AudioDeviceCallback (available Android M+ / API 23+)
        // Detects Bluetooth A2DP, BLE, USB-C DACs, and 3.5mm headsets with zero extra permissions
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            audioDeviceCallback = object : AudioDeviceCallback() {
                override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) {
                    val hasExternalAudio = addedDevices?.any { dev ->
                        dev.isSink && dev.type != AudioDeviceInfo.TYPE_BUILTIN_SPEAKER && dev.type != AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
                    } == true

                    if (hasExternalAudio) {
                        // When Bluetooth headphones or wired headsets connect, clear speaker override
                        // so media playback automatically routes to the new audio device
                        clearSpeakerOverride()
                    }
                    sendRouteUpdate()
                }

                override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) {
                    clearSpeakerOverride()
                    sendRouteUpdate()
                }
            }
            try {
                audioManager?.registerAudioDeviceCallback(audioDeviceCallback, Handler(Looper.getMainLooper()))
            } catch (_: Exception) {}
        }
    }

    private fun unregisterReceivers() {
        try {
            context?.unregisterReceiver(routeReceiver)
        } catch (_: Exception) {}

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && audioDeviceCallback != null) {
            try {
                audioManager?.unregisterAudioDeviceCallback(audioDeviceCallback)
            } catch (_: Exception) {}
            audioDeviceCallback = null
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getAvailableAudioOutputs" -> {
                val devices = getAvailableAudioOutputs()
                result.success(devices)
            }
            "selectAudioOutput" -> {
                val idObj = call.argument<Any>("id")
                val deviceId = when (idObj) {
                    is Int -> idObj
                    is Number -> idObj.toInt()
                    is String -> idObj.toIntOrNull()
                    else -> null
                }
                val deviceType = call.argument<String>("type")
                val success = setAudioOutput(deviceId, deviceType)
                sendRouteUpdate()
                result.success(success)
            }
            "resetToDefaultRoute" -> {
                val success = resetRoute()
                sendRouteUpdate()
                result.success(success)
            }
            "openSystemOutputSwitcher" -> {
                val success = openSystemOutputSwitcher()
                result.success(success)
            }
            "setVirtual3dSound" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                val strength = (call.argument<Double>("strength") ?: 0.65).toFloat()
                val mode = call.argument<String>("mode") ?: "Wide Room"
                val audioSessionId = call.argument<Int>("audioSessionId") ?: 0
                val success = setVirtual3dSound(enabled, strength, mode, audioSessionId)
                result.success(success)
            }
            else -> result.notImplemented()
        }
    }

    private fun getAvailableAudioOutputs(): List<Map<String, Any>> {
        val list = mutableListOf<Map<String, Any>>()
        val am = audioManager ?: return list

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val devices = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            val currentCommunicationDevice = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                am.communicationDevice
            } else null

            // Filter out earpiece, telephony, Bluetooth SCO (caller voice), and internal line output nodes for media audio
            val validDevices = devices.filter { dev ->
                val type = dev.type
                type != AudioDeviceInfo.TYPE_BUILTIN_EARPIECE &&
                type != AudioDeviceInfo.TYPE_TELEPHONY &&
                type != AudioDeviceInfo.TYPE_BLUETOOTH_SCO &&
                type != AudioDeviceInfo.TYPE_AUX_LINE &&
                type != AudioDeviceInfo.TYPE_LINE_ANALOG &&
                type != AudioDeviceInfo.TYPE_LINE_DIGITAL &&
                getDeviceTypeName(type) != "unknown"
            }

            // Deduplicate devices by product name, prioritizing A2DP stereo media over lower-priority profiles
            val deduplicatedDevices = mutableListOf<AudioDeviceInfo>()
            val seenNames = mutableSetOf<String>()

            val sortedDevices = validDevices.sortedWith(Comparator { a, b ->
                fun rank(t: Int): Int = when (t) {
                    AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> 1
                    AudioDeviceInfo.TYPE_BLE_HEADSET, AudioDeviceInfo.TYPE_BLE_SPEAKER -> 2
                    AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> 3
                    AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_DEVICE -> 4
                    AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> 5
                    else -> 10
                }
                rank(a.type).compareTo(rank(b.type))
            })

            for (dev in sortedDevices) {
                if (dev.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER) {
                    deduplicatedDevices.add(dev)
                } else {
                    val rawName = dev.productName.toString().trim().lowercase()
                    if (rawName.isNotEmpty() && !seenNames.contains(rawName)) {
                        seenNames.add(rawName)
                        deduplicatedDevices.add(dev)
                    } else if (rawName.isEmpty()) {
                        deduplicatedDevices.add(dev)
                    }
                }
            }

            val btDevice = deduplicatedDevices.firstOrNull { 
                it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP || 
                it.type == AudioDeviceInfo.TYPE_BLE_HEADSET || 
                it.type == AudioDeviceInfo.TYPE_BLE_SPEAKER 
            }
            val wiredDevice = deduplicatedDevices.firstOrNull { 
                it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET || 
                it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES || 
                it.type == AudioDeviceInfo.TYPE_USB_HEADSET || 
                it.type == AudioDeviceInfo.TYPE_USB_DEVICE 
            }

            val isForcedSpeaker = (am.isSpeakerphoneOn && am.mode == AudioManager.MODE_IN_COMMUNICATION) ||
                (currentCommunicationDevice?.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER)

            for (dev in deduplicatedDevices) {
                val typeName = getDeviceTypeName(dev.type)
                val isSpeaker = dev.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER

                val isCurrent = if (isForcedSpeaker) {
                    isSpeaker
                } else if (currentCommunicationDevice != null) {
                    dev.id == currentCommunicationDevice.id
                } else if (wiredDevice != null) {
                    dev.id == wiredDevice.id
                } else if (btDevice != null) {
                    dev.id == btDevice.id
                } else {
                    isSpeaker
                }

                var name = dev.productName.toString()
                if (name.isBlank() || name.lowercase().contains("builtin") || name.lowercase().contains("built-in")) {
                    name = when (dev.type) {
                        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "Phone Speaker"
                        AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "Wired Headphones"
                        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_BLE_HEADSET, AudioDeviceInfo.TYPE_BLE_SPEAKER -> "Bluetooth Audio"
                        else -> typeName.replaceFirstChar { it.uppercase() }
                    }
                }

                list.add(mapOf(
                    "id" to dev.id,
                    "name" to name,
                    "type" to typeName,
                    "rawType" to dev.type,
                    "isActive" to isCurrent
                ))
            }
        } else {
            val isSpeaker = am.isSpeakerphoneOn
            list.add(mapOf(
                "id" to 1,
                "name" to "Phone Speaker",
                "type" to "speaker",
                "isActive" to isSpeaker
            ))
        }

        return list
    }

    private fun clearSpeakerOverride() {
        val am = audioManager ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                am.clearCommunicationDevice()
            }
            am.isSpeakerphoneOn = false
            am.mode = AudioManager.MODE_NORMAL
            if (am.isBluetoothScoOn) {
                am.stopBluetoothSco()
                am.isBluetoothScoOn = false
            }
        } catch (_: Exception) {}
    }

    private fun setAudioOutput(deviceId: Int?, typeStr: String?): Boolean {
        val am = audioManager ?: return false

        return try {
            if (typeStr == "speaker") {
                // Route audio explicitly to built-in speaker
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val devices = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                    val target = devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                    if (target != null) {
                        am.mode = AudioManager.MODE_IN_COMMUNICATION
                        am.setCommunicationDevice(target)
                        am.isSpeakerphoneOn = true
                    }
                } else {
                    am.isSpeakerphoneOn = true
                }
                if (am.isBluetoothScoOn) {
                    am.stopBluetoothSco()
                    am.isBluetoothScoOn = false
                }
                true
            } else {
                // Route back to Bluetooth / Headset / System default
                clearSpeakerOverride()

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && deviceId != null) {
                    val devices = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                    val target = devices.firstOrNull { it.id == deviceId }
                    if (target != null && target.type != AudioDeviceInfo.TYPE_BUILTIN_SPEAKER && target.type != AudioDeviceInfo.TYPE_BLUETOOTH_SCO) {
                        am.mode = AudioManager.MODE_NORMAL
                        am.setCommunicationDevice(target)
                    }
                }
                true
            }
        } catch (e: Exception) {
            false
        }
    }

    private fun resetRoute(): Boolean {
        clearSpeakerOverride()
        return true
    }

    private fun openSystemOutputSwitcher(): Boolean {
        val ctx = context ?: return false
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val intent = Intent("com.android.settings.panel.action.MEDIA_OUTPUT").apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    putExtra("com.android.settings.panel.extra.PACKAGE_NAME", ctx.packageName)
                }
                ctx.startActivity(intent)
                true
            } else {
                false
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun sendRouteUpdate() {
        val outputs = getAvailableAudioOutputs()
        eventSink?.success(outputs)
    }

    private fun getDeviceTypeName(type: Int): String {
        return when (type) {
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "speaker"
            AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "earpiece"
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_USB_DEVICE -> "headset"
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
            AudioDeviceInfo.TYPE_BLE_SPEAKER -> "bluetooth"
            AudioDeviceInfo.TYPE_AUX_LINE,
            AudioDeviceInfo.TYPE_LINE_ANALOG,
            AudioDeviceInfo.TYPE_LINE_DIGITAL -> "line_out"
            else -> "unknown"
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        sendRouteUpdate()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private var virtualizer: android.media.audiofx.Virtualizer? = null
    private var bassBoost: android.media.audiofx.BassBoost? = null
    private var presetReverb: android.media.audiofx.PresetReverb? = null
    private var activeSessionId: Int = 0

    private fun releaseEffects() {
        android.util.Log.d("AURA-3D", "Releasing spatial 3D effects on session $activeSessionId")
        try {
            virtualizer?.enabled = false
            virtualizer?.release()
        } catch (_: Exception) {}
        virtualizer = null

        try {
            bassBoost?.enabled = false
            bassBoost?.release()
        } catch (_: Exception) {}
        bassBoost = null

        try {
            presetReverb?.enabled = false
            presetReverb?.release()
        } catch (_: Exception) {}
        presetReverb = null
        activeSessionId = -1
    }

    private fun setVirtual3dSound(enabled: Boolean, strength: Float, mode: String, audioSessionId: Int): Boolean {
        android.util.Log.d("AURA-3D", "setVirtual3dSound: enabled=$enabled, strength=$strength, mode=$mode, audioSessionId=$audioSessionId (current activeSession=$activeSessionId)")
        if (!enabled) {
            releaseEffects()
            return true
        }

        return try {
            val targetSession = if (audioSessionId > 0) audioSessionId else 0

            // If audio session ID changed or effects not created, re-create effects on target session
            if (virtualizer == null || targetSession != activeSessionId) {
                releaseEffects()
                activeSessionId = targetSession
                android.util.Log.d("AURA-3D", "Creating audiofx on targetSession: $targetSession")
                try {
                    virtualizer = android.media.audiofx.Virtualizer(0, targetSession)
                    android.util.Log.d("AURA-3D", "Virtualizer created successfully on session $targetSession")
                } catch (e: Exception) {
                    android.util.Log.e("AURA-3D", "Virtualizer failed on session $targetSession, trying fallback to 0: $e")
                    if (targetSession != 0) {
                        try {
                            virtualizer = android.media.audiofx.Virtualizer(0, 0)
                            activeSessionId = 0
                        } catch (err: Exception) {
                            android.util.Log.e("AURA-3D", "Virtualizer fallback to 0 also failed: $err")
                        }
                    }
                }

                try {
                    bassBoost = android.media.audiofx.BassBoost(0, activeSessionId)
                    android.util.Log.d("AURA-3D", "BassBoost created successfully on session $activeSessionId")
                } catch (e: Exception) {
                    android.util.Log.w("AURA-3D", "BassBoost creation failed: $e")
                }

                try {
                    presetReverb = android.media.audiofx.PresetReverb(0, activeSessionId)
                    android.util.Log.d("AURA-3D", "PresetReverb created successfully on session $activeSessionId")
                } catch (e: Exception) {
                    android.util.Log.w("AURA-3D", "PresetReverb creation failed: $e")
                }
            }

            // Apply 3D Virtualizer
            virtualizer?.let { v ->
                v.enabled = enabled
                if (enabled) {
                    if (v.strengthSupported) {
                        val s = (strength.coerceIn(0f, 1f) * 1000).toInt().toShort()
                        v.setStrength(s)
                        android.util.Log.d("AURA-3D", "Virtualizer strength set to $s")
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        try {
                            v.forceVirtualizationMode(android.media.audiofx.Virtualizer.VIRTUALIZATION_MODE_BINAURAL)
                            android.util.Log.d("AURA-3D", "Virtualizer mode set to BINAURAL")
                        } catch (_: Exception) {
                            try {
                                v.forceVirtualizationMode(android.media.audiofx.Virtualizer.VIRTUALIZATION_MODE_TRANSAURAL)
                                android.util.Log.d("AURA-3D", "Virtualizer mode set to TRANSAURAL fallback")
                            } catch (_: Exception) {}
                        }
                    }
                }
            }

            // Apply Bass Boost & Reverb based on preset mode for rich spatial presence
            bassBoost?.let { bb ->
                bb.enabled = enabled
                if (enabled && bb.strengthSupported) {
                    val boostStrength: Short = when (mode) {
                        "Bass Surround 3D" -> ((strength * 800).coerceIn(0f, 1000f)).toInt().toShort()
                        "Concert Hall" -> ((strength * 450).coerceIn(0f, 1000f)).toInt().toShort()
                        "Wide Room" -> ((strength * 250).coerceIn(0f, 1000f)).toInt().toShort()
                        else -> 0
                    }
                    bb.setStrength(boostStrength)
                    android.util.Log.d("AURA-3D", "BassBoost strength set to $boostStrength for $mode")
                }
            }

            presetReverb?.let { pr ->
                pr.enabled = enabled
                if (enabled) {
                    val reverbPreset: Short = when (mode) {
                        "Concert Hall" -> android.media.audiofx.PresetReverb.PRESET_LARGEHALL
                        "Wide Room" -> android.media.audiofx.PresetReverb.PRESET_LARGEROOM
                        "Bass Surround 3D" -> android.media.audiofx.PresetReverb.PRESET_MEDIUMHALL
                        "Subtle Headstage" -> android.media.audiofx.PresetReverb.PRESET_SMALLROOM
                        else -> android.media.audiofx.PresetReverb.PRESET_NONE
                    }
                    try {
                        pr.preset = reverbPreset
                        android.util.Log.d("AURA-3D", "PresetReverb preset set to $reverbPreset for $mode")
                    } catch (_: Exception) {}
                }
            }

            true
        } catch (e: Exception) {
            android.util.Log.e("AURA-3D", "Error applying 3D sound: $e")
            e.printStackTrace()
            false
        }
    }
}

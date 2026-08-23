package com.example.music_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
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

    private val routeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            intent?.action?.let { action ->
                if (action == Intent.ACTION_HEADSET_PLUG ||
                    action == AudioManager.ACTION_AUDIO_BECOMING_NOISY ||
                    action == "android.bluetooth.adapter.action.STATE_CHANGED" ||
                    action == "android.bluetooth.device.action.ACL_CONNECTED" ||
                    action == "android.bluetooth.device.action.ACL_DISCONNECTED") {
                    
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context?.registerReceiver(routeReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            context?.registerReceiver(routeReceiver, filter)
        }
    }

    private fun unregisterReceivers() {
        try {
            context?.unregisterReceiver(routeReceiver)
        } catch (_: Exception) {}
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getAvailableAudioOutputs" -> {
                val devices = getAvailableAudioOutputs()
                result.success(devices)
            }
            "selectAudioOutput" -> {
                val deviceId = call.argument<Int>("id")
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

            // Filter out earpiece, telephony, and internal line output nodes for media audio
            val validDevices = devices.filter { dev ->
                val type = dev.type
                type != AudioDeviceInfo.TYPE_BUILTIN_EARPIECE &&
                type != AudioDeviceInfo.TYPE_TELEPHONY &&
                type != AudioDeviceInfo.TYPE_AUX_LINE &&
                type != AudioDeviceInfo.TYPE_LINE_ANALOG &&
                type != AudioDeviceInfo.TYPE_LINE_DIGITAL &&
                getDeviceTypeName(type) != "unknown"
            }

            val hasExternalHeadsetOrBt = validDevices.any { 
                it.type != AudioDeviceInfo.TYPE_BUILTIN_SPEAKER 
            }

            for (dev in validDevices) {
                val typeName = getDeviceTypeName(dev.type)
                val isSpeaker = dev.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER

                val isCurrent = if (currentCommunicationDevice != null) {
                    dev.id == currentCommunicationDevice.id
                } else if (am.isSpeakerphoneOn && am.mode == AudioManager.MODE_IN_COMMUNICATION) {
                    isSpeaker
                } else {
                    if (hasExternalHeadsetOrBt) {
                        !isSpeaker
                    } else {
                        isSpeaker
                    }
                }

                var name = dev.productName.toString()
                if (name.isBlank() || name.lowercase().contains("builtin") || name.lowercase().contains("built-in")) {
                    name = when (dev.type) {
                        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "Built-in Speaker"
                        AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "Headphones / Headset"
                        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth Audio"
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
            // Fallback for older devices
            val isSpeaker = am.isSpeakerphoneOn
            list.add(mapOf(
                "id" to 1,
                "name" to "Built-in Speaker",
                "type" to "speaker",
                "isActive" to isSpeaker
            ))
        }

        return list
    }

    private fun setAudioOutput(deviceId: Int?, typeStr: String?): Boolean {
        val am = audioManager ?: return false

        try {
            if (typeStr == "speaker") {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val devices = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                    val target = devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                    if (target != null) {
                        am.setCommunicationDevice(target)
                    }
                }
                am.mode = AudioManager.MODE_IN_COMMUNICATION
                am.isSpeakerphoneOn = true
                if (am.isBluetoothScoOn) {
                    am.stopBluetoothSco()
                    am.isBluetoothScoOn = false
                }
                return true
            } else {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    if (deviceId != null) {
                        val devices = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                        val target = devices.firstOrNull { it.id == deviceId }
                        if (target != null && target.type != AudioDeviceInfo.TYPE_BUILTIN_SPEAKER) {
                            am.setCommunicationDevice(target)
                        } else {
                            am.clearCommunicationDevice()
                        }
                    } else {
                        am.clearCommunicationDevice()
                    }
                }
                am.isSpeakerphoneOn = false
                am.mode = AudioManager.MODE_NORMAL
                if (am.isBluetoothScoOn) {
                    am.stopBluetoothSco()
                    am.isBluetoothScoOn = false
                }
                return true
            }
        } catch (e: Exception) {
            return false
        }
    }

    private fun resetRoute(): Boolean {
        val am = audioManager ?: return false
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
            return true
        } catch (e: Exception) {
            return false
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
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
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
}

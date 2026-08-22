import Flutter
import UIKit
import AVFoundation
import AVKit

public class AudioRoutingPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = AudioRoutingPlugin()
        let channel = FlutterMethodChannel(name: "com.example.music_app/audio_routing", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: channel)

        let eventChannel = FlutterEventChannel(name: "com.example.music_app/audio_routing_events", binaryMessenger: registrar.messenger())
        eventChannel.setStreamHandler(instance)

        let pickerFactory = AVRoutePickerViewFactory(messenger: registrar.messenger())
        registrar.register(pickerFactory, withId: "com.example.music_app/av_route_picker_view")

        instance.setupNotificationObservers()
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleRouteChange(notification: Notification) {
        sendRouteUpdate()
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getAvailableAudioOutputs":
            result(getAvailableAudioOutputs())
        case "selectAudioOutput":
            let args = call.arguments as? [String: Any]
            let typeStr = args?["type"] as? String
            let success = setAudioOutput(typeStr: typeStr)
            sendRouteUpdate()
            result(success)
        case "resetToDefaultRoute":
            let success = setAudioOutput(typeStr: "none")
            sendRouteUpdate()
            result(success)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func getAvailableAudioOutputs() -> [[String: Any]] {
        var list: [[String: Any]] = []
        let session = AVAudioSession.sharedInstance()
        let currentRoute = session.currentRoute

        let activePortTypes = Set(currentRoute.outputs.map { $0.portType })

        // Built-in Speaker
        let isSpeakerActive = activePortTypes.contains(.builtInSpeaker)
        list.append([
            "id": "speaker",
            "name": "iPhone Speaker",
            "type": "speaker",
            "isActive": isSpeakerActive
        ])

        // Headphones / Earphones if connected
        if let availableInputs = session.availableInputs {
            for input in availableInputs {
                if input.portType == .headphones || input.portType == .headset || input.portType == .bluetoothHFP {
                    let isActive = activePortTypes.contains(input.portType)
                    list.append([
                        "id": input.uid,
                        "name": input.portName,
                        "type": input.portType == .bluetoothHFP ? "bluetooth" : "headset",
                        "isActive": isActive
                    ])
                }
            }
        }

        // Active output ports (AirPlay, Bluetooth A2DP, etc.)
        for output in currentRoute.outputs {
            let typeName: String
            switch output.portType {
            case .builtInSpeaker:
                typeName = "speaker"
            case .builtInReceiver:
                typeName = "earpiece"
            case .headphones, .headset:
                typeName = "headset"
            case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
                typeName = "bluetooth"
            case .airPlay:
                typeName = "airplay"
            default:
                typeName = "unknown"
            }

            if output.portType != .builtInSpeaker {
                list.append([
                    "id": output.uid,
                    "name": output.portName,
                    "type": typeName,
                    "isActive": true
                ])
            }
        }

        return list
    }

    private func setAudioOutput(typeStr: String?) -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            if typeStr == "speaker" {
                try session.overrideOutputAudioPort(.speaker)
            } else {
                try session.overrideOutputAudioPort(.none)
            }
            return true
        } catch {
            print("[AUDIO-ROUTING-IOS] Override output port error: \(error)")
            return false
        }
    }

    private func sendRouteUpdate() {
        let outputs = getAvailableAudioOutputs()
        eventSink?(outputs)
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        sendRouteUpdate()
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}

// ── Native AVRoutePickerView Platform View ────────────────────────

class AVRoutePickerViewFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return AVRoutePickerViewNative(frame: frame, viewId: viewId, messenger: messenger)
    }
}

class AVRoutePickerViewNative: NSObject, FlutterPlatformView {
    private var routePickerView: AVRoutePickerView

    init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
        routePickerView = AVRoutePickerView(frame: frame)
        routePickerView.activeTintColor = .systemBlue
        routePickerView.tintColor = .white
        routePickerView.prioritizesVideoDevices = false
        super.init()
    }

    func view() -> UIView {
        return routePickerView
    }
}

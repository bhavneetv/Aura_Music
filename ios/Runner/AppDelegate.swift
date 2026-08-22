import Flutter
import UIKit
import AVFoundation
import Intents

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let channelName = "com.example.music_app/voice_assistant"
  private let appGroupId = "group.com.example.musicApp"
  private var voiceChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP])
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("Failed to set AVAudioSession category: \(error)")
    }

    let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
    voiceChannel = FlutterMethodChannel(name: channelName, binaryMessenger: controller.binaryMessenger)

    voiceChannel?.setMethodCallHandler({ [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self else { return }
      if call.method == "syncLibraryIndex" {
        if let args = call.arguments as? [String: Any], let jsonStr = args["json"] as? String {
          let success = self.writeLibraryIndexToAppGroup(jsonStr: jsonStr)
          result(success)
        } else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "JSON required", details: nil))
        }
      } else if call.method == "donateMediaItem" {
        if let args = call.arguments as? [String: Any] {
          self.donateMediaIntent(args: args)
          result(true)
        } else {
          result(false)
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    })

    GeneratedPluginRegistrant.register(with: self)

    // Check for pending Siri queries stored in shared App Group defaults
    checkPendingSiriQuery()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    if let intent = userActivity.interaction?.intent as? INPlayMediaIntent {
      let query = intent.mediaSearch?.mediaName ?? intent.mediaContainer?.name ?? ""
      if !query.isEmpty {
        sendVoiceQueryToFlutter(query: query)
        return true
      }
    } else if userActivity.activityType == "INPlayMediaIntent", let query = userActivity.userInfo?["query"] as? String {
      sendVoiceQueryToFlutter(query: query)
      return true
    }
    return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
  }

  private func writeLibraryIndexToAppGroup(jsonStr: String) -> Bool {
    guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
      return false
    }
    let fileURL = containerURL.appendingPathComponent("library_index.json")
    do {
      try jsonStr.write(to: fileURL, atomically: true, encoding: .utf8)
      return true
    } catch {
      print("Failed to write library index to App Group: \(error)")
      return false
    }
  }

  private func donateMediaIntent(args: [String: Any]) {
    let intent = INPlayMediaIntent()
    let title = args["title"] as? String ?? ""
    let artist = args["artist"] as? String ?? ""
    
    let search = INMediaSearch(
      mediaType: .song,
      sortOrder: .best,
      mediaName: title,
      artistName: artist,
      albumName: args["album"] as? String,
      genreName: args["genre"] as? String,
      moodName: nil,
      releaseDate: nil,
      reference: nil,
      mediaIdentifier: args["id"] as? String
    )
    intent.mediaSearch = search
    
    let interaction = INInteraction(intent: intent, response: nil)
    interaction.donate { error in
      if let error = error {
        print("Siri media donation error: \(error)")
      }
    }
  }

  private func checkPendingSiriQuery() {
    if let sharedDefaults = UserDefaults(suiteName: appGroupId),
       let query = sharedDefaults.string(forKey: "pending_siri_query"),
       !query.isEmpty {
      let timestamp = sharedDefaults.double(forKey: "pending_siri_timestamp")
      if Date().timeIntervalSince1970 - timestamp < 300 { // within 5 mins
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
          self?.sendVoiceQueryToFlutter(query: query)
        }
      }
      sharedDefaults.removeObject(forKey: "pending_siri_query")
      sharedDefaults.synchronize()
    }
  }

  private func sendVoiceQueryToFlutter(query: String) {
    voiceChannel?.invokeMethod("onVoiceQuery", ["query": query])
  }
}

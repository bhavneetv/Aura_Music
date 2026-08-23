import UIKit
import Flutter
import Intents

@main
@objc class AppDelegate: FlutterAppDelegate, INPlayMediaIntentHandling, INSearchForMediaIntentHandling {
  private let appGroupId = "group.com.example.musicApp"
  private var voiceChannel: FlutterMethodChannel?
  private var siriChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    
    let mainChannel = FlutterMethodChannel(
      name: "com.example.music_app/voice_assistant",
      binaryMessenger: controller.binaryMessenger
    )
    voiceChannel = mainChannel

    let secondaryChannel = FlutterMethodChannel(
      name: "com.example.music_app/siri",
      binaryMessenger: controller.binaryMessenger
    )
    siriChannel = secondaryChannel

    let handler: FlutterMethodCallHandler = { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self else { return }
      if call.method == "updateLibraryIndex" || call.method == "syncLibraryIndex" {
        if let args = call.arguments as? [String: Any], let jsonStr = args["json"] as? String {
          let success = self.writeLibraryIndexToAppGroup(jsonStr: jsonStr)
          result(success)
        } else {
          result(false)
        }
      } else if call.method == "donateMediaIntent" || call.method == "donateMediaItem" {
        if let args = call.arguments as? [String: Any] {
          self.donateMediaIntent(args: args)
          result(true)
        } else {
          result(false)
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    mainChannel.setMethodCallHandler(handler)
    secondaryChannel.setMethodCallHandler(handler)

    GeneratedPluginRegistrant.register(with: self)
    if let registrar = self.registrar(forPlugin: "AudioRoutingPlugin") {
      AudioRoutingPlugin.register(with: registrar)
    }

    // Request Siri permission safely on background thread (prevents launch crash on sideloaded profiles without Siri entitlement)
    DispatchQueue.global(qos: .utility).async {
      INPreferences.requestSiriAuthorization { status in
        print("[AURA-SIRI] Siri authorization status: \(status.rawValue)")
      }
    }

    // Check for pending Siri queries stored in shared App Group defaults
    checkPendingSiriQuery()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // ── Handle Siri Media Intents Directly ──────────────────────────────────────

  override func application(
    _ application: UIApplication,
    handle intent: INIntent,
    completionHandler: @escaping (INIntentResponse) -> Void
  ) {
    if let playIntent = intent as? INPlayMediaIntent {
      var query = extractQueryFromMediaIntent(playIntent)
      if query.isEmpty {
        query = "play music"
      }
      sendVoiceQueryToFlutter(query: query)
      let response = INPlayMediaIntentResponse(code: .success, userActivity: nil)
      completionHandler(response)
    } else if let searchIntent = intent as? INSearchForMediaIntent {
      var query = extractQueryFromSearchIntent(searchIntent)
      if query.isEmpty { query = "play music" }
      sendVoiceQueryToFlutter(query: query)
      let response = INSearchForMediaIntentResponse(code: .success, userActivity: nil)
      completionHandler(response)
    } else {
      completionHandler(INPlayMediaIntentResponse(code: .success, userActivity: nil))
    }
  }

  // Protocol conformance: INPlayMediaIntentHandling
  func handle(intent: INPlayMediaIntent, completion: @escaping (INPlayMediaIntentResponse) -> Void) {
    var query = extractQueryFromMediaIntent(intent)
    if query.isEmpty { query = "play music" }
    sendVoiceQueryToFlutter(query: query)
    completion(INPlayMediaIntentResponse(code: .success, userActivity: nil))
  }

  // Protocol conformance: INSearchForMediaIntentHandling
  func handle(intent: INSearchForMediaIntent, completion: @escaping (INSearchForMediaIntentResponse) -> Void) {
    var query = extractQueryFromSearchIntent(intent)
    if query.isEmpty { query = "play music" }
    sendVoiceQueryToFlutter(query: query)
    completion(INSearchForMediaIntentResponse(code: .success, userActivity: nil))
  }

  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    if let intent = userActivity.interaction?.intent as? INPlayMediaIntent {
      var query = extractQueryFromMediaIntent(intent)
      if query.isEmpty {
        query = "play music"
      }
      sendVoiceQueryToFlutter(query: query)
      return true
    } else if userActivity.activityType == "INPlayMediaIntent" || userActivity.activityType == "INSearchForMediaIntent" {
      let query = userActivity.userInfo?["query"] as? String ?? "play music"
      sendVoiceQueryToFlutter(query: query)
      return true
    }
    return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    let urlString = url.absoluteString
    if url.scheme == "aura" || url.scheme == "aura-playlist" || url.scheme == "auramusic" {
      if let components = URLComponents(url: url, resolvingAgainstBaseURL: true) {
        if let queryItem = components.queryItems?.first(where: { $0.name == "query" || $0.name == "q" }),
           let queryValue = queryItem.value, !queryValue.isEmpty {
          sendVoiceQueryToFlutter(query: queryValue)
          return true
        }
      }
      voiceChannel?.invokeMethod("onDeepLink", arguments: ["link": urlString])
      siriChannel?.invokeMethod("onDeepLink", arguments: ["link": urlString])
      return true
    }
    return super.application(app, open: url, options: options)
  }

  private func extractQueryFromMediaSearch(_ mediaSearch: INMediaSearch?) -> String {
    guard let mediaSearch = mediaSearch else { return "" }
    if let mediaName = mediaSearch.mediaName, !mediaName.isEmpty {
      return mediaName
    }
    if let artistName = mediaSearch.artistName, !artistName.isEmpty {
      return artistName
    }
    if let genre = mediaSearch.genreNames?.first, !genre.isEmpty {
      return "\(genre) song"
    }
    if let albumName = mediaSearch.albumName, !albumName.isEmpty {
      return albumName
    }
    return ""
  }

  private func extractQueryFromMediaIntent(_ intent: INPlayMediaIntent) -> String {
    let query = extractQueryFromMediaSearch(intent.mediaSearch)
    if !query.isEmpty { return query }
    if let container = intent.mediaContainer, let title = container.title, !title.isEmpty {
      return title
    }
    return ""
  }

  private func extractQueryFromSearchIntent(_ intent: INSearchForMediaIntent) -> String {
    let query = extractQueryFromMediaSearch(intent.mediaSearch)
    if !query.isEmpty { return query }
    if let item = intent.mediaItems?.first, let title = item.title, !title.isEmpty {
      return title
    }
    return ""
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
    let title = args["title"] as? String ?? ""
    let artist = args["artist"] as? String ?? ""
    
    let search = INMediaSearch(
      mediaType: .song,
      sortOrder: .best,
      mediaName: title,
      artistName: artist,
      albumName: args["album"] as? String,
      genreNames: (args["genre"] as? String).map { [$0] },
      moodNames: nil,
      releaseDate: nil,
      reference: .unknown,
      mediaIdentifier: args["id"] as? String
    )
    let intent = INPlayMediaIntent(
      mediaItems: nil,
      mediaContainer: nil,
      playShuffled: nil,
      playbackRepeatMode: .unknown,
      resumePlayback: nil,
      playbackQueueLocation: .unknown,
      playbackSpeed: nil,
      mediaSearch: search
    )
    
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
    let args = ["query": query]
    voiceChannel?.invokeMethod("onVoiceQuery", arguments: args)
    siriChannel?.invokeMethod("onVoiceQuery", arguments: args)
  }
}

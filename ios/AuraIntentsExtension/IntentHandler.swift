import Intents
import Foundation

class IntentHandler: INExtension, INPlayMediaIntentHandling {

    private let appGroupId = "group.com.example.musicApp"

    override func handler(for intent: INIntent) -> Any {
        guard intent is INPlayMediaIntent else {
            return self
        }
        return self
    }

    // ── 1. Resolve Media Items ───────────────────────────────────

    func resolveMediaItems(for intent: INPlayMediaIntent, with completion: @escaping ([INPlayMediaMediaItemResolutionResult]) -> Void) {
        let query = extractQuery(from: intent)
        
        guard let items = loadLocalLibraryIndex() else {
            // Default success if library index unavailable
            let fallbackItem = INMediaItem(
                identifier: "default_library",
                title: "Aura Library",
                type: .music,
                artwork: nil
            )
            completion([.success(with: fallbackItem)])
            return
        }

        if query.isEmpty {
            // "Play music on Aura" -> Return first item or library placeholder
            let mediaItem = INMediaItem(
                identifier: items.first?["id"] as? String ?? "library",
                title: items.first?["title"] as? String ?? "Aura Music",
                type: .music,
                artwork: nil
            )
            completion([.success(with: mediaItem)])
            return
        }

        // Fuzzy match locally cached index items
        var bestScore: Double = 0.0
        var bestItemMap: [String: Any]? = nil

        for item in items {
            let title = (item["title"] as? String) ?? ""
            let artist = (item["artist"] as? String) ?? ""
            let album = (item["album"] as? String) ?? ""

            let score = max(
                calculateMatchScore(query: query, target: title),
                max(
                    calculateMatchScore(query: query, target: artist),
                    calculateMatchScore(query: query, target: "\(title) \(artist)")
                )
            )

            if score > bestScore {
                bestScore = score
                bestItemMap = item
            }
        }

        if bestScore >= 0.4, let matched = bestItemMap {
            let mediaItem = INMediaItem(
                identifier: (matched["id"] as? String) ?? "matched",
                title: (matched["title"] as? String) ?? query,
                type: .song,
                artwork: nil,
                artist: matched["artist"] as? String
            )
            completion([.success(with: mediaItem)])
        } else {
            // Graceful fallback resolution
            completion([.unsupported(forReason: .noMatchingMediaItem)])
        }
    }

    // ── 2. Confirm Playback ──────────────────────────────────────

    func confirm(intent: INPlayMediaIntent, completion: @escaping (INPlayMediaIntentResponse) -> Void) {
        let response = INPlayMediaIntentResponse(code: .ready, userActivity: nil)
        completion(response)
    }

    // ── 3. Handle Playback Handoff ───────────────────────────────

    func handle(intent: INPlayMediaIntent, completion: @escaping (INPlayMediaIntentResponse) -> Void) {
        let query = extractQuery(from: intent)

        // Store query in App Group shared defaults for main app pickup
        if let sharedDefaults = UserDefaults(suiteName: appGroupId) {
            sharedDefaults.set(query, forKey: "pending_siri_query")
            sharedDefaults.set(Date().timeIntervalSince1970, forKey: "pending_siri_timestamp")
            sharedDefaults.synchronize()
        }

        let userActivity = NSUserActivity(activityType: "INPlayMediaIntent")
        userActivity.userInfo = ["query": query]

        let response = INPlayMediaIntentResponse(code: .handleInApp, userActivity: userActivity)
        completion(response)
    }

    // ── Helpers ──────────────────────────────────────────────────

    private func extractQuery(from intent: INPlayMediaIntent) -> String {
        if let mediaName = intent.mediaSearch?.mediaName, !mediaName.isEmpty {
            return mediaName
        }
        if let containerName = intent.mediaContainer?.name, !containerName.isEmpty {
            return containerName
        }
        if let artistName = intent.mediaSearch?.artistName, !artistName.isEmpty {
            return artistName
        }
        if let albumName = intent.mediaSearch?.albumName, !albumName.isEmpty {
            return albumName
        }
        return ""
    }

    private func loadLocalLibraryIndex() -> [[String: Any]]? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            return nil
        }
        let fileURL = containerURL.appendingPathComponent("library_index.json")
        guard let data = try? Data(contentsOf: fileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            return nil
        }
        return items
    }

    private func calculateMatchScore(query: String, target: String) -> Double {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let t = target.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty || t.isEmpty { return 0.0 }
        if q == t { return 1.0 }
        if t.hasPrefix(q) { return 0.9 }
        if t.contains(q) { return 0.8 }
        return 0.0
    }
}

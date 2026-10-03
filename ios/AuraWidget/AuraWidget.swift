import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline Entry
struct MusicEntry: TimelineEntry {
    let date: Date
    let title: String
    let artist: String
    let isPlaying: String // "true" or "false"
    let artPath: String
}

// MARK: - Timeline Provider
struct AuraTimelineProvider: TimelineProvider {
    typealias Entry = MusicEntry

    func placeholder(in context: Context) -> MusicEntry {
        MusicEntry(
            date: Date(),
            title: "Aura Music",
            artist: "Tap to play",
            isPlaying: "false",
            artPath: ""
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (MusicEntry) -> Void) {
        completion(fetchCurrentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MusicEntry>) -> Void) {
        let entry = fetchCurrentEntry()
        let timeline = Timeline(entries: [entry], policy: .atEnd)
        completion(timeline)
    }

    private func fetchCurrentEntry() -> MusicEntry {
        let userDefaults = UserDefaults(suiteName: "group.com.example.musicApp")
        let title = userDefaults?.string(forKey: "flutter.track_title") 
            ?? userDefaults?.string(forKey: "track_title") ?? "Aura Music"
        let artist = userDefaults?.string(forKey: "flutter.track_artist") 
            ?? userDefaults?.string(forKey: "track_artist") ?? "Tap to play music"
        let isPlaying = userDefaults?.string(forKey: "flutter.is_playing") 
            ?? (userDefaults?.bool(forKey: "flutter.is_playing") == true ? "true" : "false")
        let artPath = userDefaults?.string(forKey: "flutter.track_art_path") 
            ?? userDefaults?.string(forKey: "track_art_path") ?? ""

        return MusicEntry(
            date: Date(),
            title: title,
            artist: artist,
            isPlaying: isPlaying,
            artPath: artPath
        )
    }
}

// MARK: - AppIntents for iOS 17+ Interactive Buttons
@available(iOS 17.0, *)
struct TogglePlayIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Play or Pause"
    static var description = IntentDescription("Toggles music playback in Aura")

    func perform() async throws -> some IntentResult {
        let userDefaults = UserDefaults(suiteName: "group.com.example.musicApp")
        let currentlyPlaying = userDefaults?.string(forKey: "flutter.is_playing") == "true"
        userDefaults?.setValue(!currentlyPlaying ? "true" : "false", forKey: "flutter.is_playing")
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

@available(iOS 17.0, *)
struct NextTrackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Next Track"
    static var description = IntentDescription("Skips to next track in Aura")

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

@available(iOS 17.0, *)
struct PreviousTrackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Previous Track"
    static var description = IntentDescription("Skips to previous track in Aura")

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Widget View (Medium - 4x2 style)
struct AuraWidgetEntryView: View {
    var entry: AuraTimelineProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        ZStack {
            // Material dark glass background
            Color(red: 0.11, green: 0.11, blue: 0.13)
                .edgesIgnoringSafeArea(.all)

            HStack(spacing: 14) {
                // Album Art / App Icon
                Group {
                    if let image = loadAlbumArt(path: entry.artPath) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            LinearGradient(
                                colors: [Color(red: 0.42, green: 0.36, blue: 0.91), Color(red: 0.25, green: 0.21, blue: 0.65)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: "music.note")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .frame(width: 64, height: 64)
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 3)

                // Track Metadata
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(entry.artist)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.7))
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(entry.isPlaying == "true" ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text(entry.isPlaying == "true" ? "Now Playing" : "Paused")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.6))
                    }
                    .padding(.top, 2)
                }

                Spacer()

                // Interactive Controls
                HStack(spacing: 8) {
                    // Previous
                    if #available(iOS 17.0, *) {
                        Button(intent: PreviousTrackIntent()) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Link(destination: URL(string: "aura://action/prev")!) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Circle())
                        }
                    }

                    // Play/Pause
                    if #available(iOS 17.0, *) {
                        Button(intent: TogglePlayIntent()) {
                            Image(systemName: entry.isPlaying == "true" ? "pause.fill" : "play.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(
                                    LinearGradient(
                                        colors: [Color(red: 0.48, green: 0.30, blue: 1.0), Color(red: 0.35, green: 0.15, blue: 0.9)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Link(destination: URL(string: "aura://action/play_pause")!) {
                            Image(systemName: entry.isPlaying == "true" ? "pause.fill" : "play.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.purple)
                                .clipShape(Circle())
                        }
                    }

                    // Next
                    if #available(iOS 17.0, *) {
                        Button(intent: NextTrackIntent()) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Link(destination: URL(string: "aura://action/next")!) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Circle())
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .widgetURL(URL(string: "aura://now-playing"))
    }

    private func loadAlbumArt(path: String) -> UIImage? {
        guard !path.isEmpty else { return nil }
        return UIImage(contentsOfFile: path)
    }
}

// MARK: - Widget Configuration
struct AuraWidget: Widget {
    let kind: String = "AuraWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AuraTimelineProvider()) { entry in
            AuraWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Aura Player")
        .description("Interactive Now Playing widget with playback controls.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

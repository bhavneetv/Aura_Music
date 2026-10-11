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
            artist: "Tap to play music",
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

    @ViewBuilder
    var body: some View {
        if #available(iOS 17.0, *) {
            widgetContent
                .containerBackground(Color(red: 0.09, green: 0.09, blue: 0.11), for: .widget)
                .widgetURL(URL(string: "aura://now-playing"))
        } else {
            ZStack {
                Color(red: 0.09, green: 0.09, blue: 0.11)
                    .edgesIgnoringSafeArea(.all)
                widgetContent
            }
            .widgetURL(URL(string: "aura://now-playing"))
        }
    }

    private var widgetContent: some View {
        HStack(spacing: 12) {
            // Album Art / Vinyl Artwork
            Group {
                if let image = loadAlbumArt(path: entry.artPath) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    // Sleek dark luxury vinyl disc fallback
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.14, green: 0.14, blue: 0.17),
                                        Color(red: 0.08, green: 0.08, blue: 0.10)
                                    ]),
                                    center: .center,
                                    startRadius: 5,
                                    endRadius: 36
                                )
                            )
                        Circle()
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                            .frame(width: 56, height: 56)
                        Circle()
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                            .frame(width: 42, height: 42)
                        Circle()
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                            .frame(width: 28, height: 28)
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.49, green: 0.23, blue: 0.93),
                                        Color(red: 0.35, green: 0.15, blue: 0.75)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 24, height: 24)
                        Circle()
                            .fill(Color(red: 0.08, green: 0.08, blue: 0.10))
                            .frame(width: 8, height: 8)
                    }
                }
            }
            .frame(width: 72, height: 72)
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 3)

            // Track Metadata
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(entry.artist)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.7))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Circle()
                        .fill(entry.isPlaying == "true" ? Color(red: 0.65, green: 0.55, blue: 0.98) : Color.white.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Text(entry.isPlaying == "true" ? "Playing" : "Paused")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(entry.isPlaying == "true" ? Color(red: 0.65, green: 0.55, blue: 0.98) : Color.white.opacity(0.5))
                }
                .padding(.top, 2)
            }

            Spacer()

            // Interactive Playback Controls
            HStack(spacing: 7) {
                // Previous
                if #available(iOS 17.0, *) {
                    Button(intent: PreviousTrackIntent()) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Link(destination: URL(string: "aura://action/prev")!) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 13, weight: .semibold))
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
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.49, green: 0.23, blue: 0.93),
                                        Color(red: 0.38, green: 0.15, blue: 0.85)
                                    ],
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
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.49, green: 0.23, blue: 0.93),
                                        Color(red: 0.38, green: 0.15, blue: 0.85)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(Circle())
                    }
                }

                // Next
                if #available(iOS 17.0, *) {
                    Button(intent: NextTrackIntent()) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Link(destination: URL(string: "aura://action/next")!) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func loadAlbumArt(path: String) -> UIImage? {
        guard !path.isEmpty else { return nil }
        if let direct = UIImage(contentsOfFile: path) {
            return direct
        }
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.example.musicApp") {
            let filename = URL(fileURLWithPath: path).lastPathComponent
            let groupPath = containerURL.appendingPathComponent("home_widget").appendingPathComponent(filename).path
            if let groupImg = UIImage(contentsOfFile: groupPath) {
                return groupImg
            }
            let directContainerPath = containerURL.appendingPathComponent(filename).path
            if let directImg = UIImage(contentsOfFile: directContainerPath) {
                return directImg
            }
        }
        return nil
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

# PRD.md — Build Instructions for AI Coding Agent

**Product:** Vinyl — Premium Cross-Platform Music Player
**Target platforms:** Android + iOS, single Flutter codebase
**Scope of this document:** UI, playback, animations, haptics, and a free music API integration only.
**Explicitly out of scope:** authentication, backend/server logic, and any database. Build this as a **local, client-only app** — no login screens, no user accounts, no Postgres/Supabase, no sync. All state (favorites, downloads, settings, recently played) is stored **on-device only** using local storage (`shared_preferences` for simple flags, `Isar` or `sqflite` for lists/tables like favorites and history).

Follow this document top to bottom. Where a decision isn't specified, choose the simplest option that keeps the app fully working offline-first and dependency-free of any backend.

---

## 1. What to build

A minimal, elegant, animated music player app with:
- A Home screen with trending/new/genre rails pulled from a free music API.
- Search.
- A Library (Favorites, Downloads, History, Playlists — all stored locally on the device).
- A Now Playing screen with 4 switchable visual styles: **Vinyl, CD, Cassette, Minimal**.
- Full playback transport (play/pause/next/prev/seek/shuffle/repeat/speed/sleep timer).
- Background/lock-screen playback.
- Downloads for offline playback.
- Haptic feedback on virtually every interactive action.
- Dark Mode and Light Mode, glassmorphism, rounded cards, Material 3 styling.

No sign-up, no sign-in, no cloud sync. Everything works standalone from first launch.

---

## 2. Tech stack (use exactly this unless a package is unmaintained/broken)

| Concern | Package |
|---|---|
| Framework | Flutter (stable, Dart ≥ 3.3) |
| State management | `flutter_riverpod` |
| Local storage (settings, flags) | `shared_preferences` |
| Local storage (favorites/downloads/history/playlists lists) | `isar` (preferred) or `sqflite` |
| Audio engine | `just_audio` |
| Background playback / lock screen | `audio_service` |
| Networking | `dio` |
| Connectivity check | `connectivity_plus` |
| HTTP/file caching | `flutter_cache_manager` |
| Image caching | `cached_network_image` |
| Local notifications (download complete) | `flutter_local_notifications` |
| Animation | Flutter's built-in `AnimationController`/implicit widgets + `lottie` for loaders/onboarding |
| Haptics | `HapticFeedback` (`flutter/services.dart`) + `vibration` package for richer Android patterns |
| Routing | `go_router` |
| Fonts | `google_fonts` (bundle a local fallback font for offline builds) |
| Dominant-color theming | `palette_generator` |
| Sharing | `share_plus` |

Do not add Supabase, Firebase Auth, or any auth/session package. Do not create a `users` table or any server schema.

---

## 3. Free Music API — use Jamendo

Use the **Jamendo API** (`https://api.jamendo.com/v3.0`) as the sole music data source for v1. It's free (self-serve `client_id`, no OAuth needed for catalog reads), the tracks are Creative-Commons licensed (safe to stream/download), and it returns everything needed: search, albums, artists, playlists, genres/tags, artwork, and direct streaming URLs.

### 3.1 Getting a client_id
Get a free `client_id` at `https://devportal.jamendo.com/`. Pass it as a query param on every request (`client_id=...`). Store it via `--dart-define=JAMENDO_CLIENT_ID=xxxx` at build time — never hard-code it in source.

### 3.2 Endpoints to implement

| Need | Endpoint |
|---|---|
| Search tracks | `GET /tracks/?search=<q>&client_id=...&format=json&limit=30&include=musicinfo` |
| Trending | `GET /tracks/?order=popularity_week&client_id=...` |
| New releases | `GET /tracks/?order=releasedate_desc&client_id=...` |
| Album detail + tracks | `GET /albums/tracks/?id=<albumId>&client_id=...` |
| Artist top tracks | `GET /artists/tracks/?id=<artistId>&client_id=...` |
| Playlists | `GET /playlists/tracks/?id=<playlistId>&client_id=...` |
| Genres/tags (for genre rail + filters) | `GET /autocomplete/?entity=tags&client_id=...` |

Each track object returned already includes:
- `audio` → direct streaming MP3 URL (use `audioformat=mp32` for ~192kbps). Feed this straight into `just_audio` as the source — no extra signing/token step.
- `image` / `album_image` → artwork URL, request larger sizes with `imagesize=300` etc.
- `musicinfo.tags.genres` → genre tags for the Genre/Mood rails.

### 3.3 Make it swappable

Define one interface, `MusicSource`, with methods: `search`, `trending`, `newReleases`, `getArtistTopTracks`, `getAlbumTracks`, `getGenres`. Implement `JamendoSource implements MusicSource`. **Every screen and provider must depend on `MusicSource`, never on `JamendoSource` or `Dio` directly** — so a different free API (Free Music Archive, Internet Archive Audio, Openverse) or a future paid catalog can be swapped in later by writing one new class and changing a single provider binding.

### 3.4 Client-side "recommendations" (no backend needed)

Since there's no server, build a simple **on-device** recommender: keep a local tally (Isar/`shared_preferences`) of genre tags from the last ~20 played tracks, then call `search`/`trending` filtered by the user's top 2–3 genres. New users with no history just see `trending()` results. This requires no backend and no database server — it's a local heuristic only.

---

## 4. Screens to build

Build these as real, navigable screens (use `go_router`):

1. **Splash** — brief brand animation, then goes straight to Home (no auth check).
2. **Onboarding** — 3–4 swipeable intro pages, shown only on first launch (flag in `shared_preferences`), skip button, ends at Home.
3. **Home** — rails: Continue Listening, Recently Played, Trending, Recommended, New Releases, Genres/Moods, Favorites preview, Downloads preview. Pull-to-refresh.
4. **Search** — search field, tabs (Songs/Albums/Artists/Playlists), recent searches (local), trending searches (static curated list is fine), filter sheet (genre/duration/year/sort).
5. **Album Detail** — artwork header, Play All / Shuffle, track list, Download album, Favorite album.
6. **Artist Detail** — artist image/bio, top tracks, albums rail, similar artists rail (derived from shared genre tags).
7. **Playlist Detail** — local playlists only (create/rename/delete/reorder/add-remove tracks, all stored on-device); no "collaborative" feature (needs a backend — skip it).
8. **Queue** — draggable bottom sheet: now playing + up-next, drag-to-reorder, swipe-to-remove, play-next/move-to-top, clear/shuffle/repeat queue.
9. **Now Playing** — full-screen sheet with the 4 switchable skins (Vinyl/CD/Cassette/Minimal), transport controls, sleep timer, playback speed, lyrics button, queue button.
10. **Lyrics** — static or synced (LRC) lyrics if a free lyrics source is available; otherwise show "Lyrics not available" gracefully. No paid lyrics API.
11. **Downloads** — active downloads with progress, completed downloads, retry failed, delete, storage usage.
12. **Favorites** — local favorited tracks list.
13. **History** — local recently-played list, grouped by day.
14. **Library** — tabs: Songs/Albums/Artists/Playlists + shortcuts to Downloads/Favorites/History.
15. **Settings** — Appearance (Dark/Light/System, accent color, dynamic color, animation speed, rounded corners, glass effects), Player Settings (Now Playing style picker, gapless, crossfade, normalize volume, auto-resume, remember position, gesture controls, **Haptic Feedback toggle**), Audio Settings (quality selector — capped honestly by what Jamendo's `audioformat` actually offers), Notification Settings, About.
16. **Equalizer** — band sliders + presets (Rock/Pop/Hip-Hop/Jazz/Electronic/Classical/Custom), applied via platform audio effects where `just_audio` exposes them.
17. **Sleep Timer** — bottom sheet from Now Playing (5/15/30/45/60 min or end-of-track), fades volume over the final 10s.

Skip entirely: Login, Register, Forgot Password, Profile (no accounts to manage).

---

## 5. Bottom navigation & Mini Player

- **Bottom nav (5 tabs):** Home, Search, Library, Queue, Settings. `NavigationBar` (Material 3). Every tab switch calls `HapticsService.tabChange()`.
- **Mini Player:** pinned above the bottom nav whenever a queue is active. Shows artwork, title, artist, play/pause, next, a thin progress line along the top edge. Tap → expands to Now Playing via a shared-element (Hero) transition. Swipe left/right on it → previous/next (if Gesture Controls is on in Settings).

---

## 6. Classic Vinyl Mode (Now Playing skins)

Build 4 interchangeable Now Playing visual styles behind one shared widget contract (`isPlaying`, `progress`, `artworkUrl` in → animated visual out), switchable in Settings → Player Settings → "Now Playing Style":

1. **Vinyl (default):** black disc with procedurally drawn concentric grooves (`CustomPainter`, no image asset needed), album art as the center label, subtle radial reflection highlight, animated tonearm/needle that drops onto the record on play and lifts on pause. Disc spins continuously while playing (`AnimationController.repeat()`, ~1.8s/revolution, linear) and **decelerates smoothly to a stop on pause** (animate to a slightly-further angle over ~600ms with `Curves.decelerate`) — never snap to a stop instantly.
2. **CD:** reflective disc, rainbow specular gradient overlay, faster spin, art in the center hole area.
3. **Cassette:** retro cassette shell illustration with two spinning reels bound to progress.
4. **Minimal:** no skeuomorphism — large square album art, flat modern control row.

---

## 7. Animations to implement

| Animation | Trigger |
|---|---|
| Vinyl rotation + decel-to-stop | play / pause |
| Needle drop / lift | play / pause (Vinyl mode) |
| Album art zoom (Hero) | Mini Player → Now Playing expand |
| Button ripple | any tap target (keep Material's default `InkWell` ripple, tinted to accent color) |
| Animated waveform | while playing — a seeded pseudo-random bar animation is fine (no real FFT needed since audio is a streamed URL, not a raw buffer) |
| Page transitions | route push/pop — shared-axis on Android, horizontal-slide on iOS (branch on `Theme.of(context).platform`) |
| Staggered card fade-in | first load of a rail (cap stagger to first ~8 visible items) |
| Queue add/remove/reorder | `AnimatedList` insert/remove with slide+fade; `ReorderableListView` for drag |
| Loading state | skeleton shimmer (`shimmer` package) shaped like the target content, not a generic spinner |
| Pull-to-refresh | small Lottie loop instead of the default spinner |

Respect the OS "Reduce Motion" setting and the in-app Animation Speed setting by scaling durations down, not removing state-communicating motion entirely.

---

## 8. Haptics — implement on every one of these events

Build one `HapticsService` class (wrapping `HapticFeedback` + `vibration`) that every other file calls through — never call `HapticFeedback` directly from a screen. Gate all of it behind a single Settings → Player Settings → **"Haptic Feedback"** toggle (on by default).

```dart
class HapticsService {
  final bool Function() isEnabled;
  Future<void> tabChange();        // bottom nav tab switch -> selectionClick
  Future<void> selection();        // list item tap, filter chip, switch toggle -> selectionClick
  Future<void> play();             // play pressed -> mediumImpact
  Future<void> pause();            // pause pressed -> lightImpact
  Future<void> skip();             // next / previous / swipe-skip on mini player -> mediumImpact
  Future<void> seekReleased();     // seek bar released (NOT while dragging) -> lightImpact
  Future<void> favoriteToggleOn(); // heart -> on: two quick light pulses ("success" feel)
  Future<void> favoriteToggleOff();// heart -> off: lightImpact
  Future<void> queueReorderPickup();// drag start -> lightImpact
  Future<void> queueReorderDrop();  // drag drop -> mediumImpact
  Future<void> downloadComplete();  // -> success pattern
  Future<void> downloadFailed();    // -> error pattern (double sharp buzz)
  Future<void> sleepTimerEnd();     // -> warning pattern
  Future<void> refreshTriggered();  // pull-to-refresh threshold hit -> lightImpact
}
```

Wire it in specifically at:
- **Bottom nav tab change** → `tabChange()`
- **Play button** (Mini Player and Now Playing) → `play()`
- **Pause button** → `pause()`
- **Next / Previous buttons**, and swipe-to-skip gesture on Mini Player → `skip()`
- **Seek bar** → `seekReleased()` only on release, never continuously while dragging
- **Favorite heart** → `favoriteToggleOn()` / `favoriteToggleOff()`
- **Queue drag** → `queueReorderPickup()` on pickup, `queueReorderDrop()` on drop
- **Download finishes** → `downloadComplete()`; **download fails** → `downloadFailed()`
- **Sleep timer fires** → `sleepTimerEnd()`
- **Settings switches, filter chips, list selections** → `selection()`

All transport haptics must fire from the central `PlayerController` (the Notifier that wraps `audio_service`/`just_audio`), not from individual screen widgets, so the mapping stays consistent no matter which screen the button is tapped from.

---

## 9. Playback engine

- Wrap `just_audio`'s `AudioPlayer` inside an `audio_service` `BaseAudioHandler` so playback survives backgrounding and gets OS lock-screen/notification controls + Bluetooth/headset button support for free.
- Use `ConcatenatingAudioSource` for the queue; `just_audio`'s built-in shuffle/loop modes for shuffle and repeat.
- A single global `PlayerController` (Riverpod `Notifier`) is the only thing every screen (Mini Player, Now Playing, Queue) reads from — no duplicated player state.
- Persist "last track + position" to `shared_preferences`, debounced every ~5s, so Auto Resume / Remember Position settings work across app restarts — this is local-only, not a database.

---

## 10. Downloads (offline playback, still no backend)

- Tapping Download streams the track's `audio` URL to a file in the app's local documents directory (`/downloads/<trackId>.mp3`), tracked in a local Isar collection (`status`, `bytesTotal`, `bytesDownloaded`, `localPath`) — this is on-device bookkeeping only, not a server database.
- Show progress in the Downloads screen; support retry on failure and delete.
- When offline (`connectivity_plus` reports no connection), only downloaded/cached tracks are playable; show a non-blocking banner rather than error dialogs.

---

## 11. Folder structure

```
lib/
├── main.dart
├── core/                    # constants, error types, dio setup
├── models/                  # Track, Album, Artist, Playlist (plain Dart classes)
├── services/
│   ├── music_sources/
│   │   ├── music_source.dart     # abstract interface
│   │   └── jamendo_source.dart   # implementation
│   ├── audio_player_service.dart # audio_service + just_audio wiring
│   ├── download_service.dart
│   ├── local_storage_service.dart # Isar/shared_preferences wrapper
│   ├── haptics_service.dart
│   └── recommendation_service.dart # local genre-weighted heuristic
├── providers/                # Riverpod: player, queue, playlist, theme,
│                              # settings, search, download (NO auth provider)
├── screens/                  # one folder per screen from §4
├── widgets/
│   ├── now_playing_skins/    # vinyl_skin.dart, cd_skin.dart, cassette_skin.dart, minimal_skin.dart
│   ├── mini_player.dart
│   ├── track_tile.dart
│   └── shimmer_placeholders/
├── themes/
└── routes/                   # go_router config, no auth guard/redirect logic
```

---

## 12. Non-functional requirements (keep it real, but skip anything backend-related)

- Cold start ≤ 2.5s to an interactive Home screen on a mid-tier device.
- Full Dark Mode + Light Mode + dynamic color (derive accent from current album art via `palette_generator`).
- Respect OS text scaling and "Reduce Motion."
- Screen-reader labels on every transport control and track row.
- App must be **fully usable with zero network** as long as tracks were previously downloaded/cached (favorites, downloads, history, playlists, settings all live locally, so none of that needs connectivity either).
- No login wall anywhere — the app is 100% usable the moment it's installed.

---

## 13. Explicitly do NOT build

- No login/register/forgot-password screens or flows.
- No Supabase/Firebase/any backend service.
- No Postgres/SQL server schema — local storage (Isar/`shared_preferences`) only.
- No collaborative playlists, no cross-device sync, no user accounts, no server-side recommendations.
- No payment/subscription logic (Premium is out of scope entirely for this build, not just "future").

---

*End of document. Build screen by screen following §4, wiring haptics per §8 and the Jamendo source per §3 as you go.*
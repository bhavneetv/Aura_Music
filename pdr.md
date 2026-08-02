# PRD — Flutter Music App (Agent Implementation Spec)

Instructions for the coding agent: each task below is self-contained. Implement in the order listed (dependencies are noted). For each task: read the goal, follow the implementation steps, use the exact package/API names given, and verify against the acceptance criteria before moving to the next task. Do not implement anything under "Already Implemented."

---

## ALREADY IMPLEMENTED — do not rebuild
- Core playback (search, stream, queue)
- Favorites
- Sleep timer
- Crossfade
- Equalizer

---

## TASK 0: Bug Fixes
No dependencies. Do these first.

### 0.1 Playlist saves wrong track/cover art / won't play
- **Cause:** playlist entries are storing a partial reference (index or ID only) instead of the full track object.
- **Fix:** change playlist storage model to persist the complete track object per entry: `{id, title, artist, coverUrl, streamUrl, duration}` as JSON, not an index into a mutable list.
- **On playlist load:** if `streamUrl` may expire, re-fetch a fresh stream URL by `id` from the JioSaavn API at play time, but keep `title`/`artist`/`coverUrl` from the saved snapshot (don't re-fetch metadata).
- **Acceptance:** save a playlist, force-close app, reopen, play every song in it — correct art/title/audio for each.

### 0.2 iOS requires pull-to-refresh twice
- **Cause:** `RefreshIndicator` (Material) misfires on first pull inside iOS scroll physics, especially when nested inside another scrollable.
- **Fix:** on iOS, replace `RefreshIndicator` with `CupertinoSliverRefreshControl` inside a `CustomScrollView`. Ensure the scrollable that owns the refresh control is the outermost/direct scrollable — not nested inside a second `ScrollView`/`ListView`.
- **Acceptance:** single pull-to-refresh triggers refresh on iOS, matches Android behavior.

### 0.3 Haptics too strong on toggles/tab changes
- **Fix:** find all `HapticFeedback.vibrate()` / `mediumImpact()` / `heavyImpact()` calls tied to toggle switches and tab/screen changes. Replace with `HapticFeedback.lightImpact()`.
- **Acceptance:** toggling switches and changing tabs produces a light tap, not a strong buzz.

### 0.4 Loading spinner and other elements ignore theme color
- **Cause:** hardcoded colors instead of reading from theme.
- **Fix:** audit every `CircularProgressIndicator(...)` and set `color: Theme.of(context).colorScheme.primary`. Grep the codebase for literal `Colors.` usage in UI widgets and replace with theme-derived colors where the intent is "match app theme."
- **Acceptance:** changing the theme color updates spinners and all other previously-hardcoded elements immediately.

### 0.5 Greeting shows wrong time-of-day
- **Fix:** replace time-of-day logic with:
```dart
String greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  if (hour < 21) return 'Good evening';
  return 'Good night';
}
```
- **Acceptance:** correct greeting at 9am, 2pm, 6pm, 11pm.

---

## TASK 1: AiService (Groq → Gemini fallback)
No dependencies except network access. Required by Tasks 4, 6, 7.

### Goal
A single service class all AI features call through. Tries Groq first; on any failure (non-200, timeout, exception) falls back to Gemini. Caller never handles provider-specific logic.

### API keys
- Groq: obtained at `console.groq.com` → API Keys → Create API Key. No cost, no card.
- Gemini: obtained at `aistudio.google.com/app/apikey` → Create API key. No cost, no card.
- Store both server-side if any backend exists (preferred). If client-only for now, inject via `--dart-define=GROQ_KEY=... --dart-define=GEMINI_KEY=...`, never commit to source control.

### Implementation
Create `lib/services/ai_service.dart`:
```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class AiService {
  final String groqKey;
  final String geminiKey;
  AiService({required this.groqKey, required this.geminiKey});

  Future<String> generate(String prompt) async {
    try {
      return await _callGroq(prompt).timeout(const Duration(seconds: 8));
    } catch (_) {
      return await _callGemini(prompt);
    }
  }

  Future<String> _callGroq(String prompt) async {
    final res = await http.post(
      Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $groqKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'llama-3.3-70b-versatile',
        'messages': [{'role': 'user', 'content': prompt}],
      }),
    );
    if (res.statusCode != 200) throw Exception('Groq ${res.statusCode}');
    return jsonDecode(res.body)['choices'][0]['message']['content'];
  }

  Future<String> _callGemini(String prompt) async {
    final res = await http.post(
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$geminiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'contents': [{'parts': [{'text': prompt}]}]}),
    );
    if (res.statusCode != 200) throw Exception('Gemini ${res.statusCode}');
    return jsonDecode(res.body)['candidates'][0]['content']['parts'][0]['text'];
  }
}
```
- Instantiate once (e.g. in a provider/singleton), inject into any feature needing AI text generation.
- Log which provider served each call (return a `(String text, String provider)` tuple instead of bare `String` if you want failure-rate visibility).

### Acceptance
- Force a Groq failure (bad key) → request still succeeds via Gemini.
- Both keys valid → Groq is used (verify via log).

---

## TASK 2: Synced Lyrics
Depends on: nothing. Independent of Task 1 except for the fallback path.

### Goal
Fetch time-synced lyrics and highlight the current line as the track plays.

### API
LRCLIB — free, no key required.
- `GET https://lrclib.net/api/get?track_name={name}&artist_name={artist}&album_name={album}&duration={seconds}`
- Fallback: `GET https://lrclib.net/api/search?track_name={name}&artist_name={artist}` — returns array, pick result with closest `duration` to the actual track duration.
- Response fields: `syncedLyrics` (LRC string), `plainLyrics` (string), `instrumental` (bool).

### Implementation
1. Create `lib/services/lyrics_service.dart` with a function `fetchLyrics(trackName, artistName, albumName, durationSeconds)` returning `{synced: List<LyricLine>?, plain: String?}`.
2. Parse LRC format with:
```dart
class LyricLine {
  final Duration time;
  final String text;
  LyricLine(this.time, this.text);
}

List<LyricLine> parseLrc(String lrc) {
  final lines = <LyricLine>[];
  final regex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');
  for (final line in lrc.split('\n')) {
    final m = regex.firstMatch(line);
    if (m == null) continue;
    lines.add(LyricLine(
      Duration(
        minutes: int.parse(m.group(1)!),
        seconds: int.parse(m.group(2)!),
        milliseconds: int.parse(m.group(3)!.padRight(3, '0')),
      ),
      m.group(4)!.trim(),
    ));
  }
  return lines;
}

int currentLineIndex(List<LyricLine> lines, Duration position) {
  int idx = -1;
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].time <= position) idx = i; else break;
  }
  return idx;
}
```
3. In the player screen, subscribe to the audio player's position stream. On each tick, compute `currentLineIndex` and scroll a `ListView`/`ScrollController` so that line is centered. Bold + full opacity for active line; ~40% opacity for others.
4. Resolution order to implement: (a) exact `get` match → synced, (b) `search` best duration match → synced, (c) `plainLyrics` → static non-scrolling display, (d) nothing found → hand off to Task 6 (AI explanation) as the displayed content instead.
5. Cache fetched lyrics locally keyed by track ID (local DB / shared_preferences JSON) to avoid re-fetching on repeat plays and to support offline viewing.

### 2.6 Lyrics button in player
- Add a lyrics icon button in the player screen controls row.
- **Enabled/disabled state:** on track load, resolve lyrics per the order in step 4. If the result is "nothing found" (no synced, no plain, LRCLIB returns empty for all query variants), disable the button (greyed out, non-tappable, e.g. `onPressed: null`). If any lyrics exist (synced or plain), enable it.
- **On tap:** open a full-screen (or large bottom-sheet) lyrics window over the player.
- **Sync highlight style (Spotify-style):**
  - The line currently being sung/about to be sung (the line whose timestamp is the next one reached) is rendered in white/full-opacity, larger or bold weight.
  - All other lines rendered in grey (~40-50% opacity of the theme's text color).
  - As playback crosses each line's timestamp, animate the color/opacity transition (150-250ms) from grey → white for the new active line, and white → grey for the previous one.
  - Auto-scroll so the active line stays vertically centered (or fixed in the upper third, matching Spotify's layout) — use the same `currentLineIndex` logic from step 3, driven by the position stream.
  - If only `plainLyrics` exists (no timestamps), show the full lyrics as static grey text, no highlighting, no auto-scroll.
- **Multi-language lyrics:** if LRCLIB's `search` endpoint returns multiple candidate results for the same track with lyrics in different languages/scripts (e.g. romanized vs. native script), surface a language toggle at the top of the lyrics window listing the available options; switching re-renders using the alternate candidate's `syncedLyrics`/`plainLyrics`, keeping the same sync logic. If only one lyrics result exists, don't show the toggle.

### Acceptance
- Playing a track with LRCLIB coverage shows lyrics auto-scrolling in sync with playback, active line visually distinct.
- Track with only plain lyrics shows static lyrics, no crash.
- Track with no lyrics at all falls through to Task 6 output, no crash.
- Lyrics button is disabled (not just hidden) when a track has zero lyrics results; enabled otherwise.
- Opening the lyrics window on a synced track shows the current/next line in white, all other lines in grey, updating live as playback progresses.
- If multiple lyrics languages are available for a track, a toggle lets the user switch between them.

---

## TASK 3: Dynamic Theming from Cover Art
Depends on: nothing.

### Goal
Player screen background subtly reflects the current track's cover art colors.

### Package
`palette_generator` (pub.dev, official Flutter package).

### Implementation
1. On track change, run:
```dart
final palette = await PaletteGenerator.fromImageProvider(
  NetworkImage(coverArtUrl),
  size: const Size(100, 100),
);
final accent = palette.vibrantColor?.color ?? palette.dominantColor?.color ?? Colors.grey;
```
2. Cache `accent` alongside the track object so it's not recomputed on every rebuild — recompute only on track change.
3. Render behind player content:
```dart
BackdropFilter(
  filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
  child: Container(
    decoration: BoxDecoration(
      gradient: RadialGradient(
        colors: [accent.withOpacity(0.25), Colors.transparent],
      ),
    ),
  ),
)
```
4. Wrap the color transition in `AnimatedContainer` or `TweenAnimationBuilder<Color>` with a 300–500ms duration so it doesn't snap between tracks.

### Acceptance
- Changing tracks produces a smoothly-animated, subtly-tinted background matching the new cover art, never a hard flat color fill, never overwhelming the UI.

---

## TASK 4: AI Search + AI Playlist Curation
Depends on: Task 1 (AiService).

### Goal
Natural-language search/playlist requests resolve to real tracks via the existing JioSaavn search endpoint — the LLM only generates search terms, never invents track data.

### 4.1 AI toggle on Search page
- Add an AI toggle button on the search page (e.g. a star icon button next to/inside the search bar).
- **Off state:** search bar in default theme styling, normal keyword search against `/search/songs?query=` only — no AI call.
- **On state:**
  - Search bar background/border/accent color changes to a golden-yellow color (e.g. `Color(0xFFFFC72C)` or similar gold tone — pick one consistent with the app's existing palette contrast requirements).
  - Display a star icon on/inside the search bar to visually confirm AI search is active.
  - Persist the toggle state for the session (resets off on app restart, or persist in `SharedPreferences` if always-on-by-default is preferred — default to session-only unless specified otherwise).
  - When active, submitted queries go through the Task 4 AI query-expansion flow (step below) instead of a raw keyword search.
- Below/near the toggle when it's ON, show a small persistent disclaimer text, e.g.: *"AI search can make mistakes and may take longer than regular search."*

### 4.2 AI search loading animation
- While an AI-search request is in flight (waiting on `AiService.generate()` + the subsequent song lookups), show a custom loading animation instead of a generic spinner:
  - A **vinyl disk graphic continuously rotating** (reuse the rotation approach from Task 9.1's vinyl-spin cover art style if already built — same `AnimationController` pattern, looping indefinitely while loading).
  - **Music note icons animating outward in randomized directions** from around the disk (e.g. 3-5 small note icons, each with a randomized angle/trajectory and fade-out as they move away, looping or staggered so new notes keep emitting while loading continues).
  - Keep the golden-yellow accent color from 4.1 in this animation (e.g. disk rim glow or note icon tint) so the loading state visually matches the AI-search-on state.
- Dismiss the animation and show results (or the review/curation screen from step below) as soon as the search resolves.

### Implementation — query resolution
1. On user query (e.g. "old Punjabi songs like Karan Aujla"), call `AiService.generate()` with a prompt instructing the model to return **strict JSON only**:
```
Given this music request: "{user_query}"
Return ONLY valid JSON, no other text, in this exact shape:
{"intent": "search" | "playlist", "queries": ["term1", "term2", ...], "playlist_name_suggestion": "string"}
Generate 3-6 concrete search query strings a music search API could use (artist names, song titles, eras, genres). Do not invent song titles that don't exist.
```
2. Parse the JSON response. If parsing fails, retry once with a stricter reminder appended to the prompt; if it fails again, fall back to using the raw user query as a single search term.
3. Run each returned query string against the existing `/search/songs?query=` endpoint. Merge results, de-duplicate by track ID.
4. If `intent == "playlist"`: also query the user's local favorites store for tracks matching the same query terms (simple substring/genre match against favorited track metadata) and merge those in too, so favorited songs aren't excluded from AI playlists.
5. Navigate to a new screen: checklist of all resulting tracks (pre-checked), text field pre-filled with `playlist_name_suggestion` (editable), Save/Cancel buttons. Unchecking a track removes it before save.

### Acceptance
- Toggling AI search ON turns the search bar golden-yellow with a visible star icon, and shows the "AI can make mistakes / may take longer" disclaimer; toggling OFF reverts to normal search styling and behavior with no disclaimer.
- "old Punjabi songs like Karan Aujla" returns real, playable tracks by relevant artists, not hallucinated titles.
- Themed playlist requests include the user's matching favorited tracks in the initial checklist.
- Malformed LLM JSON output does not crash the flow.
- While an AI search is in flight, the rotating vinyl disk + outward-animating music note loading animation is shown instead of a generic spinner, and disappears as soon as results are ready.

---

## TASK 5: Player Gestures
Depends on: nothing (Task 5.1 depends on Favorites already implemented).

### 5.1 Double-tap cover art → toggle favorite
```dart
GestureDetector(
  onDoubleTap: () {
    toggleFavorite(currentTrack);
    _showHeartPopAnimation(); // scale 0->1.2->1, fade out, ~400ms
  },
  child: CoverArtWidget(...),
)
```

### 5.2 Long-press (4s) cover art → reveal next 3 queued songs
```dart
Timer? _holdTimer;

void onLongPressStart(LongPressStartDetails d) {
  _holdTimer = Timer(const Duration(seconds: 4), () {
    _showStackedQueuePreview(nextThreeInQueue);
  });
}

void onLongPressEnd(LongPressEndDetails d) => _holdTimer?.cancel();
void onLongPressCancel() => _holdTimer?.cancel();
```
- Render the 3 upcoming tracks as smaller `Card`/`Container` widgets stacked with slight offset + scale behind/below the main art. Each tappable → jumps queue to that track and plays it. Dismiss the stack on tap-away or after selection.

### Acceptance
- Double-tap toggles favorite state with visible heart animation, single taps do not trigger it.
- Holding cover art for 4 continuous seconds reveals the stack; releasing early does not trigger it; tapping a stacked song plays it immediately.

---

## TASK 6: Queue → Playlist Save
Depends on: nothing, but reuses the AI playlist review screen UI from Task 4 if convenient.

### Implementation
1. Add a `source` field to queue item model: `enum QueueSource { user, recommendation }`. Tag every queue insertion with the correct source at insert time.
2. Add a button on the queue screen. On tap, open a bottom sheet with: playlist name `TextField`, radio group (`Only songs I queued` / `All queued songs including recommendations`), Save/Cancel.
3. On Save: filter queue by `source == user` or take the full queue depending on radio selection, write as a new playlist using the same storage model fixed in Task 0.1 (full track objects, not references).

### Acceptance
- Selecting "only user-queued" excludes recommendation-sourced tracks from the saved playlist; selecting "all" includes everything currently queued.

---

## TASK 7: AI Song Explanation
Depends on: Task 1 (AiService), Task 2 (Lyrics — for the "no lyrics found" fallback path and for lyrics-informed explanations).

### Implementation
1. Trigger points: (a) automatically when Task 2's lyrics resolution finds nothing, (b) as an optional "About this song" tab next to lyrics when lyrics do exist.
2. Add a **Summary Language** setting (see Task 7.1 below) that controls the language of generated explanations.
3. Prompt (inject the selected language):
```
Song: "{title}" by {artist}.
{if lyrics available}: Lyrics: "{lyrics_text}"
In 3-4 sentences, explain the theme or story of this song for a listener.
Do not reproduce the lyrics verbatim.
Respond in {selected_language_name} only.
```
4. Call via `AiService.generate()`.
5. Cache result keyed by **`{track_id}_{language_code}`**, not just `track_id` — a track explained in English and then in Hindi must cache both independently.

### 7.1 Summary Language setting
- Add a setting under Settings → "Summary Language" (or similar section) with a fixed, limited list of selectable languages — start with **English** and **Hindi**, structured so more can be added later:
```dart
const summaryLanguages = {
  'en': 'English',
  'hi': 'Hindi',
};
```
- Persist selection (language code) in `SharedPreferences` under e.g. `summary_language`, default `'en'`.
- Every call in Task 7 reads this preference and passes the corresponding language name into the prompt per step 3 above.
- Changing the setting does not retroactively regenerate already-cached explanations — a newly requested track/language pair triggers a fresh AI call and caches under its own `{track_id}_{language_code}` key.

### Acceptance
- Track with no lyrics shows an AI-generated explanation instead of an empty lyrics screen.
- Repeat plays of the same track in the same language do not trigger a new AI call (cache hit).
- Switching the Summary Language setting and reopening the explanation for the same track produces a new explanation in the newly selected language, without needing to clear any existing cache.
- Settings only offers the fixed language list (English, Hindi) — no free-text or unsupported languages selectable.

---

## TASK 8: Onboarding
Depends on: Task 9 (color templates) for the theme-picker step.

### Implementation
1. On app start, check `SharedPreferences` flag `has_onboarded`. If false, show onboarding screen before main app.
2. Collect: name (`TextField`), theme (grid of Task 9 templates, tap to select).
3. Save `user_name` and `selected_theme_key` to `SharedPreferences` (or Supabase if cross-device sync is desired — project already uses Supabase for RewardWatch).
4. Set `has_onboarded = true` after save.
5. Apply `user_name` in greeting (Task 0.5's `greeting()` + `', $userName'`), apply `selected_theme_key`'s seed color via `ColorScheme.fromSeed`.
6. Add "Edit name" and "Change theme" entries in Settings that re-open the same picker UI and update the stored values.

### Acceptance
- Fresh install shows onboarding once; subsequent launches skip it.
- Name and theme chosen at onboarding are reflected immediately in greeting and app theme, and are editable afterward from Settings.

---

## TASK 9: Cover Art Style, Seek Bar Style, Color Templates

### 9.1 Cover art presentation (implement as a settings-selectable style, default to one)
- **Vinyl spin:** `ClipOval` on art, continuous rotation via `AnimationController` while `isPlaying`, pause rotation (don't reset) on pause.
- **3D tilt:** use `sensors_plus` gyroscope stream to apply a small `Transform` perspective tilt to the art widget.
- **Stacked cards:** reuse the stack rendering from Task 5.2 as a persistent style option, not just the long-press reveal.
- **Full-bleed blurred backdrop:** reuse Task 3's blur technique at full-screen scale with the sharp art in a smaller card on top.

### 9.2 Seek bar (implement as a custom `Slider`/`CustomPainter` replacing the default)
- **Waveform bar:** generate a deterministic pseudo-waveform seeded from `track.id.hashCode` (no real audio analysis needed) and render as bars instead of a line.
- **Thick rounded track with glow:** track height 6–8px, full round caps, `BoxShadow` in the Task 3 accent color under the played segment.
- **Drag tooltip:** floating time-label bubble above the thumb while dragging, dismiss on release.

### 9.3 Premade color templates
Define as a fixed list, each a seed color:
```dart
const colorTemplates = {
  'midnight': Color(0xFF1A1A2E),
  'sunset': Color(0xFFFF6B6B),
  'forest': Color(0xFF2D6A4F),
  'amethyst': Color(0xFF6A0DAD),
  'mono': Color(0xFF757575),
  'ocean': Color(0xFF006D77),
  'rose_gold': Color(0xFFB76E79),
};
```
- Store the selected **key** (e.g. `'sunset'`) in preferences, not a raw hex — apply via `ColorScheme.fromSeed(seedColor: colorTemplates[key]!)` so palettes can be refined later without breaking saved selections.

### Acceptance
- Settings screen offers style pickers for cover art and color template; selection persists and applies app-wide immediately.

---

## Build Order (dependency-respecting)
1. Task 0 (bug fixes)
2. Task 1 (AiService)
3. Task 2 (lyrics) — parallel with Task 3
4. Task 3 (dynamic color) — parallel with Task 2
5. Task 9.3 (color templates) before Task 8 (onboarding)
6. Task 5 (gestures) — parallel with above
7. Task 6 (queue→playlist)
8. Task 4 (AI search/playlist)
9. Task 7 (AI explanation)
10. Task 9.1 / 9.2 (visual styles) — lowest priority, cosmetic
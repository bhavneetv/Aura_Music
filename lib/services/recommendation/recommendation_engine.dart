import 'dart:math' as math;
import '../../models/track.dart';
import '../storage/storage_service.dart';

class RecommendationEngine {
  static final RecommendationEngine instance = RecommendationEngine._internal();
  RecommendationEngine._internal();

  // Temperature parameter for Softmax exploration
  static const double _sessionTemperature = 0.65; // Tighter during active session
  static const double _coldStartTemperature = 0.85; // More exploratory on cold start

  // Track session state for cold-start detection
  int _sessionTrackCount = 0;
  bool get _isColdStart => _sessionTrackCount < 3;

  String get currentTimeOfDayContext {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'Morning';
    if (hour >= 12 && hour < 17) return 'Afternoon';
    if (hour >= 17 && hour < 19) return 'Evening';
    return 'Night';
  }

  /// Called whenever a track begins playing — updates all affinity vectors
  void recordTrackStarted(Track track) {
    _sessionTrackCount++;
    final artist = track.artist.split(',').first.trim();
    final genre = track.genre.trim().toUpperCase();

    // Persist real-time vector updates in Hive DB
    StorageService.updateArtistAffinity(artist, 1.5);
    StorageService.updateGenreAffinity(genre, 2.0);
    StorageService.updateLanguageAffinity(genre, 1.5); // genre == language from Saavn
    StorageService.addCooldownTrackTitle(track.title);
    StorageService.setSessionContext(genre: genre, artist: artist, language: genre);

    // Track replay behavior
    final replayCount = StorageService.getReplayCount(track.id);
    if (replayCount >= 2) {
      // User repeatedly plays this track — boost artist and genre significantly
      StorageService.updateArtistAffinity(artist, 8.0);
      StorageService.updateGenreAffinity(genre, 6.0);
      StorageService.updateLanguageAffinity(genre, 5.0);
    }
    StorageService.incrementReplayCount(track.id);
  }

  /// Called whenever a track finishes or is skipped
  void recordTrackEnded(Track track, Duration positionPlayed, Duration totalDuration) {
    final totalSec = totalDuration.inSeconds > 0 ? totalDuration.inSeconds : 180;
    final playedSec = positionPlayed.inSeconds;
    final completionRatio = playedSec / totalSec;

    final artist = track.artist.split(',').first.trim();
    final genre = track.genre.trim().toUpperCase();

    if (completionRatio < 0.25 && playedSec < 30) {
      // Skipped early -> apply strong skip penalty
      StorageService.updateArtistAffinity(artist, -3.0);
      StorageService.updateGenreAffinity(genre, -4.0);
      StorageService.updateLanguageAffinity(genre, -3.5);
      StorageService.addSkipRecord(artist, genre, genre);
    } else if (completionRatio >= 0.75) {
      // Completed listen -> strong completion reward
      StorageService.updateArtistAffinity(artist, 4.0);
      StorageService.updateGenreAffinity(genre, 3.5);
      StorageService.updateLanguageAffinity(genre, 3.0);
    } else if (completionRatio >= 0.4) {
      // Partial listen (engaged but moved on) -> mild positive
      StorageService.updateArtistAffinity(artist, 1.0);
      StorageService.updateGenreAffinity(genre, 0.8);
    }
  }

  /// Called when user likes/favorites a track — immediate affinity boost
  void recordTrackLiked(Track track) {
    final artist = track.artist.split(',').first.trim();
    final genre = track.genre.trim().toUpperCase();
    StorageService.updateArtistAffinity(artist, 6.0);
    StorageService.updateGenreAffinity(genre, 5.0);
    StorageService.updateLanguageAffinity(genre, 4.0);
  }

  /// Multi-Factor Scoring enforcing strict language/genre/artist continuity
  double calculateAffinityScore(Track candidate, {Track? currentTrack}) {
    double score = 50.0;

    final favoriteTrackIds = StorageService.getFavoriteIds('tracks').toSet();
    final artistAffinityMap = StorageService.getArtistAffinityMap();
    final genreAffinityMap = StorageService.getGenreAffinityMap();
    final languageAffinityMap = StorageService.getLanguageAffinityMap();
    final cooldownTitles = StorageService.getCooldownHistoryTitles().toSet();
    final skipHistory = StorageService.getSkipHistory();
    final sessionContext = StorageService.getSessionContext();

    final candidateTitle = candidate.title.trim().toLowerCase();
    final candidateArtist = candidate.artist.split(',').first.trim().toLowerCase();
    final candidateGenre = candidate.genre.trim().toUpperCase();
    final candidateAlbum = candidate.album.trim().toLowerCase();

    // Determine target context from current track or active session
    final targetGenre = currentTrack != null && currentTrack.genre.trim().isNotEmpty
        ? currentTrack.genre.trim().toUpperCase()
        : (sessionContext['genre'] ?? '');

    final targetArtist = currentTrack != null && currentTrack.artist.trim().isNotEmpty
        ? currentTrack.artist.split(',').first.trim().toLowerCase()
        : (sessionContext['artist']?.toLowerCase() ?? '');

    final targetAlbum = currentTrack?.album.trim().toLowerCase() ?? '';

    // ── 1. COOLDOWN & YEAR-SPAM PENALTY ─────────────────────────
    if (cooldownTitles.contains(candidateTitle)) {
      score -= 500.0;
    }

    if (candidateTitle.contains('happy new year') ||
        candidateTitle.contains('new year 202') ||
        candidateTitle.contains('2026 dj') ||
        candidateTitle.contains('2025 dj') ||
        candidateTitle.contains('nonstop dj 202') ||
        candidateTitle.contains('wishing you')) {
      score -= 1000.0; // Heavily penalize year-spam / event-spam tracks
    }

    // ── 2. PREFERRED LANGUAGE & GENRE CONTINUITY (HIGHEST PRIORITY) ──────────
    final preferredLangs = StorageService.getPreferredLanguages();
    if (preferredLangs.isNotEmpty) {
      final matchesPreferred = preferredLangs.any((lang) => _genreMatches(candidateGenre, lang.toUpperCase()));
      if (matchesPreferred) {
        score += 600.0; // Enforce preferred language
      } else {
        score -= 800.0; // Heavily penalize non-preferred languages
      }
    }

    if (targetGenre.isNotEmpty) {
      if (_genreMatches(candidateGenre, targetGenre)) {
        score += 300.0;
      } else {
        score -= 350.0;
      }
    }

    // ── 3. ARTIST CONTINUITY ─────────────────────────────────────
    if (targetArtist.isNotEmpty) {
      if (_artistMatches(candidateArtist, targetArtist)) {
        score += 25.0; // Mild same singer preference (prevents artist flooding)
      }
    }

    // ── 4. ALBUM AFFINITY ────────────────────────────────────────
    if (targetAlbum.isNotEmpty && candidateAlbum == targetAlbum) {
      score += 30.0;
    }

    // ── 5. SKIP HISTORY PENALTY ──────────────────────────────────
    // If user recently skipped songs from this artist/genre, penalize
    final recentSkips = skipHistory.take(10);
    for (final skip in recentSkips) {
      final skipGenre = skip['genre'] ?? '';
      final skipArtist = (skip['artist'] ?? '').toLowerCase();
      if (skipGenre.isNotEmpty && candidateGenre == skipGenre && !_genreMatches(candidateGenre, targetGenre)) {
        score -= 80.0; // Penalize genre that was recently skipped away from
      }
      if (skipArtist.isNotEmpty && candidateArtist == skipArtist) {
        score -= 40.0; // Penalize recently skipped artist
      }
    }

    // ── 6. LIKED SONG BOOST ──────────────────────────────────────
    if (favoriteTrackIds.contains(candidate.id)) {
      score += 40.0;
    }

    // ── 7. USER PROFILE AFFINITY (Hive DB vectors) ───────────────
    final artistAff = artistAffinityMap[candidateArtist] ?? 0.0;
    final genreAff = genreAffinityMap[candidateGenre] ?? 0.0;
    final langAff = languageAffinityMap[candidateGenre] ?? 0.0;
    score += (artistAff * 1.5) + (genreAff * 1.2) + (langAff * 1.0);

    // ── 8. TIME-OF-DAY CONTEXT ───────────────────────────────────
    final timeContext = currentTimeOfDayContext;
    if (timeContext == 'Night' && _isChillGenre(candidateGenre)) {
      score += 15.0;
    } else if (timeContext == 'Morning' && _isMorningGenre(candidateGenre)) {
      score += 15.0;
    }

    // ── 9. ARTIST DIVERSITY (penalize excessive same artist) ──────
    if (currentTrack != null && candidateArtist == currentTrack.artist.split(',').first.trim().toLowerCase()) {
      score -= 40.0; // Encourage variety within same genre
    }

    // ── 10. EXPLORATION NOISE ────────────────────────────────────
    final noiseRange = _isColdStart ? 15.0 : 5.0;
    final noise = (math.Random().nextDouble() * noiseRange * 2) - noiseRange;
    score += noise;

    return score;
  }

  bool _genreMatches(String a, String b) {
    if (a == b) return true;
    if (a.contains(b) || b.contains(a)) return true;
    return false;
  }

  bool _artistMatches(String a, String b) {
    if (a == b) return true;
    if (a.contains(b) || b.contains(a)) return true;
    return false;
  }

  bool _isChillGenre(String genre) {
    return genre.contains('CHILL') || genre.contains('AMBIENT') || genre.contains('LO-FI') || genre.contains('LOFI');
  }

  bool _isMorningGenre(String genre) {
    return genre.contains('ACOUSTIC') || genre.contains('POP') || genre.contains('BOLLYWOOD') || genre.contains('DEVOTIONAL');
  }

  /// Rank candidate tracks using Temperature Softmax sampling and strict Artist Diversity capping
  List<Track> rankRecommendations(List<Track> candidates, {Track? currentTrack, Set<String>? excludeIds, int maxPerArtist = 2}) {
    // Deduplicate by title
    final Map<String, Track> uniqueByTitle = {};
    for (final track in candidates) {
      final key = track.title.trim().toLowerCase();
      if (!uniqueByTitle.containsKey(key)) {
        uniqueByTitle[key] = track;
      }
    }

    final List<MapEntry<Track, double>> scoredEntries = [];

    for (final track in uniqueByTitle.values) {
      final titleKey = track.title.trim().toLowerCase();
      if (excludeIds != null && (excludeIds.contains(track.id) || excludeIds.contains(titleKey))) {
        continue;
      }
      final score = calculateAffinityScore(track, currentTrack: currentTrack);
      scoredEntries.add(MapEntry(track, score));
    }

    if (scoredEntries.isEmpty) return [];

    // Sort by descending score
    scoredEntries.sort((a, b) => b.value.compareTo(a.value));

    // Temperature Softmax Sampling
    final temperature = _isColdStart ? _coldStartTemperature : _sessionTemperature;
    final sampled = _temperatureSample(scoredEntries, temperature);

    // Apply strict Artist Diversity Cap (max 1 additional track for current artist, max 2 for other artists)
    return _applyArtistDiversityCap(sampled, currentTrack: currentTrack, maxPerArtist: maxPerArtist);
  }

  /// Ensures queue diversity by limiting same artist to 1-2 tracks at top of upcoming queue, putting overflow at end
  List<Track> _applyArtistDiversityCap(List<Track> tracks, {Track? currentTrack, int maxPerArtist = 2}) {
    final List<Track> result = [];
    final List<Track> overflow = [];
    final Map<String, int> artistCounts = {};

    final currentArtistKey = currentTrack != null
        ? currentTrack.artist.split(',').first.trim().toLowerCase()
        : '';

    // If current track is playing, count 1 for that artist
    if (currentArtistKey.isNotEmpty) {
      artistCounts[currentArtistKey] = 1;
    }

    for (final track in tracks) {
      final artistKey = track.artist.split(',').first.trim().toLowerCase();
      final count = artistCounts[artistKey] ?? 0;

      // Allow max 1 additional song for currently playing artist, max 2 for other artists
      final limit = (currentArtistKey.isNotEmpty && artistKey == currentArtistKey) ? 1 : maxPerArtist;

      if (count < limit) {
        result.add(track);
        artistCounts[artistKey] = count + 1;
      } else {
        overflow.add(track);
      }
    }

    // Append overflow tracks at the end of queue
    result.addAll(overflow);
    return result;
  }

  /// Re-score existing upcoming queue tracks against current context and filter low-scoring ones
  List<Track> rerankUpcomingQueue(List<Track> upcomingTracks, Track currentTrack) {
    final scored = upcomingTracks.map((t) {
      final score = calculateAffinityScore(t, currentTrack: currentTrack);
      return MapEntry(t, score);
    }).toList();

    // Remove tracks that score below threshold (mismatch penalty is -350, so anything < -100 is bad)
    scored.removeWhere((e) => e.value < -100.0);

    // Sort by descending score
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.map((e) => e.key).toList();
  }

  /// Performs Softmax probability distribution sampling over top candidates
  List<Track> _temperatureSample(List<MapEntry<Track, double>> sortedEntries, double temperature) {
    if (sortedEntries.length <= 1) {
      return sortedEntries.map((e) => e.key).toList();
    }

    final topK = sortedEntries.take(20).toList();
    final double maxScore = topK.first.value;

    // Compute exponents with numeric stability shift
    final List<double> exps = topK.map((e) => math.exp((e.value - maxScore) / temperature)).toList();
    final double sumExp = exps.reduce((a, b) => a + b);
    final List<double> probs = exps.map((e) => e / sumExp).toList();

    final List<Track> sampledList = [];
    final List<MapEntry<Track, double>> pool = List.from(topK);
    final List<double> poolProbs = List.from(probs);

    while (pool.isNotEmpty) {
      final double r = math.Random().nextDouble();
      double cumulative = 0.0;
      int selectedIdx = 0;

      for (int i = 0; i < poolProbs.length; i++) {
        cumulative += poolProbs[i];
        if (r <= cumulative) {
          selectedIdx = i;
          break;
        }
      }

      sampledList.add(pool[selectedIdx].key);
      pool.removeAt(selectedIdx);
      poolProbs.removeAt(selectedIdx);

      // Re-normalize remaining probabilities
      final double newSum = poolProbs.fold(0.0, (a, b) => a + b);
      if (newSum > 0) {
        for (int i = 0; i < poolProbs.length; i++) {
          poolProbs[i] /= newSum;
        }
      }
    }

    // Append remaining tail items if any
    if (sortedEntries.length > 20) {
      sampledList.addAll(sortedEntries.sublist(20).map((e) => e.key));
    }

    return sampledList;
  }
}

class UserStats {
  final int totalSongsPlayed;
  final Map<String, int> topArtists;
  final String? favoriteArtist;
  final Map<String, int> dailyListens;

  const UserStats({
    this.totalSongsPlayed = 0,
    this.topArtists = const {},
    this.favoriteArtist,
    this.dailyListens = const {},
  });

  factory UserStats.empty() {
    return const UserStats(
      totalSongsPlayed: 0,
      topArtists: {},
      favoriteArtist: null,
      dailyListens: {},
    );
  }

  factory UserStats.fromMap(Map<String, dynamic>? data) {
    if (data == null) return UserStats.empty();

    final topArtistsRaw = data['topArtists'] as Map<dynamic, dynamic>? ?? {};
    final topArtists = <String, int>{};
    topArtistsRaw.forEach((key, value) {
      if (key != null && value is num) {
        topArtists[key.toString()] = value.toInt();
      }
    });

    final dailyListensRaw = data['dailyListens'] as Map<dynamic, dynamic>? ?? {};
    final dailyListens = <String, int>{};
    dailyListensRaw.forEach((key, value) {
      if (key != null && value is num) {
        dailyListens[key.toString()] = value.toInt();
      }
    });

    return UserStats(
      totalSongsPlayed: (data['totalSongsPlayed'] as num?)?.toInt() ?? 0,
      topArtists: topArtists,
      favoriteArtist: data['favoriteArtist'] as String?,
      dailyListens: dailyListens,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'totalSongsPlayed': totalSongsPlayed,
      'topArtists': topArtists,
      'favoriteArtist': favoriteArtist,
      'dailyListens': dailyListens,
    };
  }

  UserStats copyWith({
    int? totalSongsPlayed,
    Map<String, int>? topArtists,
    String? favoriteArtist,
    Map<String, int>? dailyListens,
  }) {
    return UserStats(
      totalSongsPlayed: totalSongsPlayed ?? this.totalSongsPlayed,
      topArtists: topArtists ?? this.topArtists,
      favoriteArtist: favoriteArtist ?? this.favoriteArtist,
      dailyListens: dailyListens ?? this.dailyListens,
    );
  }
}

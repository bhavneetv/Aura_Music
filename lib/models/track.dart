class Track {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String duration;
  final String artworkUrl;
  final String audioUrl;
  final String genre;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.artworkUrl,
    required this.audioUrl,
    required this.genre,
  });

  Track copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? duration,
    String? artworkUrl,
    String? audioUrl,
    String? genre,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      audioUrl: audioUrl ?? this.audioUrl,
      genre: genre ?? this.genre,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'duration': duration,
        'artworkUrl': artworkUrl,
        'audioUrl': audioUrl,
        'genre': genre,
      };

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Unknown Title',
      artist: json['artist'] as String? ?? 'Unknown Artist',
      album: json['album'] as String? ?? '',
      duration: json['duration'] as String? ?? '3:30',
      artworkUrl: json['artworkUrl'] as String? ?? '',
      audioUrl: json['audioUrl'] as String? ?? '',
      genre: json['genre'] as String? ?? '',
    );
  }

  // Mock tracks representing Creative Commons & fallback tracks
  static List<Track> get mockTracks => [
    const Track(
      id: '1',
      title: 'Midnight Sun',
      artist: 'Aether Flow',
      album: 'Ethereal Waves',
      duration: '3:45',
      artworkUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=500&auto=format&fit=crop&q=60',
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
      genre: 'Chillout',
    ),
    const Track(
      id: '2',
      title: 'Golden Horizon',
      artist: 'Solaris Duo',
      album: 'Sunsets & Silhouettes',
      duration: '4:12',
      artworkUrl: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=500&auto=format&fit=crop&q=60',
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
      genre: 'Ambient',
    ),
    const Track(
      id: '3',
      title: 'Neon Drift',
      artist: 'Synthetica',
      album: 'Retro Future',
      duration: '3:20',
      artworkUrl: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=500&auto=format&fit=crop&q=60',
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
      genre: 'Synthwave',
    ),
    const Track(
      id: '4',
      title: 'Velvet Echoes',
      artist: 'Luna Eclipse',
      album: 'Dark Side of Joy',
      duration: '5:02',
      artworkUrl: 'https://images.unsplash.com/photo-1507838153414-b4b713384a76?w=500&auto=format&fit=crop&q=60',
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3',
      genre: 'Indie Pop',
    ),
    const Track(
      id: '5',
      title: 'Starlight Voyage',
      artist: 'Cosmo Ranger',
      album: 'Deep Space Odyssey',
      duration: '4:30',
      artworkUrl: 'https://images.unsplash.com/photo-1459749411175-04bf5292ceea?w=500&auto=format&fit=crop&q=60',
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-5.mp3',
      genre: 'Chillout',
    ),
    const Track(
      id: '6',
      title: 'Autumn Rain',
      artist: 'Whispering Winds',
      album: 'Acoustic Seasons',
      duration: '3:50',
      artworkUrl: 'https://images.unsplash.com/photo-1501630834273-4b5604d2ee31?w=500&auto=format&fit=crop&q=60',
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-6.mp3',
      genre: 'Acoustic',
    ),
    const Track(
      id: '7',
      title: 'Desi Rhythm',
      artist: 'Amrit Pal',
      album: 'Punjabi Beats',
      duration: '3:30',
      artworkUrl: 'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?w=500&auto=format&fit=crop&q=60',
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-7.mp3',
      genre: 'Punjabi',
    ),
    const Track(
      id: '8',
      title: 'Tum Hi Ho Vibe',
      artist: 'Arijit Vibes',
      album: 'Romantic Melodies',
      duration: '4:15',
      artworkUrl: 'https://images.unsplash.com/photo-1518609878373-06d740f60d8b?w=500&auto=format&fit=crop&q=60',
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-8.mp3',
      genre: 'Bollywood',
    ),
    const Track(
      id: '9',
      title: 'Midnight Coffee Lofi',
      artist: 'Chilled Cow',
      album: 'Study Sessions',
      duration: '2:45',
      artworkUrl: 'https://images.unsplash.com/photo-1501386761578-eac5c94b800a?w=500&auto=format&fit=crop&q=60',
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-9.mp3',
      genre: 'Lo-Fi',
    ),
    const Track(
      id: '10',
      title: 'City Street Flow',
      artist: 'Metro Beats',
      album: 'Urban Nights',
      duration: '3:10',
      artworkUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=500&auto=format&fit=crop&q=60',
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-10.mp3',
      genre: 'Hip-Hop',
    ),
    const Track(
      id: '11',
      title: 'Bhangra Grooves',
      artist: 'Diljit Sound',
      album: 'Bhangra Fire',
      duration: '3:40',
      artworkUrl: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=500&auto=format&fit=crop&q=60',
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-11.mp3',
      genre: 'Punjabi',
    ),
    const Track(
      id: '12',
      title: 'Sufi Soul',
      artist: 'Rahat Melodies',
      album: 'Mystic Echoes',
      duration: '4:50',
      artworkUrl: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=500&auto=format&fit=crop&q=60',
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-12.mp3',
      genre: 'Bollywood',
    ),
  ];
}

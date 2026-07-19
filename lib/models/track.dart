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

  // Mock tracks representing Creative Commons tracks
  static List<Track> get mockTracks => const [
    Track(
      id: '1',
      title: 'Midnight Sun',
      artist: 'Aether Flow',
      album: 'Ethereal Waves',
      duration: '3:45',
      artworkUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=500&auto=format&fit=crop&q=60',
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
      genre: 'Chillout',
    ),
    Track(
      id: '2',
      title: 'Golden Horizon',
      artist: 'Solaris Duo',
      album: 'Sunsets & Silhouettes',
      duration: '4:12',
      artworkUrl: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=500&auto=format&fit=crop&q=60',
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
      genre: 'Ambient',
    ),
    Track(
      id: '3',
      title: 'Neon Drift',
      artist: 'Synthetica',
      album: 'Retro Future',
      duration: '3:20',
      artworkUrl: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=500&auto=format&fit=crop&q=60',
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
      genre: 'Synthwave',
    ),
    Track(
      id: '4',
      title: 'Velvet Echoes',
      artist: 'Luna Eclipse',
      album: 'Dark Side of Joy',
      duration: '5:02',
      artworkUrl: 'https://images.unsplash.com/photo-1507838153414-b4b713384a76?w=500&auto=format&fit=crop&q=60',
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3',
      genre: 'Indie Pop',
    ),
    Track(
      id: '5',
      title: 'Starlight Voyage',
      artist: 'Cosmo Ranger',
      album: 'Deep Space Odyssey',
      duration: '4:30',
      artworkUrl: 'https://images.unsplash.com/photo-1459749411175-04bf5292ceea?w=500&auto=format&fit=crop&q=60',
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-5.mp3',
      genre: 'Chillout',
    ),
    Track(
      id: '6',
      title: 'Autumn Rain',
      artist: 'Whispering Winds',
      album: 'Acoustic Seasons',
      duration: '3:50',
      artworkUrl: 'https://images.unsplash.com/photo-1487180142328-0c4e37023af5?w=500&auto=format&fit=crop&q=60',
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-6.mp3',
      genre: 'Acoustic',
    ),
  ];
}

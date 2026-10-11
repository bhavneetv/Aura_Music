import 'package:cloud_firestore/cloud_firestore.dart';
import 'playlist_track.dart';

class Playlist {
  final String id;
  final String name;
  final String description;
  final String ownerUid;
  final String ownerName;
  final List<String> memberUids;
  final String visibility; // "private" | "public"
  final bool collabEnabled;
  final String type; // "custom" | "favorites"
  final DateTime createdAt;
  final DateTime updatedAt;
  final int trackCount;
  final List<PlaylistTrack> tracks;
  final String? shareCode;

  const Playlist({
    required this.id,
    required this.name,
    this.description = '',
    required this.ownerUid,
    required this.ownerName,
    required this.memberUids,
    this.visibility = 'private',
    this.collabEnabled = false,
    this.type = 'custom',
    required this.createdAt,
    required this.updatedAt,
    required this.trackCount,
    this.tracks = const [],
    this.shareCode,
  });

  bool get isPublic => visibility == 'public';
  bool get isFavorites => type == 'favorites';
  bool isOwner(String? uid) => uid != null && uid == ownerUid;
  bool isMember(String? uid) => uid != null && memberUids.contains(uid);
  bool canEditTracks(String? uid) => isOwner(uid) || (collabEnabled && isMember(uid));
  bool canManage(String? uid) => isOwner(uid);

  factory Playlist.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return Playlist.fromMap(doc.data() ?? {}, id: doc.id);
  }

  factory Playlist.fromMap(Map<String, dynamic> data, {String? id}) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    final rawMembers = data['memberUids'] as List<dynamic>? ?? [];
    final memberUids = rawMembers.map((e) => e.toString()).toList();

    final rawTracks = data['tracks'] as List<dynamic>? ?? [];
    final tracks = rawTracks
        .whereType<Map<dynamic, dynamic>>()
        .map((t) => PlaylistTrack.fromMap(Map<String, dynamic>.from(t)))
        .toList();

    return Playlist(
      id: id ?? data['id'] as String? ?? '',
      name: data['name'] as String? ?? 'Untitled Playlist',
      description: data['description'] as String? ?? '',
      ownerUid: data['ownerUid'] as String? ?? '',
      ownerName: data['ownerName'] as String? ?? 'Aura User',
      memberUids: memberUids,
      visibility: data['visibility'] as String? ?? (data['isPublic'] == true ? 'public' : 'private'),
      collabEnabled: (data['collabEnabled'] as bool?) ?? false,
      type: data['type'] as String? ?? 'custom',
      createdAt: parseDate(data['createdAt']),
      updatedAt: parseDate(data['updatedAt']),
      trackCount: (data['trackCount'] as num?)?.toInt() ?? tracks.length,
      tracks: tracks,
      shareCode: data['shareCode'] as String? ?? data['inviteCode'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'ownerUid': ownerUid,
      'ownerName': ownerName,
      'memberUids': memberUids,
      'visibility': visibility,
      'isPublic': isPublic,
      'collabEnabled': collabEnabled,
      'type': type,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'trackCount': tracks.length,
      'tracks': tracks.map((t) => t.toMap()).toList(),
      if (shareCode != null && shareCode!.isNotEmpty) 'shareCode': shareCode,
    };
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'ownerUid': ownerUid,
      'ownerName': ownerName,
      'memberUids': memberUids,
      'visibility': visibility,
      'isPublic': isPublic,
      'collabEnabled': collabEnabled,
      'type': type,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'trackCount': tracks.length,
      'tracks': tracks.map((t) => t.toMap()).toList(),
      if (shareCode != null && shareCode!.isNotEmpty) 'shareCode': shareCode,
    };
  }

  Playlist copyWith({
    String? id,
    String? name,
    String? description,
    String? ownerUid,
    String? ownerName,
    List<String>? memberUids,
    String? visibility,
    bool? collabEnabled,
    String? type,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? trackCount,
    List<PlaylistTrack>? tracks,
    String? shareCode,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      ownerUid: ownerUid ?? this.ownerUid,
      ownerName: ownerName ?? this.ownerName,
      memberUids: memberUids ?? this.memberUids,
      visibility: visibility ?? this.visibility,
      collabEnabled: collabEnabled ?? this.collabEnabled,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      trackCount: trackCount ?? this.trackCount,
      tracks: tracks ?? this.tracks,
      shareCode: shareCode ?? this.shareCode,
    );
  }
}

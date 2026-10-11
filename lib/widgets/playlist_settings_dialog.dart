import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import '../providers/customization_provider.dart';
import '../services/auth/auth_service.dart';
import '../services/storage/storage_service.dart';
import '../services/sync/playlist_cloud_sync_service.dart';
import '../services/playlist/playlist_repository.dart';
import '../models/playlist_track.dart';
import '../themes/app_theme.dart';
import 'auth_dialog.dart';

class PlaylistSettingsModal extends ConsumerStatefulWidget {
  final Map<String, dynamic> playlist;
  final List<Track> tracks;
  final ValueChanged<Map<String, dynamic>> onUpdated;

  const PlaylistSettingsModal({
    super.key,
    required this.playlist,
    required this.tracks,
    required this.onUpdated,
  });

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> playlist,
    required List<Track> tracks,
    required ValueChanged<Map<String, dynamic>> onUpdated,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PlaylistSettingsModal(
        playlist: playlist,
        tracks: tracks,
        onUpdated: onUpdated,
      ),
    );
  }

  @override
  ConsumerState<PlaylistSettingsModal> createState() => _PlaylistSettingsModalState();
}

class _PlaylistSettingsModalState extends ConsumerState<PlaylistSettingsModal> {
  late TextEditingController _nameController;
  late TextEditingController _descController;
  late TextEditingController _authorController;

  late bool _isPublic;
  late bool _isSyncEnabled;
  late String _shareCode;
  late bool _isOwner;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.playlist['name']?.toString() ?? '');
    _descController = TextEditingController(text: widget.playlist['description']?.toString() ?? '');
    
    final currentAuthor = widget.playlist['authorName']?.toString().isNotEmpty == true
        ? widget.playlist['authorName']!.toString()
        : (AuthService.instance.currentUserName.isNotEmpty
            ? AuthService.instance.currentUserName
            : StorageService.getUserAuthorName());
    _authorController = TextEditingController(text: currentAuthor);

    _isPublic = widget.playlist['isPublic'] == true;
    _isSyncEnabled = widget.playlist['isSyncEnabled'] == true;

    _shareCode = widget.playlist['shareCode']?.toString().trim() ?? '';
    _isOwner = AuthService.instance.isPlaylistOwner(widget.playlist);

    // Resolve canonical invite code from Firestore if missing or collaborative
    final pid = widget.playlist['id']?.toString() ?? '';
    if (pid.isNotEmpty) {
      PlaylistRepository().getInviteCodeForPlaylist(pid).then((code) {
        if (code != null && code.isNotEmpty && mounted) {
          setState(() {
            _shareCode = code;
          });
        }
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _authorController.dispose();
    super.dispose();
  }

  Future<void> _checkAuthAndToggle(bool targetVal, {required bool isPublicToggle}) async {
    if (!_isOwner) return;

    if (AuthService.instance.isGuest && targetVal) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isPublicToggle
                ? 'Guest accounts cannot make playlists public. Please link or sign in with an account in Settings.'
                : 'Guest accounts cannot enable collaborative sync. Please link or sign in with an account in Settings.',
          ),
          backgroundColor: Colors.orangeAccent.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!AuthService.instance.isLoggedIn && targetVal) {
      final prompt = isPublicToggle
          ? 'Sign in or create a free account to make playlists public in the global directory!'
          : 'Sign in or create a free account to enable collaborative cloud sync!';
      final loggedIn = await AuthModalDialog.show(context, featurePrompt: prompt);
      if (loggedIn) {
        setState(() {
          if (isPublicToggle) {
            _isPublic = true;
          } else {
            _isSyncEnabled = true;
          }
        });
      }
      return;
    }

    setState(() {
      if (isPublicToggle) {
        _isPublic = targetVal;
      } else {
        _isSyncEnabled = targetVal;
      }
    });
  }

  Future<void> _handleSave() async {
    if (!_isOwner) {
      Navigator.pop(context);
      return;
    }

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Playlist title cannot be empty')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final desc = _descController.text.trim();
      final author = _authorController.text.trim().isEmpty ? StorageService.getUserAuthorName() : _authorController.text.trim();
      await StorageService.setUserAuthorName(author);

      final playlistId = widget.playlist['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
      String? syncId = widget.playlist['syncId']?.toString();
      final ownerId = widget.playlist['ownerId']?.toString() ?? AuthService.instance.currentUserId;
      final ownerEmail = widget.playlist['ownerEmail']?.toString() ?? AuthService.instance.currentUserEmail ?? '';

      // Legacy cloud slot wrapped in try-catch to prevent Dio errors
      try {
        if ((_isSyncEnabled || _isPublic) && (syncId == null || syncId.isEmpty)) {
          syncId = await PlaylistCloudSyncService.instance.createCloudSyncSlot(
            localId: playlistId,
            name: name,
            description: desc,
            authorName: author,
            isPublic: _isPublic,
            isSyncEnabled: _isSyncEnabled,
            tracks: widget.tracks,
            shareCode: _shareCode,
            ownerId: ownerId,
            ownerEmail: ownerEmail,
          );
        } else if (syncId != null && syncId.isNotEmpty) {
          await PlaylistCloudSyncService.instance.updateCloudSlot(
            syncId: syncId,
            name: name,
            description: desc,
            authorName: author,
            isPublic: _isPublic,
            isSyncEnabled: _isSyncEnabled,
            tracks: widget.tracks,
            shareCode: _shareCode,
            ownerId: ownerId,
            ownerEmail: ownerEmail,
          );
        }
      } catch (dioE) {
        debugPrint('Legacy PlaylistCloudSync notice (safe): $dioE');
      }

      // Sync to Firestore (primary backend for public explore and collaboration)
      if (AuthService.instance.isLoggedIn) {
        try {
          final repo = PlaylistRepository();
          final existing = await repo.getPlaylist(playlistId);
          if (existing != null) {
            await repo.updatePlaylistDetails(
              playlistId: playlistId,
              name: name,
              description: desc,
              callerUid: ownerId,
            );
            await repo.updateVisibility(
              playlistId,
              _isPublic ? 'public' : 'private',
              ownerId,
            );
            if (_isSyncEnabled && !existing.collabEnabled) {
              try {
                _shareCode = await repo.enableCollaboration(playlistId, ownerId);
              } catch (_) {}
            } else if (!_isSyncEnabled && existing.collabEnabled) {
              try {
                await repo.disableCollaboration(playlistId, ownerId);
              } catch (_) {}
            }
          } else {
            final created = await repo.createPlaylist(
              id: playlistId,
              name: name,
              description: desc,
              ownerUid: ownerId,
              ownerName: author,
              visibility: _isPublic ? 'public' : 'private',
              collabEnabled: _isSyncEnabled,
              initialTracks: widget.tracks.map((t) => PlaylistTrack.fromTrack(t, addedByUid: ownerId, addedByName: author)).toList(),
              shareCode: _shareCode.isNotEmpty ? _shareCode : null,
            );
            if (_isSyncEnabled) {
              try {
                _shareCode = created.shareCode ?? await repo.enableCollaboration(created.id, ownerId);
              } catch (_) {}
            }
          }
        } catch (e) {
          debugPrint('Error syncing playlist to Firestore in settings dialog: $e');
        }
      }

      final updatedPlaylist = {
        ...widget.playlist,
        'name': name,
        'description': desc,
        'authorName': author,
        'isPublic': _isPublic,
        'isSyncEnabled': _isSyncEnabled,
        'shareCode': _shareCode,
        'ownerId': ownerId,
        'ownerEmail': ownerEmail,
        'ownerName': author,
        if (syncId != null) 'syncId': syncId,
      };

      await StorageService.updatePlaylist(playlistId, updatedPlaylist);
      widget.onUpdated(updatedPlaylist);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved settings for "$name"! 🎉'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save settings: $e')),
        );
      }
    }
  }

  void _copyShareCode() {
    Clipboard.setData(ClipboardData(text: _shareCode));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied code "$_shareCode" to clipboard! 📋'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showCollaboratorsDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CollaboratorsModalSheet(
        playlist: widget.playlist,
        tracks: widget.tracks,
        shareCode: _shareCode,
        isSyncEnabled: _isSyncEnabled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = ref.watch(customizationProvider).accentColor;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1B1F) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.settings_rounded, color: accentColor, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Playlist Settings ⚙️',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isOwner ? 'Manage visibility, collaboration, and code' : 'View playlist info (Read Only)',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Non-Owner Locked Warning Banner
            if (!_isOwner) ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.handshake_rounded, color: Colors.amber, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Collaborator Mode 🤝: This playlist is owned by ${widget.playlist['authorName'] ?? widget.playlist['ownerName'] ?? 'another user'}. Only the owner can modify playlist title, visibility, or collaboration rules.',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.amber),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Unique Playlist Code Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accentColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.tag_rounded, color: accentColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'UNIQUE PLAYLIST CODE',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8),
                        ),
                        Row(
                          children: [
                            Flexible(
                              child: SelectableText(
                                _shareCode.isNotEmpty
                                    ? _shareCode
                                    : 'AURA-CODE',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                  color: accentColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _isSyncEnabled
                                    ? Colors.greenAccent.withValues(alpha: 0.15)
                                    : Colors.orangeAccent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: _isSyncEnabled
                                      ? Colors.greenAccent.withValues(alpha: 0.4)
                                      : Colors.orangeAccent.withValues(alpha: 0.4),
                                  width: 0.5,
                                ),
                              ),
                              child: Text(
                                _isSyncEnabled ? 'Collab 🔄' : 'Read-Only 🔒',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: _isSyncEnabled ? Colors.greenAccent : Colors.orangeAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _shareCode.isNotEmpty ? _copyShareCode : null,
                    tooltip: 'Copy Code',
                    icon: Icon(Icons.copy_rounded, color: _shareCode.isNotEmpty ? accentColor : Colors.grey, size: 20),
                  ),
                ],
              ),
            ),

            // View Collaborators Button
            InkWell(
              onTap: _showCollaboratorsDialog,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.people_alt_rounded, color: accentColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'View Collaborators 👥',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: accentColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Members',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: accentColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'See who joined and contributed songs to this playlist',
                            style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, size: 14, color: accentColor),
                  ],
                ),
              ),
            ),

            // Playlist Title Field
            TextField(
              controller: _nameController,
              readOnly: !_isOwner,
              decoration: InputDecoration(
                labelText: 'Playlist Title',
                prefixIcon: Icon(Icons.title_rounded, color: accentColor, size: 20),
                filled: true,
                fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: accentColor, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Description Field
            TextField(
              controller: _descController,
              readOnly: !_isOwner,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Description (Optional)',
                prefixIcon: Icon(Icons.description_rounded, color: accentColor, size: 20),
                filled: true,
                fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: accentColor, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Author Name Field (Read Only)
            TextField(
              controller: _authorController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Playlist Owner / Author',
                helperText: 'Loaded directly from account profile 🔒',
                prefixIcon: Icon(Icons.verified_user_rounded, color: accentColor, size: 20),
                suffixIcon: const Tooltip(
                  message: 'Owner name matches your signed-in account profile',
                  child: Icon(Icons.lock_rounded, size: 18, color: Colors.grey),
                ),
                filled: true,
                fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: accentColor, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Public Visibility Toggle
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _isPublic ? accentColor.withValues(alpha: 0.4) : (isDark ? Colors.white10 : Colors.black12)),
              ),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isPublic,
                activeThumbColor: accentColor,
                title: Row(
                  children: [
                    Icon(_isPublic ? Icons.public_rounded : Icons.lock_outline_rounded, size: 20, color: _isPublic ? accentColor : Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isPublic ? 'Public Playlist (🌐 Discoverable)' : 'Private Playlist (🔒 Hidden)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  !_isOwner
                      ? 'Locked by original creator'
                      : _isPublic
                          ? 'Visible in the Global Playlists feed for all Aura users'
                          : 'Hidden from global feed. Discoverable only by unique code',
                  style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black54),
                ),
                onChanged: _isOwner
                    ? (val) => _checkAuthAndToggle(val, isPublicToggle: true)
                    : null,
              ),
            ),
            const SizedBox(height: 12),

            // Collaborative Sync Toggle
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _isSyncEnabled ? accentColor.withValues(alpha: 0.4) : (isDark ? Colors.white10 : Colors.black12)),
              ),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isSyncEnabled,
                activeThumbColor: accentColor,
                title: Row(
                  children: [
                    Icon(Icons.sync_rounded, size: 20, color: _isSyncEnabled ? accentColor : Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isSyncEnabled ? 'Allow Collaborative Sync (🔄)' : 'Read-Only Playlist (🔒)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  !_isOwner
                      ? 'Locked by original creator'
                      : _isSyncEnabled
                          ? 'Collaborators can add songs and merge changes via cloud sync'
                          : 'Collaborators cannot push song additions to this playlist',
                  style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black54),
                ),
                onChanged: _isOwner
                    ? (val) => _checkAuthAndToggle(val, isPublicToggle: false)
                    : null,
              ),
            ),
            const SizedBox(height: 24),

            // Save / Close Button
            ElevatedButton(
              onPressed: _isSaving ? null : _handleSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 2,
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : Text(
                      _isOwner ? 'Save Settings' : 'Done',
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollaboratorsModalSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> playlist;
  final List<Track> tracks;
  final String shareCode;
  final bool isSyncEnabled;

  const _CollaboratorsModalSheet({
    required this.playlist,
    required this.tracks,
    required this.shareCode,
    required this.isSyncEnabled,
  });

  @override
  ConsumerState<_CollaboratorsModalSheet> createState() => _CollaboratorsModalSheetState();
}

class _CollaboratorsModalSheetState extends ConsumerState<_CollaboratorsModalSheet> {
  bool _isLoading = true;
  Playlist? _remotePlaylist;
  final Map<String, String> _memberNames = {};

  @override
  void initState() {
    super.initState();
    _fetchRemoteDetails();
  }

  Future<void> _fetchRemoteDetails() async {
    final pid = widget.playlist['id']?.toString() ?? '';
    if (pid.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final pl = await PlaylistRepository().getPlaylist(pid);
      if (pl != null && mounted) {
        _remotePlaylist = pl;

        // Fetch display names for any memberUids
        for (final uid in pl.memberUids) {
          if (uid != pl.ownerUid && !_memberNames.containsKey(uid)) {
            try {
              final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
              if (userDoc.exists && mounted) {
                final d = userDoc.data();
                final name = d?['displayName']?.toString() ?? d?['name']?.toString() ?? '';
                if (name.isNotEmpty) {
                  _memberNames[uid] = name;
                }
              }
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('_fetchRemoteDetails error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _copyCode() {
    if (widget.shareCode.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: widget.shareCode));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Copied invite code "${widget.shareCode}" to clipboard! 📋'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = ref.watch(customizationProvider).accentColor;

    final ownerName = _remotePlaylist?.ownerName ??
        widget.playlist['ownerName']?.toString() ??
        widget.playlist['authorName']?.toString() ??
        'Playlist Owner';
    final ownerUid = _remotePlaylist?.ownerUid ??
        widget.playlist['ownerId']?.toString() ??
        widget.playlist['ownerUid']?.toString() ??
        '';

    // Group track contributions
    int ownerSongCount = 0;
    final collaboratorContributions = <String, _CollaboratorItem>{};

    // 1. Scan tracks
    final rawTracks = widget.playlist['tracks'] as List? ?? [];
    if (rawTracks.isNotEmpty) {
      for (final raw in rawTracks) {
        if (raw is Map) {
          final addedUid = raw['addedByUid']?.toString() ?? '';
          final addedName = raw['addedBy']?.toString() ?? raw['addedByName']?.toString() ?? '';
          final isByOwner = (addedUid.isNotEmpty && addedUid == ownerUid) ||
              (addedUid.isEmpty && (addedName.isEmpty || addedName == ownerName));

          if (isByOwner) {
            ownerSongCount++;
          } else {
            final key = addedUid.isNotEmpty ? addedUid : addedName;
            if (collaboratorContributions.containsKey(key)) {
              collaboratorContributions[key]!.songCount++;
            } else {
              collaboratorContributions[key] = _CollaboratorItem(
                uid: addedUid,
                displayName: addedName.isNotEmpty ? addedName : (_memberNames[addedUid] ?? 'Collaborator'),
                songCount: 1,
              );
            }
          }
        }
      }
    } else {
      for (final t in widget.tracks) {
        final addedName = (t.addedBy ?? '').trim();
        final isByOwner = addedName.isEmpty || addedName == ownerName;
        if (isByOwner) {
          ownerSongCount++;
        } else {
          if (collaboratorContributions.containsKey(addedName)) {
            collaboratorContributions[addedName]!.songCount++;
          } else {
            collaboratorContributions[addedName] = _CollaboratorItem(
              uid: '',
              displayName: addedName,
              songCount: 1,
            );
          }
        }
      }
    }

    // 2. Add remote members who haven't added tracks yet
    if (_remotePlaylist != null) {
      for (final mUid in _remotePlaylist!.memberUids) {
        if (mUid != ownerUid && !collaboratorContributions.containsKey(mUid)) {
          final resolvedName = _memberNames[mUid] ?? 'Joined Collaborator';
          collaboratorContributions[mUid] = _CollaboratorItem(
            uid: mUid,
            displayName: resolvedName,
            songCount: 0,
          );
        }
      }
    }

    final collaboratorsList = collaboratorContributions.values.toList();
    final totalMembers = 1 + collaboratorsList.length;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1B1F) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.people_alt_rounded, color: accentColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Playlist Collaborators 👥',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.playlist['name'] ?? 'Playlist'} • $totalMembers ${totalMembers == 1 ? 'member' : 'members'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                children: [
                  // Owner Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: accentColor.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: accentColor,
                          child: const Icon(Icons.workspace_premium_rounded, color: Colors.black, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      ownerName,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: isDark ? Colors.white : Colors.black87,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.amber.withValues(alpha: 0.5), width: 0.5),
                                    ),
                                    child: const Text(
                                      'Owner 👑',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.amber,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$ownerSongCount ${ownerSongCount == 1 ? 'song' : 'songs'} added',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white70 : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Collaborator Items Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'COLLABORATORS (${collaboratorsList.length})',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                      if (widget.shareCode.isNotEmpty)
                        InkWell(
                          onTap: _copyCode,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.copy_rounded, size: 13, color: accentColor),
                              const SizedBox(width: 4),
                              Text(
                                'Copy Code',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: accentColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Collaborators List or Empty State
                  if (collaboratorsList.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.group_add_rounded, color: accentColor, size: 36),
                          const SizedBox(height: 10),
                          const Text(
                            'No collaborators have joined yet',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.isSyncEnabled
                                ? 'Share your unique playlist code with friends so they can join and add songs!'
                                : 'Enable "Allow Collaborative Sync" in settings to let friends join and add songs.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
                          ),
                          if (widget.shareCode.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            ElevatedButton.icon(
                              onPressed: _copyCode,
                              icon: const Icon(Icons.share_rounded, size: 16, color: Colors.black),
                              label: Text(
                                'Copy Invite Code (${widget.shareCode})',
                                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accentColor,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  else
                    ...collaboratorsList.map((collab) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: accentColor.withValues(alpha: 0.2),
                              child: Text(
                                (collab.displayName.isNotEmpty ? collab.displayName[0] : 'C').toUpperCase(),
                                style: TextStyle(
                                  color: accentColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          collab.displayName,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: isDark ? Colors.white : Colors.black87,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: Colors.blueAccent.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(5),
                                        ),
                                        child: const Text(
                                          'Collaborator 🤝',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blueAccent,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    collab.songCount > 0
                                        ? '${collab.songCount} ${collab.songCount == 1 ? 'song' : 'songs'} contributed'
                                        : 'Joined via invite code',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: isDark ? Colors.white60 : Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          const SizedBox(height: 16),

          // Close button
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              side: BorderSide(color: isDark ? Colors.white24 : Colors.black26),
            ),
            child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _CollaboratorItem {
  final String uid;
  final String displayName;
  int songCount;

  _CollaboratorItem({
    required this.uid,
    required this.displayName,
    required this.songCount,
  });
}

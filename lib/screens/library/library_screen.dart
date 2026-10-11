import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../providers/playback_provider.dart';
import '../../providers/customization_provider.dart';
import '../../services/storage/storage_service.dart';
import '../../services/download/download_service.dart';
import '../../services/import/spotify_import_service.dart';
import '../../themes/app_theme.dart';
import '../../widgets/app_artwork_image.dart';
import 'playlist_detail_screen.dart';
import 'recently_played_screen.dart';
import 'spotify_import_preview_screen.dart';
import 'package:flutter/services.dart';
import '../../services/sharing/playlist_link_share_service.dart';
import '../sharing/remote_link_share_modal.dart';
import '../../widgets/playlist_imported_dialog.dart';
import 'global_playlists_screen.dart';
import 'explore_playlists_screen.dart';
import '../../services/playlist/playlist_repository.dart';
import '../../services/sync/playlist_cloud_sync_service.dart';
import '../../services/auth/auth_service.dart';
import '../../widgets/auth_dialog.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _playlistNameController = TextEditingController();
  final TextEditingController _playlistDescController = TextEditingController();
  final TextEditingController _spotifyUrlController = TextEditingController();
  List<Map<String, dynamic>> _playlists = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadPlaylists();
    AuthService.instance.playlistsChangedNotifier.addListener(_loadPlaylists);
    PlaylistLinkShareService.importEventNotifier.addListener(_loadPlaylists);
  }

  @override
  void dispose() {
    AuthService.instance.playlistsChangedNotifier.removeListener(_loadPlaylists);
    PlaylistLinkShareService.importEventNotifier.removeListener(_loadPlaylists);
    _tabController.dispose();
    _playlistNameController.dispose();
    _playlistDescController.dispose();
    _spotifyUrlController.dispose();
    super.dispose();
  }

  void _loadPlaylists() {
    setState(() {
      _playlists = StorageService.getPlaylists();
    });
  }

  void _showAddPlaylistModal({int initialTab = 0}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = ref.read(customizationProvider).accentColor;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        int selectedTab = initialTab;
        String? inlineError;
        bool isLoading = false;
        bool newPlaylistIsPublic = false;
        bool newPlaylistIsSyncEnabled = true;
        final accountName = AuthService.instance.currentUserName.isNotEmpty
            ? AuthService.instance.currentUserName
            : StorageService.getUserAuthorName();
        final authorController = TextEditingController(text: accountName);

        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            return Container(
              padding: EdgeInsets.only(
                left: 24, 
                right: 24, 
                top: 20, 
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
              ),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetContext).size.height * 0.88,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1B1B1E) : Colors.white,
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
                        color: Colors.grey.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        selectedTab == 0 ? 'Import Playlist 📥' : 'Create Playlist 🎵',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Outfit',
                          color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Two-way Sliding Bar Selector
                  Container(
                    height: 46,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(23),
                      border: Border.all(
                        color: isDark ? Colors.white12 : Colors.black12,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Sliding Tab 1: Import
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setModalState(() {
                                selectedTab = 0;
                                inlineError = null;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeInOut,
                              decoration: BoxDecoration(
                                color: selectedTab == 0 ? accentColor : Colors.transparent,
                                borderRadius: BorderRadius.circular(19),
                                boxShadow: selectedTab == 0
                                    ? [
                                        BoxShadow(
                                          color: accentColor.withValues(alpha: 0.35),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : [],
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.download_rounded,
                                    size: 17,
                                    color: selectedTab == 0 ? Colors.black : (isDark ? Colors.white70 : Colors.black54),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Import Playlist',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Outfit',
                                      color: selectedTab == 0 ? Colors.black : (isDark ? Colors.white70 : Colors.black54),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Sliding Tab 2: Create Playlist
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setModalState(() {
                                selectedTab = 1;
                                inlineError = null;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeInOut,
                              decoration: BoxDecoration(
                                color: selectedTab == 1 ? accentColor : Colors.transparent,
                                borderRadius: BorderRadius.circular(19),
                                boxShadow: selectedTab == 1
                                    ? [
                                        BoxShadow(
                                          color: accentColor.withValues(alpha: 0.35),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : [],
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.add_rounded,
                                    size: 17,
                                    color: selectedTab == 1 ? Colors.black : (isDark ? Colors.white70 : Colors.black54),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Create Playlist',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Outfit',
                                      color: selectedTab == 1 ? Colors.black : (isDark ? Colors.white70 : Colors.black54),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // TAB CONTENT
                  if (selectedTab == 0) ...[
                    // --- TAB 0: IMPORT PLAYLIST ---
                    Text(
                      'Paste an Aura shared link, playlist code, or Spotify URL:',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _spotifyUrlController,
                      enabled: !isLoading,
                      autofocus: true,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: 'e.g. 7KX9Y2 or aura://share?dpc=... or Spotify URL',
                        hintStyle: TextStyle(
                          fontSize: 12.5,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                        errorText: inlineError,
                        prefixIcon: Icon(Icons.link_rounded, color: accentColor, size: 20),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_spotifyUrlController.text.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () {
                                  _spotifyUrlController.clear();
                                  setModalState(() {
                                    inlineError = null;
                                  });
                                },
                              ),
                            TextButton(
                              onPressed: () async {
                                final data = await Clipboard.getData(Clipboard.kTextPlain);
                                if (data?.text != null && data!.text!.trim().isNotEmpty) {
                                  _spotifyUrlController.text = data.text!.trim();
                                  setModalState(() {
                                    inlineError = null;
                                  });
                                }
                              },
                              child: Text(
                                'PASTE',
                                style: TextStyle(
                                  color: accentColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
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
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      onChanged: (_) {
                        if (inlineError != null) {
                          setModalState(() {
                            inlineError = null;
                          });
                        }
                      },
                    ),

                    const SizedBox(height: 22),

                    ElevatedButton(
                      onPressed: isLoading
                          ? null
                          : () async {
                              final input = _spotifyUrlController.text.trim();
                              if (input.isEmpty) {
                                setModalState(() {
                                  inlineError = 'Please enter a playlist code or paste a link.';
                                });
                                return;
                              }

                              setModalState(() {
                                isLoading = true;
                                inlineError = null;
                              });

                              try {
                                // 0. Attempt Firestore Collaborative Invite Code join
                                if (AuthService.instance.isLoggedIn) {
                                  try {
                                    final repo = PlaylistRepository();
                                    final joinedPl = await repo.joinByInviteCode(
                                      input,
                                      AuthService.instance.currentUserId,
                                      AuthService.instance.currentUserName,
                                    );
                                    await AuthService.instance.restoreUserPlaylists();
                                    if (mounted) {
                                      Navigator.pop(sheetContext);
                                      _loadPlaylists();
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          backgroundColor: const Color(0xFF2E7D32),
                                          content: Text('Joined collaborative playlist "${joinedPl.name}"! 🎵'),
                                        ),
                                      );
                                    }
                                    return;
                                  } catch (e) {
                                    // If code wasn't a valid invite code, fallback to legacy/links below
                                  }
                                }

                                // 1. Attempt Cloud Share Code lookup (e.g. AURA-7K9X2B)
                                final cloudByCode = await PlaylistCloudSyncService.instance.fetchPlaylistByShareCode(input);
                                if (cloudByCode != null) {
                                  final List<Track> tracks = List<Track>.from(cloudByCode['tracks'] as List? ?? []);
                                  final currentUserId = AuthService.instance.currentUserId;
                                  final currentUserEmail = (AuthService.instance.currentUserEmail ?? '').trim().toLowerCase();
                                  final currentUserName = AuthService.instance.currentUserName.trim().toLowerCase();

                                  final codeOwnerId = cloudByCode['ownerId']?.toString() ?? '';
                                  final codeOwnerEmail = (cloudByCode['ownerEmail']?.toString() ?? '').trim().toLowerCase();
                                  final codeAuthor = (cloudByCode['authorName']?.toString() ?? '').trim().toLowerCase();

                                  final isMyOwnPlaylist = AuthService.instance.isLoggedIn && (
                                    (codeOwnerId.isNotEmpty && codeOwnerId == currentUserId) ||
                                    (codeOwnerEmail.isNotEmpty && codeOwnerEmail == currentUserEmail) ||
                                    (codeAuthor.isNotEmpty && codeAuthor == currentUserName && (codeOwnerId.isEmpty || codeOwnerId == currentUserId))
                                  );

                                  final newPl = {
                                    'id': DateTime.now().millisecondsSinceEpoch.toString(),
                                    'name': cloudByCode['name']?.toString() ?? 'Shared Playlist',
                                    'description': cloudByCode['description']?.toString() ?? 'Imported via Playlist Code',
                                    'authorName': cloudByCode['authorName']?.toString() ?? 'Community Member',
                                    'ownerId': isMyOwnPlaylist ? currentUserId : codeOwnerId,
                                    'ownerEmail': isMyOwnPlaylist ? (AuthService.instance.currentUserEmail ?? codeOwnerEmail) : codeOwnerEmail,
                                    'ownerName': cloudByCode['authorName']?.toString() ?? '',
                                    'isImported': !isMyOwnPlaylist,
                                    'isPublic': cloudByCode['isPublic'] == true,
                                    'isSyncEnabled': cloudByCode['isSyncEnabled'] == true,
                                    'shareCode': cloudByCode['shareCode']?.toString() ?? input.toUpperCase(),
                                    'syncId': cloudByCode['syncId']?.toString(),
                                    'trackIds': tracks.map((t) => t.id).toList(),
                                    'syncedTrackIds': tracks.map((t) => t.id).toList(),
                                    'tracks': tracks.map((t) => t.toJson()).toList(),
                                  };
                                  final playlists = StorageService.getPlaylists();
                                  playlists.insert(0, newPl);
                                  await StorageService.savePlaylists(playlists);

                                  final importEvent = PlaylistImportEvent(
                                    title: newPl['name'].toString(),
                                    description: newPl['description'].toString(),
                                    trackCount: tracks.length,
                                    tracks: tracks,
                                    fromQrScan: false,
                                  );

                                  Navigator.pop(sheetContext);
                                  _spotifyUrlController.clear();
                                  _loadPlaylists();

                                  if (context.mounted) {
                                    PlaylistImportSuccessDialog.show(context, importEvent, ref);
                                  }
                                  return;
                                }

                                // 2. Attempt Aura Link or code decode
                                final decodedAura = await PlaylistLinkShareService.instance.decodeShareableLinkAsync(input);
                                if (decodedAura != null && decodedAura.tracks.isNotEmpty) {
                                  final newPl = {
                                    'id': DateTime.now().millisecondsSinceEpoch.toString(),
                                    'name': decodedAura.title,
                                    'description': decodedAura.description.isNotEmpty
                                        ? decodedAura.description
                                        : 'Imported via Shared Code / Link',
                                    'trackIds': decodedAura.tracks.map((t) => t.id).toList(),
                                    'tracks': decodedAura.tracks.map((t) => t.toJson()).toList(),
                                  };
                                  final playlists = StorageService.getPlaylists();
                                  playlists.insert(0, newPl);
                                  await StorageService.savePlaylists(playlists);

                                  final importEvent = PlaylistImportEvent(
                                    title: decodedAura.title,
                                    description: decodedAura.description,
                                    trackCount: decodedAura.tracks.length,
                                    tracks: decodedAura.tracks,
                                    fromQrScan: false,
                                  );

                                  Navigator.pop(sheetContext);
                                  _spotifyUrlController.clear();
                                  _loadPlaylists();

                                  // Show the celebratory popup!
                                  if (context.mounted) {
                                    PlaylistImportSuccessDialog.show(context, importEvent, ref);
                                  }
                                  return;
                                }

                                // 2. Attempt Spotify URL import
                                final playlistId = SpotifyImportService.instance.validateAndExtractPlaylistId(input);
                                if (playlistId != null) {
                                  final preview = await SpotifyImportService.instance.fetchPlaylistPreview(input);
                                  Navigator.pop(sheetContext);
                                  _spotifyUrlController.clear();

                                  if (context.mounted) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => SpotifyImportPreviewScreen(preview: preview),
                                      ),
                                    ).then((_) => _loadPlaylists());
                                  }
                                  return;
                                }

                                setModalState(() {
                                  isLoading = false;
                                  inlineError = 'Could not find or decode playlist. Please check your code or link.';
                                });
                              } catch (e) {
                                setModalState(() {
                                  isLoading = false;
                                  inlineError = 'Failed to load playlist: $e';
                                });
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 2,
                      ),
                      child: isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const Text(
                              'Import Playlist',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                    ),
                  ] else ...[
                    // --- TAB 1: CREATE PLAYLIST ---
                    Text(
                      'Give your new playlist a title and optional description:',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _playlistNameController,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Playlist Title',
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
                    const SizedBox(height: 12),
                    TextField(
                      controller: _playlistDescController,
                      decoration: InputDecoration(
                        labelText: 'Description (Optional)',
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
                    const SizedBox(height: 12),
                    TextField(
                      controller: authorController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Playlist Owner / Author',
                        helperText: 'Loaded directly from your account name 🔒',
                        helperStyle: TextStyle(fontSize: 11, color: accentColor.withValues(alpha: 0.8)),
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
                    const SizedBox(height: 14),

                    // Public / Private Switch
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: newPlaylistIsPublic ? accentColor.withValues(alpha: 0.4) : (isDark ? Colors.white10 : Colors.black12)),
                      ),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: newPlaylistIsPublic,
                        activeThumbColor: accentColor,
                        title: Row(
                          children: [
                            Icon(newPlaylistIsPublic ? Icons.public_rounded : Icons.lock_outline_rounded, size: 18, color: newPlaylistIsPublic ? accentColor : Colors.grey),
                            const SizedBox(width: 8),
                            Text(
                              newPlaylistIsPublic ? 'Public (Global Feed) 🌐' : 'Private (Hidden) 🔒',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          newPlaylistIsPublic ? 'Discoverable in the Global Playlists screen' : 'Only users with your direct link can access',
                          style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white54 : Colors.black54),
                        ),
                        onChanged: (val) async {
                          if (val && !AuthService.instance.isLoggedIn) {
                            final loggedIn = await AuthModalDialog.show(
                              context,
                              featurePrompt: 'Please sign in or create a free account to make playlists public!',
                            );
                            if (loggedIn) {
                              setModalState(() => newPlaylistIsPublic = true);
                            }
                            return;
                          }
                          setModalState(() => newPlaylistIsPublic = val);
                        },
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Collaborative Sync Switch
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: newPlaylistIsSyncEnabled ? accentColor.withValues(alpha: 0.4) : (isDark ? Colors.white10 : Colors.black12)),
                      ),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: newPlaylistIsSyncEnabled,
                        activeThumbColor: accentColor,
                        title: Row(
                          children: [
                            Icon(Icons.sync_rounded, size: 18, color: newPlaylistIsSyncEnabled ? accentColor : Colors.grey),
                            const SizedBox(width: 8),
                            Text(
                              newPlaylistIsSyncEnabled ? 'Allow Collaborative Sync 🔄' : 'Read-Only (No Sync) 🔒',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          newPlaylistIsSyncEnabled ? 'Others can add songs & sync updates' : 'Collaborators cannot push songs to this playlist',
                          style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white54 : Colors.black54),
                        ),
                        onChanged: (val) async {
                          if (val && !AuthService.instance.isLoggedIn) {
                            final loggedIn = await AuthModalDialog.show(
                              context,
                              featurePrompt: 'Please sign in or create a free account to enable collaborative sync!',
                            );
                            if (loggedIn) {
                              setModalState(() => newPlaylistIsSyncEnabled = true);
                            }
                            return;
                          }
                          setModalState(() => newPlaylistIsSyncEnabled = val);
                        },
                      ),
                    ),
                    const SizedBox(height: 20),

                    ElevatedButton(
                      onPressed: isLoading
                          ? null
                          : () async {
                              final name = _playlistNameController.text.trim();
                              final desc = _playlistDescController.text.trim();
                              final author = authorController.text.trim().isEmpty ? StorageService.getUserAuthorName() : authorController.text.trim();

                              if (name.isNotEmpty) {
                                setModalState(() => isLoading = true);
                                await StorageService.setUserAuthorName(author);

                                String plId = DateTime.now().millisecondsSinceEpoch.toString();
                                String shareCode = '';
                                final ownerId = AuthService.instance.currentUserId;
                                final ownerEmail = AuthService.instance.currentUserEmail ?? '';
                                String? syncId;

                                // Create in Cloud Firestore (for Explore screen and Collaboration)
                                if (AuthService.instance.isLoggedIn) {
                                  try {
                                    final repo = PlaylistRepository();
                                    final firestorePlaylist = await repo.createPlaylist(
                                      id: plId,
                                      name: name,
                                      description: desc,
                                      ownerUid: ownerId,
                                      ownerName: author,
                                      visibility: newPlaylistIsPublic ? 'public' : 'private',
                                      collabEnabled: newPlaylistIsSyncEnabled,
                                    );
                                    plId = firestorePlaylist.id;
                                    if (newPlaylistIsSyncEnabled) {
                                      try {
                                        shareCode = firestorePlaylist.shareCode ?? await repo.enableCollaboration(plId, ownerId);
                                      } catch (ce) {
                                        debugPrint('Collaboration code notice: $ce');
                                      }
                                    }
                                  } catch (e) {
                                    debugPrint('Firestore playlist create error: $e');
                                  }
                                }

                                if (newPlaylistIsPublic || newPlaylistIsSyncEnabled) {
                                  try {
                                    syncId = await PlaylistCloudSyncService.instance.createCloudSyncSlot(
                                      localId: plId,
                                      name: name,
                                      description: desc,
                                      authorName: author,
                                      isPublic: newPlaylistIsPublic,
                                      isSyncEnabled: newPlaylistIsSyncEnabled,
                                      tracks: [],
                                      shareCode: shareCode,
                                      ownerId: ownerId,
                                      ownerEmail: ownerEmail,
                                    );
                                  } catch (dioE) {
                                    debugPrint('Legacy createCloudSyncSlot notice (safe): $dioE');
                                  }
                                }

                                final playlists = StorageService.getPlaylists();
                                final newPl = {
                                  'id': plId,
                                  'name': name,
                                  'description': desc.isNotEmpty ? desc : 'A custom playlist',
                                  'authorName': author,
                                  'ownerId': ownerId,
                                  'ownerEmail': ownerEmail,
                                  'ownerName': author,
                                  'isImported': false,
                                  'isPublic': newPlaylistIsPublic,
                                  'isSyncEnabled': newPlaylistIsSyncEnabled,
                                  'shareCode': shareCode,
                                  if (syncId != null) 'syncId': syncId,
                                  'trackIds': <String>[],
                                  'tracks': <Map<String, dynamic>>[],
                                };
                                playlists.add(newPl);
                                await StorageService.savePlaylists(playlists);

                                _playlistNameController.clear();
                                _playlistDescController.clear();
                                _loadPlaylists();
                                Navigator.pop(sheetContext);

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Created playlist "$name"! 🎉'),
                                    backgroundColor: accentColor,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 2,
                      ),
                      child: isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const Text(
                              'Create Playlist',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                    ),
                  ],
                ],
              ),
            ),
          );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final customBranding = ref.watch(customizationProvider);
    final accentColor = customBranding.accentColor;

    final favTracks = StorageService.getFavoriteTracks();
    final downloadedTracks = DownloadService.instance.getDownloadedTracksList();
    final historyList = StorageService.getListeningHistory();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Header & Title Bar
        Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: MediaQuery.of(context).padding.top + 8, bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your Library 📚',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_playlists.length} Playlists • ${favTracks.length} Liked • ${downloadedTracks.length} Offline',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                children: [
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.add_rounded, color: accentColor, size: 20),
                    ),
                    tooltip: 'Add / Import Playlist',
                    onPressed: () => _showAddPlaylistModal(initialTab: 0),
                  ),
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AuthService.instance.isLoggedIn
                            ? accentColor.withValues(alpha: 0.2)
                            : (isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.04)),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        AuthService.instance.isLoggedIn ? Icons.cloud_done_rounded : Icons.account_circle_outlined,
                        color: AuthService.instance.isLoggedIn ? accentColor : (isDark ? Colors.white70 : Colors.black54),
                        size: 20,
                      ),
                    ),
                    tooltip: AuthService.instance.isLoggedIn ? 'Cloud Account Active' : 'Sign In / Account',
                    onPressed: () async {
                      await AuthModalDialog.show(context, onLoggedIn: () {
                        if (mounted) _loadPlaylists();
                      });
                      if (mounted) _loadPlaylists();
                    },
                  ),
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.04),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.import_export_rounded, color: accentColor, size: 20),
                    ),
                    tooltip: 'Import Playlist',
                    onPressed: () => _showAddPlaylistModal(initialTab: 0),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 2. Quick Action Cards Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              _buildLibraryShortcutCard(
                context,
                'Favorites',
                '${favTracks.length} Tracks',
                Icons.favorite_rounded,
                accentColor,
                () => _tabController.animateTo(1),
              ),
              _buildLibraryShortcutCard(
                context,
                'Offline',
                '${downloadedTracks.length} Saved',
                Icons.download_done_rounded,
                accentColor,
                () => _tabController.animateTo(3),
              ),
              _buildLibraryShortcutCard(
                context,
                'History',
                '${historyList.length} Played',
                Icons.history_rounded,
                accentColor,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const RecentlyPlayedScreen()),
                  ).then((_) => _loadPlaylists());
                },
              ),
              _buildLibraryShortcutCard(
                context,
                'Explore 🌐',
                'Community',
                Icons.public_rounded,
                accentColor,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ExplorePlaylistsScreen()),
                  ).then((_) => _loadPlaylists());
                },
              ),
            ],
          ),
        ),

        // 3. Floating Segmented Tab Selector
        Container(
          height: 38,
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(20),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(18),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: Colors.black,
            unselectedLabelColor: isDark ? Colors.white54 : Colors.black54,
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(text: 'Playlists'),
              Tab(text: 'Liked Songs'),
              Tab(text: 'Albums'),
              Tab(text: 'Downloaded'),
            ],
          ),
        ),

        // 4. Main Tab Content Area
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildPlaylistsTab(accentColor),
              _buildLikedSongsTab(favTracks, accentColor),
              _buildAlbumsTab(favTracks, accentColor),
              _buildDownloadedTab(downloadedTracks, accentColor),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLibraryShortcutCard(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    Color accentColor,
    VoidCallback onTap,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accentColor.withValues(alpha: 0.2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: accentColor, size: 20),
              const SizedBox(height: 5),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 9.5, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Playlists Tab
  Widget _buildPlaylistsTab(Color accentColor) {
    if (_playlists.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.playlist_add_rounded, size: 56, color: accentColor.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text('No custom playlists created yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 6),
            const Text('Tap "+" in top right or import from Spotify!', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _showAddPlaylistModal(initialTab: 0),
              icon: const Icon(Icons.add_rounded, color: Colors.black, size: 18),
              label: const Text('Add / Import Playlist', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: accentColor),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ExplorePlaylistsScreen()),
                ).then((_) => _loadPlaylists());
              },
              icon: Icon(Icons.public_rounded, color: accentColor, size: 18),
              label: Text('Explore Global Playlists 🌐', style: TextStyle(color: accentColor, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: accentColor),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 150, top: 10, left: 20, right: 20),
      itemCount: _playlists.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accentColor.withValues(alpha: 0.18), isDark ? const Color(0xFF1E1E24) : Colors.white],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accentColor.withValues(alpha: 0.25)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: accentColor, shape: BoxShape.circle),
                child: const Icon(Icons.public_rounded, color: Colors.black, size: 20),
              ),
              title: const Text('Discover Global Playlists 🌐', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'Outfit')),
              subtitle: Text('Browse community public playlists', style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54)),
              trailing: Icon(Icons.arrow_forward_ios_rounded, size: 13, color: accentColor),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ExplorePlaylistsScreen()),
                ).then((_) => _loadPlaylists());
              },
            ),
          );
        }

        final playlist = _playlists[index - 1];
        final List rawTracks = playlist['tracks'] as List? ?? [];
        final List trackIds = playlist['trackIds'] as List? ?? [];
        final int songCount = rawTracks.isNotEmpty ? rawTracks.length : trackIds.length;
        final author = playlist['authorName']?.toString();
        final isPublic = playlist['isPublic'] == true;
        final isSync = playlist['isSyncEnabled'] == true;

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          color: isDark ? const Color(0xFF1E1E22) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.playlist_play_rounded, color: accentColor, size: 30),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(playlist['name'] ?? 'Playlist', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                if (isPublic) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.public_rounded, size: 13, color: Colors.blueAccent),
                ],
                if (isSync) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.sync_rounded, size: 13, color: Colors.greenAccent),
                ],
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Text(
                  author != null && author.isNotEmpty
                      ? '$songCount songs • By $author'
                      : '$songCount songs • ${playlist['description'] ?? 'Custom playlist'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (playlist['shareCode'] != null && playlist['shareCode'].toString().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.tag_rounded, size: 11, color: accentColor),
                      const SizedBox(width: 2),
                      Text(
                        playlist['shareCode'].toString(),
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: accentColor),
                      ),
                      if (playlist['isImported'] == true) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('Imported', style: TextStyle(fontSize: 9, color: Colors.amber, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.share_rounded, color: accentColor, size: 20),
                  tooltip: 'Share Playlist',
                  onPressed: () {
                    final List rawTracks = playlist['tracks'] ?? [];
                    final List<Track> playlistTracks = [];
                    if (rawTracks.isNotEmpty) {
                      for (final item in rawTracks) {
                        if (item is Map) {
                          playlistTracks.add(Track(
                            id: item['id']?.toString() ?? '',
                            title: item['title']?.toString() ?? 'Track',
                            artist: item['artist']?.toString() ?? 'Unknown Artist',
                            album: item['album']?.toString() ?? 'Album',
                            duration: item['duration']?.toString() ?? '3:30',
                            artworkUrl: item['artworkUrl']?.toString() ?? '',
                            audioUrl: item['audioUrl']?.toString() ?? '',
                            genre: item['genre']?.toString() ?? '',
                          ));
                        }
                      }
                    }
                    ShareOptionsModal.show(
                      context,
                      tracks: playlistTracks,
                      title: playlist['name']?.toString() ?? 'Custom Playlist',
                      description: playlist['description']?.toString() ?? '',
                    );
                  },
                ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              ],
            ),
            onTap: () {
              final actualIndex = index - 1;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PlaylistDetailScreen(
                    playlistIndex: actualIndex,
                    initialPlaylist: playlist,
                  ),
                ),
              ).then((_) => _loadPlaylists());
            },
          ),
        );
      },
    );
  }

  // Liked Songs Tab
  Widget _buildLikedSongsTab(List<Track> tracks, Color accentColor) {
    if (tracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_border_rounded, size: 56, color: accentColor.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text('No favorited songs yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 6),
            const Text('Heart any playing song to save it here!', style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      );
    }

    return Consumer(
      builder: (context, ref, child) {
        final notifier = ref.read(playbackProvider.notifier);
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 150, top: 8),
          itemCount: tracks.length,
          itemBuilder: (context, index) {
            final track = tracks[index];
            final isFav = StorageService.isFavorite('trackIds', track.id);
            
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              leading: AppArtworkImage(
                artworkUrl: track.artworkUrl,
                trackId: track.id,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(10),
              ),
              title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: Text('${track.artist} • ${track.album}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: isFav ? Colors.redAccent : Colors.grey,
                      size: 20,
                    ),
                    onPressed: () async {
                      await StorageService.toggleFavoriteTrack(track);
                      setState(() {});
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.play_circle_fill_rounded, size: 30, color: accentColor),
                    onPressed: () => notifier.playTrack(track),
                  ),
                ],
              ),
              onTap: () {
                notifier.playTrack(track);
              },
            );
          },
        );
      },
    );
  }

  // Albums Tab
  Widget _buildAlbumsTab(List<Track> tracks, Color accentColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Map<String, List<Track>> albumsMap = {};
    for (final track in tracks) {
      final albumName = track.album.trim().isNotEmpty ? track.album.trim() : 'Singles';
      albumsMap.putIfAbsent(albumName, () => []).add(track);
    }

    if (albumsMap.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.album_rounded, size: 56, color: accentColor.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text('No saved albums found', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.grey)),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 14, bottom: 150),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.82,
      ),
      itemCount: albumsMap.keys.length,
      itemBuilder: (context, index) {
        final albumName = albumsMap.keys.elementAt(index);
        final albumTracks = albumsMap[albumName]!;
        final firstTrack = albumTracks.first;

        return Consumer(
          builder: (context, ref, child) {
            return GestureDetector(
              onTap: () {
                ref.read(playbackProvider.notifier).playCustomQueue(albumTracks, initialIndex: 0);
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C1F) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accentColor.withValues(alpha: 0.2)),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: AppArtworkImage(
                          artworkUrl: firstTrack.artworkUrl,
                          trackId: firstTrack.id,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(albumName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text('${firstTrack.artist} • ${albumTracks.length} tracks', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Downloaded Offline Tab
  Widget _buildDownloadedTab(List<Track> downloadedTracks, Color accentColor) {
    final downloadedPlaylists = StorageService.getDownloadedPlaylists();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (downloadedTracks.isEmpty && downloadedPlaylists.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.download_done_rounded, size: 56, color: accentColor.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text('No offline downloads yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 6),
            const Text('Download songs to listen offline anytime!', style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 150, top: 12, left: 20, right: 20),
      children: [
        if (downloadedPlaylists.isNotEmpty) ...[
          const Text('Downloaded Playlists', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'Outfit')),
          const SizedBox(height: 10),
          ...downloadedPlaylists.map((pl) {
            final List rawTracks = pl['tracks'] ?? [];
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              color: isDark ? const Color(0xFF1E1E22) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.download_done_rounded, color: accentColor, size: 24),
                ),
                title: Text(pl['name'] ?? 'Playlist', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text('${rawTracks.length} songs saved offline'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                  onPressed: () async {
                    await StorageService.deleteDownloadedPlaylist(pl['name']);
                    setState(() {});
                  },
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
        ],

        if (downloadedTracks.isNotEmpty) ...[
          Text('Downloaded Tracks (${downloadedTracks.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'Outfit')),
          const SizedBox(height: 10),
          ...downloadedTracks.map((track) {
            return Consumer(
              builder: (context, ref, child) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: AppArtworkImage(
                    artworkUrl: track.artworkUrl,
                    trackId: track.id,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.play_circle_fill_rounded, size: 30, color: accentColor),
                        onPressed: () {
                          ref.read(playbackProvider.notifier).playTrack(track);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                        onPressed: () async {
                          await DownloadService.instance.deleteDownload(track.id);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                  onTap: () {
                    ref.read(playbackProvider.notifier).playTrack(track);
                  },
                );
              },
            );
          }),
        ],
      ],
    );
  }
}

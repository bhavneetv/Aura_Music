import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../models/user_model.dart';
import '../storage/storage_service.dart';

class AuthResult {
  final bool success;
  final String message;
  final UserModel? user;

  const AuthResult({
    required this.success,
    required this.message,
    this.user,
  });
}

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const String _apiBase = 'https://extendsclass.com/api/json-storage/bin';
  // Central master registry bin ID for zero-database account directory
  static const String _masterAccountsId = 'eecabce';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'AuraMusic/4.0',
      },
    ),
  );

  UserModel? _currentUser;
  final ValueNotifier<UserModel?> authState = ValueNotifier<UserModel?>(null);

  bool get isLoggedIn => _currentUser != null;
  UserModel? get currentUser => _currentUser;
  String get currentUserId => _currentUser?.id ?? StorageService.getDeviceId();
  String get currentUserName => _currentUser?.name ?? StorageService.getUserAuthorName();
  String? get currentUserEmail => _currentUser?.email;

  /// Initializes auth state from local persistence
  void init() {
    _currentUser = StorageService.getCurrentUser();
    authState.value = _currentUser;
    debugPrint('[Auth] Initialized. Logged in: $isLoggedIn (${_currentUser?.name ?? "Guest"})');
    if (_currentUser != null) {
      _claimLocalPlaylistsForUser(_currentUser!);
    }
  }

  /// Hashes a password deterministically with salt
  static String hashPassword(String password) {
    const salt = 'aura_cloud_music_salt_2026_';
    return _sha256Hex('$salt$password');
  }

  /// Register a new zero-database account
  Future<AuthResult> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final cleanName = name.trim();
    final cleanEmail = email.trim().toLowerCase();
    final cleanPassword = password.trim();

    if (cleanName.length < 2) {
      return const AuthResult(success: false, message: 'Please enter a name with at least 2 characters.');
    }
    if (!cleanEmail.contains('@') || !cleanEmail.contains('.')) {
      return const AuthResult(success: false, message: 'Please enter a valid email address.');
    }
    if (cleanPassword.length < 4) {
      return const AuthResult(success: false, message: 'Password must be at least 4 characters long.');
    }

    try {
      // 1. Fetch current accounts directory to check for duplicates
      final accountsMap = await _fetchAccountsDirectory();
      if (accountsMap.containsKey(cleanEmail)) {
        return const AuthResult(
          success: false,
          message: 'An account with this email already exists. Please log in.',
        );
      }

      final userId = 'usr_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
      final passHash = hashPassword(cleanPassword);

      // 2. Create personal cloud backup slot for user
      final currentPlaylists = StorageService.getPlaylists();
      String cloudSlotId = '';
      try {
        final slotResp = await _dio.post(
          _apiBase,
          data: jsonEncode({
            'userId': userId,
            'name': cleanName,
            'email': cleanEmail,
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
            'playlists': currentPlaylists,
          }),
          options: Options(validateStatus: (s) => s != null && s < 500),
        );
        if ((slotResp.statusCode == 200 || slotResp.statusCode == 201) && slotResp.data != null) {
          final data = slotResp.data is Map ? slotResp.data : jsonDecode(slotResp.data.toString());
          cloudSlotId = data['id']?.toString() ?? '';
        }
      } catch (e) {
        debugPrint('[Auth] Could not create personal backup slot: $e');
      }

      final newUser = UserModel(
        id: userId,
        name: cleanName,
        email: cleanEmail,
        passwordHash: passHash,
        cloudSlotId: cloudSlotId,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      // 3. Save to master accounts directory
      accountsMap[cleanEmail] = newUser.toJson();
      await _saveAccountsDirectory(accountsMap);

      // 4. Save locally
      await StorageService.saveCurrentUser(newUser);
      await StorageService.setUserAuthorName(cleanName);
      _currentUser = newUser;
      authState.value = newUser;

      // Claim local playlists for the newly registered user
      await _claimLocalPlaylistsForUser(newUser);

      return AuthResult(
        success: true,
        message: 'Welcome to Aura, $cleanName! 🎉 Account created successfully.',
        user: newUser,
      );
    } catch (e) {
      debugPrint('[Auth] Registration error: $e');
      return AuthResult(success: false, message: 'Registration failed: $e');
    }
  }

  /// Login to existing zero-database account
  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanPassword = password.trim();

    if (!cleanEmail.contains('@') || !cleanEmail.contains('.')) {
      return const AuthResult(success: false, message: 'Please enter a valid email address.');
    }
    if (cleanPassword.isEmpty) {
      return const AuthResult(success: false, message: 'Please enter your password.');
    }

    try {
      final accountsMap = await _fetchAccountsDirectory();
      if (!accountsMap.containsKey(cleanEmail)) {
        return const AuthResult(
          success: false,
          message: 'No account found with this email. Please check spelling or create an account.',
        );
      }

      final accountData = Map<String, dynamic>.from(accountsMap[cleanEmail] as Map);
      final storedHash = accountData['passwordHash']?.toString() ?? '';
      final inputHash = hashPassword(cleanPassword);

      if (storedHash != inputHash) {
        return const AuthResult(
          success: false,
          message: 'Incorrect password. Please try again.',
        );
      }

      final user = UserModel.fromJson(accountData);

      // Save locally
      await StorageService.saveCurrentUser(user);
      await StorageService.setUserAuthorName(user.name);
      _currentUser = user;
      authState.value = user;

      // Claim local playlists created on this device
      await _claimLocalPlaylistsForUser(user);

      // Automatically restore cloud playlists on login
      int restoredCount = 0;
      if (user.cloudSlotId.isNotEmpty) {
        final restoreRes = await restoreUserPlaylists();
        restoredCount = restoreRes;
      }

      final extra = restoredCount > 0 ? ' ($restoredCount playlists synced)' : '';
      return AuthResult(
        success: true,
        message: 'Welcome back, ${user.name}! ☁️$extra',
        user: user,
      );
    } catch (e) {
      debugPrint('[Auth] Login error: $e');
      return AuthResult(success: false, message: 'Login failed: $e');
    }
  }

  /// Log out the user
  Future<void> logout() async {
    await StorageService.saveCurrentUser(null);
    _currentUser = null;
    authState.value = null;
    debugPrint('[Auth] Logged out.');
  }

  /// Check whether the current user is the owner of a playlist
  bool isPlaylistOwner(Map<String, dynamic> playlist) {
    final ownerId = playlist['ownerId']?.toString();
    final ownerEmail = playlist['ownerEmail']?.toString().toLowerCase().trim();
    final currentEmail = currentUserEmail?.toLowerCase().trim();

    // 1. Direct owner ID match (works for logged-in user ID and local device ID)
    if (ownerId != null && ownerId.isNotEmpty && ownerId == currentUserId) {
      return true;
    }

    // 2. Direct owner Email match (works across devices when logged into the same account)
    if (isLoggedIn && ownerEmail != null && ownerEmail.isNotEmpty && currentEmail != null && currentEmail.isNotEmpty) {
      if (ownerEmail == currentEmail) {
        return true;
      }
    }

    // 3. Author Name match (if not assigned to another user ID)
    final authorName = (playlist['ownerName'] ?? playlist['authorName'])?.toString().trim().toLowerCase();
    if (authorName != null && authorName.isNotEmpty && authorName == currentUserName.trim().toLowerCase()) {
      if (ownerId == null || ownerId.isEmpty || ownerId == currentUserId || ownerId == StorageService.getDeviceId()) {
        return true;
      }
    }

    // 4. If explicitly marked imported from someone else and didn't match owner identity above
    if (playlist['isImported'] == true) {
      return false;
    }

    // 5. Default for locally created playlists on this device without isImported
    return true;
  }

  /// Scans local playlists and tags any created on this device or belonging to user with their account credentials
  Future<void> _claimLocalPlaylistsForUser(UserModel user) async {
    try {
      final playlists = StorageService.getPlaylists();
      bool modified = false;

      for (final pl in playlists) {
        final ownerId = pl['ownerId']?.toString();
        final ownerEmail = pl['ownerEmail']?.toString();
        final isImported = pl['isImported'] == true;

        // If it was created on this device while logged out (ownerId is null, empty, or deviceId)
        // and NOT imported from another user:
        final isLocalUnclaimed = !isImported && (ownerId == null || ownerId.isEmpty || ownerId == StorageService.getDeviceId());

        // Or if it matches this user's id, email, or author name
        final matchesThisAccount = (ownerId != null && ownerId == user.id) ||
            (ownerEmail != null && ownerEmail.toLowerCase() == user.email.toLowerCase()) ||
            (!isImported && pl['authorName']?.toString().toLowerCase() == user.name.toLowerCase());

        if (isLocalUnclaimed || matchesThisAccount) {
          pl['ownerId'] = user.id;
          pl['ownerEmail'] = user.email;
          pl['ownerName'] = user.name;
          pl['isImported'] = false;
          modified = true;
        }
      }

      if (modified) {
        await StorageService.savePlaylists(playlists);
      }
    } catch (e) {
      debugPrint('[Auth] Error claiming local playlists: $e');
    }
  }

  /// Backs up all local playlists to the user's dedicated account cloud slot
  Future<String> backupUserPlaylists() async {
    if (!isLoggedIn || _currentUser == null) {
      return 'Please sign in to backup your playlists.';
    }

    try {
      await _claimLocalPlaylistsForUser(_currentUser!);
      final playlists = StorageService.getPlaylists();
      String slotId = _currentUser!.cloudSlotId;

      final payload = {
        'userId': _currentUser!.id,
        'name': _currentUser!.name,
        'email': _currentUser!.email,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'playlists': playlists,
      };

      if (slotId.isNotEmpty) {
        await _dio.put(
          '$_apiBase/$slotId',
          data: jsonEncode(payload),
          options: Options(validateStatus: (s) => s != null && s < 500),
        );
      } else {
        // Create slot if not existing
        final createResp = await _dio.post(
          _apiBase,
          data: jsonEncode(payload),
          options: Options(validateStatus: (s) => s != null && s < 500),
        );
        if ((createResp.statusCode == 200 || createResp.statusCode == 201) && createResp.data != null) {
          final data = createResp.data is Map ? createResp.data : jsonDecode(createResp.data.toString());
          slotId = data['id']?.toString() ?? '';
          if (slotId.isNotEmpty) {
            _currentUser = _currentUser!.copyWith(cloudSlotId: slotId);
            await StorageService.saveCurrentUser(_currentUser);
            // Update directory
            final dir = await _fetchAccountsDirectory();
            if (dir.containsKey(_currentUser!.email)) {
              dir[_currentUser!.email]['cloudSlotId'] = slotId;
              await _saveAccountsDirectory(dir);
            }
          }
        }
      }

      return 'Backed up ${playlists.length} playlists to ${_currentUser!.email}! ☁️';
    } catch (e) {
      debugPrint('[Auth] Backup failed: $e');
      return 'Backup failed: $e';
    }
  }

  /// Restores playlists from the user's dedicated account cloud slot and merges them
  Future<int> restoreUserPlaylists() async {
    if (!isLoggedIn || _currentUser == null || _currentUser!.cloudSlotId.isEmpty) {
      return 0;
    }

    try {
      final resp = await _dio.get(
        '$_apiBase/${_currentUser!.cloudSlotId}?t=${DateTime.now().millisecondsSinceEpoch}',
        options: Options(
          validateStatus: (s) => s != null && s < 500,
          headers: {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
        ),
      );

      if (resp.statusCode == 200 && resp.data != null) {
        final dynamic rawObj = resp.data is Map ? resp.data : jsonDecode(resp.data.toString());
        final Map<String, dynamic> data = rawObj is Map
            ? (rawObj.containsKey('data') && rawObj['data'] is Map
                ? Map<String, dynamic>.from(rawObj['data'] as Map)
                : Map<String, dynamic>.from(rawObj))
            : {};
        final List remotePlaylists = data['playlists'] as List? ?? [];

        if (remotePlaylists.isEmpty) return 0;

        final localPlaylists = StorageService.getPlaylists();
        final Map<String, int> existingIdIndex = {};
        final Map<String, int> existingCodeIndex = {};
        for (int i = 0; i < localPlaylists.length; i++) {
          final id = localPlaylists[i]['id']?.toString() ?? '';
          final code = localPlaylists[i]['shareCode']?.toString().toUpperCase() ?? '';
          if (id.isNotEmpty) existingIdIndex[id] = i;
          if (code.isNotEmpty) existingCodeIndex[code] = i;
        }

        int restored = 0;
        for (final item in remotePlaylists) {
          if (item is Map) {
            final pl = Map<String, dynamic>.from(item);
            final id = pl['id']?.toString() ?? '';
            final code = pl['shareCode']?.toString().toUpperCase() ?? '';

            // User's own backup playlists are unlocked and owned by this account
            pl['isImported'] = false;
            pl['ownerId'] = _currentUser!.id;
            pl['ownerEmail'] = _currentUser!.email;
            pl['ownerName'] = _currentUser!.name;

            final existingIdx = existingIdIndex[id] ?? (code.isNotEmpty ? existingCodeIndex[code] : null);
            if (existingIdx != null) {
              // Unlock and update existing local playlist with account ownership!
              localPlaylists[existingIdx]['isImported'] = false;
              localPlaylists[existingIdx]['ownerId'] = _currentUser!.id;
              localPlaylists[existingIdx]['ownerEmail'] = _currentUser!.email;
              localPlaylists[existingIdx]['ownerName'] = _currentUser!.name;
              restored++;
            } else {
              localPlaylists.add(pl);
              if (id.isNotEmpty) existingIdIndex[id] = localPlaylists.length - 1;
              if (code.isNotEmpty) existingCodeIndex[code] = localPlaylists.length - 1;
              restored++;
            }
          }
        }

        if (restored > 0) {
          await StorageService.savePlaylists(localPlaylists);
        }
        return restored;
      }
    } catch (e) {
      debugPrint('[Auth] Restore failed: $e');
    }
    return 0;
  }

  Future<Map<String, dynamic>> _fetchAccountsDirectory() async {
    try {
      final resp = await _dio.get(
        '$_apiBase/$_masterAccountsId',
        options: Options(validateStatus: (s) => s != null && s < 500),
      );
      if (resp.statusCode == 200 && resp.data != null) {
        final dynamic raw = resp.data is Map ? resp.data : jsonDecode(resp.data.toString());
        final Map<String, dynamic> data = raw is Map
            ? (raw.containsKey('data') && raw['data'] is Map ? Map<String, dynamic>.from(raw['data'] as Map) : Map<String, dynamic>.from(raw))
            : {};
        final users = data['users'] ?? data['accounts'];
        if (users is Map) {
          return Map<String, dynamic>.from(users);
        }
      }
    } catch (e) {
      debugPrint('[Auth] Error fetching accounts directory: $e');
    }
    return {};
  }

  Future<void> _saveAccountsDirectory(Map<String, dynamic> accounts) async {
    try {
      await _dio.put(
        '$_apiBase/$_masterAccountsId',
        data: jsonEncode({
          'service': 'AURA_ACCOUNTS_MASTER',
          'users': accounts,
          'lastUpdated': DateTime.now().millisecondsSinceEpoch,
        }),
        options: Options(validateStatus: (s) => s != null && s < 500),
      );
    } catch (e) {
      debugPrint('[Auth] Error saving accounts directory: $e');
    }
  }

  // --- Pure Dart SHA-256 implementation ---
  static String _sha256Hex(String input) {
    final bytes = utf8.encode(input);
    final hash = _sha256(bytes);
    return hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static List<int> _sha256(List<int> message) {
    final k = <int>[
      0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
      0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
      0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
      0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
      0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
      0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
      0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
      0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ];

    int h0 = 0x6a09e667, h1 = 0xbb67ae85, h2 = 0x3c6ef372, h3 = 0xa54ff53a;
    int h4 = 0x510e527f, h5 = 0x9b05688c, h6 = 0x1f83d9ab, h7 = 0x5be0cd19;

    final bitLen = message.length * 8;
    final padded = List<int>.from(message)..add(0x80);
    while ((padded.length % 64) != 56) {
      padded.add(0);
    }
    for (int i = 7; i >= 0; i--) {
      padded.add((bitLen >> (i * 8)) & 0xff);
    }

    final w = List<int>.filled(64, 0);
    for (int chunk = 0; chunk < padded.length; chunk += 64) {
      for (int i = 0; i < 16; i++) {
        w[i] = (padded[chunk + i * 4] << 24) |
            (padded[chunk + i * 4 + 1] << 16) |
            (padded[chunk + i * 4 + 2] << 8) |
            padded[chunk + i * 4 + 3];
      }
      for (int i = 16; i < 64; i++) {
        final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
        final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
      }

      int a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;
      for (int i = 0; i < 64; i++) {
        final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
        final ch = (e & f) ^ ((~e) & g);
        final temp1 = (h + s1 + ch + k[i] + w[i]) & 0xffffffff;
        final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = (s0 + maj) & 0xffffffff;

        h = g;
        g = f;
        f = e;
        e = (d + temp1) & 0xffffffff;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & 0xffffffff;
      }

      h0 = (h0 + a) & 0xffffffff;
      h1 = (h1 + b) & 0xffffffff;
      h2 = (h2 + c) & 0xffffffff;
      h3 = (h3 + d) & 0xffffffff;
      h4 = (h4 + e) & 0xffffffff;
      h5 = (h5 + f) & 0xffffffff;
      h6 = (h6 + g) & 0xffffffff;
      h7 = (h7 + h) & 0xffffffff;
    }

    final out = <int>[];
    for (final val in [h0, h1, h2, h3, h4, h5, h6, h7]) {
      out.add((val >> 24) & 0xff);
      out.add((val >> 16) & 0xff);
      out.add((val >> 8) & 0xff);
      out.add(val & 0xff);
    }
    return out;
  }

  static int _rotr(int x, int n) => ((x >>> n) | (x << (32 - n))) & 0xffffffff;
}

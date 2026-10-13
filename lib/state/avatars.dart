import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../api/bb_api.dart';
import '../api/models.dart';
import 'settings.dart';

/// Profile pictures: contact photos and group photos from the Mac, plus photos
/// you pick yourself. Everything is cached as small files on the phone, so
/// pictures show instantly and work offline.
class Avatars extends ChangeNotifier {
  final Settings settings;
  Avatars(this.settings);

  Directory? _dir;
  final Set<String> _have = {}; // file names that exist
  Map<String, String> _custom = {}; // chat guid -> file name
  final Set<String> _iconTried = {};
  bool _syncing = false;
  bool _syncingIcons = false;

  /// Call once at startup, before the first frame.
  Future<void> init() async {
    try {
      final base = await getApplicationSupportDirectory();
      final d = Directory('${base.path}/avatars');
      await d.create(recursive: true);
      _dir = d;
      for (final e in d.listSync()) {
        if (e is File) _have.add(e.uri.pathSegments.last);
      }
      _custom = Map<String, String>.from(jsonDecode(settings.prefs.getString('custom_avatars') ?? '{}'));
      _custom.removeWhere((_, f) => !_have.contains(f));
    } catch (_) {}
  }

  static String _safe(String s) => base64Url.encode(utf8.encode(s)).replaceAll('=', '');

  ImageProvider? _provider(String name) {
    final d = _dir;
    if (d == null || !_have.contains(name)) return null;
    return ResizeImage(FileImage(File('${d.path}/$name')), width: 200);
  }

  Future<void> _write(String name, List<int> bytes) async {
    final d = _dir;
    if (d == null) return;
    final f = File('${d.path}/$name');
    final existed = _have.contains(name);
    if (existed) await _provider(name)?.evict();
    await f.writeAsBytes(bytes, flush: true);
    _have.add(name);
  }

  Future<void> _delete(String name) async {
    final d = _dir;
    if (d == null) return;
    await _provider(name)?.evict();
    _have.remove(name);
    try {
      await File('${d.path}/$name').delete();
    } catch (_) {}
  }

  // ------------------------------------------------------------ lookups

  ImageProvider? forAddress(String address) => _provider('c_${_safe(normalizeAddress(address))}');

  /// Your own photo for the chat, else the group's photo, else (for 1:1 chats)
  /// the contact's photo. Null means "show initials".
  ImageProvider? forChat(Chat c) {
    final custom = _custom[c.guid];
    if (custom != null) {
      final p = _provider(custom);
      if (p != null) return p;
    }
    final icon = _provider('g_${_safe(c.guid)}');
    if (icon != null) return icon;
    if (c.isGroup) return null;
    for (final h in c.participants) {
      final p = forAddress(h.address);
      if (p != null) return p;
    }
    return null;
  }

  bool hasCustom(String chatGuid) => _custom.containsKey(chatGuid);

  // ------------------------------------------------------------ your own photo

  /// Lets you pick a photo from the gallery for this chat. Returns true if one was set.
  Future<bool> pickFor(Chat c) async {
    final d = _dir;
    if (d == null) return false;
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 720, maxHeight: 720, imageQuality: 88);
    if (x == null) return false;
    final name = 'u_${_safe(c.guid)}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(x.path).copy('${d.path}/$name');
    _have.add(name);
    final old = _custom[c.guid];
    _custom[c.guid] = name;
    if (old != null) await _delete(old);
    await settings.prefs.setString('custom_avatars', jsonEncode(_custom));
    notifyListeners();
    return true;
  }

  Future<void> clearFor(Chat c) async {
    final old = _custom.remove(c.guid);
    if (old != null) await _delete(old);
    await settings.prefs.setString('custom_avatars', jsonEncode(_custom));
    notifyListeners();
  }

  // ------------------------------------------------------------ from the Mac

  /// Downloads contact photos (at most every 6 hours). Photos are saved per
  /// phone number / email so any chat with that person can find them.
  Future<void> syncContacts(BBApi api, {bool force = false}) async {
    if (_syncing || _dir == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = settings.prefs.getInt('avatar_sync') ?? 0;
    if (!force && now - last < 6 * 3600 * 1000 && _have.any((n) => n.startsWith('c_'))) return;
    _syncing = true;
    try {
      final list = await api.contactsWithPhotos();
      var n = 0;
      for (final m in list) {
        var b64 = (m['avatar'] ?? '').toString();
        if (b64.isEmpty) continue;
        if (b64.contains(',')) b64 = b64.split(',').last;
        List<int> bytes;
        try {
          bytes = base64Decode(b64);
        } catch (_) {
          continue;
        }
        if (bytes.isEmpty) continue;
        final addrs = <String>[];
        for (final k in ['phoneNumbers', 'emails']) {
          for (final e in (m[k] as List?) ?? const []) {
            if (e is Map && e['address'] != null) addrs.add(e['address'].toString());
          }
        }
        for (final a in addrs.take(4)) {
          await _write('c_${_safe(normalizeAddress(a))}', bytes);
        }
        if (++n % 25 == 0) notifyListeners();
      }
      await settings.prefs.setInt('avatar_sync', now);
    } catch (_) {
      // Photos are a nicety; initials still work.
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// Fetches the photo of each group chat (once per app launch).
  Future<void> syncGroupIcons(BBApi? api, List<Chat> chats) async {
    if (api == null || _dir == null || _syncingIcons) return;
    _syncingIcons = true;
    try {
      final groups = chats.where((c) => c.isGroup).take(40).toList();
      var fetched = 0;
      for (final c in groups) {
        if (!_iconTried.add(c.guid)) continue;
        final bytes = await api.chatIcon(c.guid);
        if (bytes != null) {
          await _write('g_${_safe(c.guid)}', bytes);
          if (++fetched % 3 == 0) notifyListeners();
        }
      }
      if (fetched > 0) notifyListeners();
    } finally {
      _syncingIcons = false;
    }
  }
}

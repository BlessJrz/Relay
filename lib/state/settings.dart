import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/bb_api.dart';

enum DesignId { pinned, material, folders, minimal }

enum ThemeModeChoice { light, dark, system }

extension DesignNames on DesignId {
  String get label => switch (this) {
        DesignId.pinned => 'Pinned',
        DesignId.material => 'Material',
        DesignId.folders => 'Folders',
        DesignId.minimal => 'Modern Minimal',
      };
}

/// Everything the user can change, persisted on the phone.
/// The server password lives in the Android Keystore via flutter_secure_storage.
class Settings extends ChangeNotifier {
  final SharedPreferences prefs;
  static const _secure = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  Settings._(this.prefs);

  static Future<Settings> load() async {
    final p = await SharedPreferences.getInstance();
    final s = Settings._(p);
    s._password = await _secure.read(key: 'server_password') ?? '';
    return s;
  }

  String _password = '';

  // ---------- appearance ----------
  DesignId get design => DesignId.values.firstWhere(
        (d) => d.name == prefs.getString('design'),
        orElse: () => DesignId.pinned,
      );
  set design(DesignId d) {
    prefs.setString('design', d.name);
    notifyListeners();
  }

  ThemeModeChoice get mode => ThemeModeChoice.values.firstWhere(
        (m) => m.name == prefs.getString('mode'),
        orElse: () => ThemeModeChoice.system,
      );
  set mode(ThemeModeChoice m) {
    prefs.setString('mode', m.name);
    notifyListeners();
  }

  int accentFor(DesignId d) => prefs.getInt('accent_${d.name}') ?? 0;
  void setAccent(DesignId d, int i) {
    prefs.setInt('accent_${d.name}', i);
    notifyListeners();
  }

  /// Your colour for "Messages", unread badges and times. Null = the design's own.
  Color? get highlight {
    final v = prefs.getInt('highlight_color');
    return v == null ? null : Color(v);
  }

  set highlight(Color? c) {
    if (c == null) {
      prefs.remove('highlight_color');
    } else {
      prefs.setInt('highlight_color', c.toARGB32());
    }
    notifyListeners();
  }

  bool get animations => prefs.getBool('animations') ?? true;
  set animations(bool v) {
    prefs.setBool('animations', v);
    notifyListeners();
  }

  /// Fewer effects and shorter transitions.
  bool get reduceMotion => prefs.getBool('reduce_motion') ?? false;
  set reduceMotion(bool v) {
    prefs.setBool('reduce_motion', v);
    notifyListeners();
  }

  /// Chats pinned to the top (the Pinned design shows them as big circles).
  List<String> get pinnedChats => prefs.getStringList('pinned_chats') ?? const [];
  set pinnedChats(List<String> v) {
    prefs.setStringList('pinned_chats', v);
    prefs.setBool('pins_seeded', true);
    notifyListeners();
  }

  /// Chats that don't make a sound or show a notification.
  List<String> get mutedChats => prefs.getStringList('muted_chats') ?? const [];
  bool isMuted(String guid) => mutedChats.contains(guid);
  void toggleMute(String guid) {
    final l = [...mutedChats];
    l.contains(guid) ? l.remove(guid) : l.add(guid);
    prefs.setStringList('muted_chats', l);
    notifyListeners();
  }

  /// Half-written messages, per chat. Changes bump [drafts] (just the chat
  /// list listens) rather than rebuilding the whole app, which would also
  /// disturb the keyboard while you type.
  final drafts = ValueNotifier<int>(0);
  Map<String, String> get _drafts => Map<String, String>.from(jsonDecode(prefs.getString('drafts') ?? '{}'));
  String draftFor(String guid) => _drafts[guid] ?? '';
  void setDraft(String guid, String text, {bool notify = true}) {
    final d = _drafts;
    final had = (d[guid] ?? '').trim().isNotEmpty;
    final has = text.trim().isNotEmpty;
    if ((d[guid] ?? '') == (has ? text : '')) return;
    has ? d[guid] = text : d.remove(guid);
    prefs.setString('drafts', jsonEncode(d));
    if (had != has) {
      // The chat list shows "Draft: …". Callers in the middle of a build pass
      // notify: false, so the bump waits for the frame.
      notify ? drafts.value++ : WidgetsBinding.instance.addPostFrameCallback((_) => drafts.value++);
    }
  }

  /// Ask for a fingerprint (or the phone's PIN) to open Relay.
  bool get appLock => prefs.getBool('app_lock') ?? false;
  set appLock(bool v) {
    prefs.setBool('app_lock', v);
    notifyListeners();
  }

  /// Warn me when the Mac can't be reached for a while.
  bool get macOfflineAlert => prefs.getBool('mac_offline_alert') ?? true;
  set macOfflineAlert(bool v) {
    prefs.setBool('mac_offline_alert', v);
    notifyListeners();
  }

  bool get pinsSeeded => prefs.getBool('pins_seeded') ?? false;
  bool isPinned(String guid) => pinnedChats.contains(guid);
  void togglePin(String guid) {
    final l = [...pinnedChats];
    l.contains(guid) ? l.remove(guid) : l.add(guid);
    pinnedChats = l;
  }

  double get textScale => prefs.getDouble('text_scale') ?? 1.0;
  set textScale(double v) {
    prefs.setDouble('text_scale', v);
    notifyListeners();
  }

  // ---------- onboarding ----------
  bool get setupDone => prefs.getBool('setup_done') ?? false;
  set setupDone(bool v) {
    prefs.setBool('setup_done', v);
    notifyListeners();
  }

  bool get tipsDone => prefs.getBool('tips_done') ?? false;
  set tipsDone(bool v) {
    prefs.setBool('tips_done', v);
    notifyListeners();
  }

  Set<String> get macStepsDone => (prefs.getStringList('mac_steps') ?? const []).toSet();
  void toggleMacStep(String id) {
    final s = macStepsDone;
    s.contains(id) ? s.remove(id) : s.add(id);
    prefs.setStringList('mac_steps', s.toList());
    notifyListeners();
  }

  // ---------- connection ----------
  String get serverUrl => prefs.getString('server_url') ?? '';
  String get password => _password;

  Future<void> saveServer(String url, String password) async {
    await prefs.setString('server_url', BBApi.sanitizeUrl(url));
    _password = password;
    await _secure.write(key: 'server_password', value: password);
    // The background push handler runs in its own isolate and can't read the
    // secure store synchronously, so it only gets what it needs: nothing secret.
    notifyListeners();
  }

  Future<void> updateServerUrl(String url) async {
    await prefs.setString('server_url', BBApi.sanitizeUrl(url));
    notifyListeners();
  }

  bool get pushEnabled => prefs.getBool('push_enabled') ?? true;
  set pushEnabled(bool v) {
    prefs.setBool('push_enabled', v);
    notifyListeners();
  }

  bool get notificationPreviews => prefs.getBool('notif_previews') ?? true;
  set notificationPreviews(bool v) {
    prefs.setBool('notif_previews', v);
    notifyListeners();
  }

  Future<void> resetAll() async {
    await prefs.clear();
    await _secure.deleteAll();
    _password = '';
    notifyListeners();
  }
}

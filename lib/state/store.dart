import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../api/bb_api.dart';
import '../api/models.dart';
import '../api/socket.dart';
import '../push/push.dart';
import 'avatars.dart';
import 'settings.dart';

enum Conn { notConfigured, connecting, online, offline, badPassword }

class MsgBanner {
  final Chat chat;
  final Message message;
  MsgBanner(this.chat, this.message);
}

/// App data: connection, chats, messages, contacts. One instance for the app.
class Store extends ChangeNotifier {
  final Settings settings;
  Store(this.settings) {
    avatars = Avatars(settings);
    avatars.addListener(notifyListeners);
  }

  late final Avatars avatars;

  /// Set from the app lifecycle: polling pauses while Relay is in the background.
  bool appActive = true;

  /// True while the real-time link to the Mac is up.
  bool get live => socket.state == SocketState.connected;
  bool get liveLinkDown => conn == Conn.online && socket.state == SocketState.disconnected;

  BBApi? api;
  final socket = SocketService();
  StreamSubscription? _evSub, _stSub;
  Timer? _pingTimer;

  Conn conn = Conn.notConfigured;
  String? lastError;
  ServerInfo? info;
  Duration? latency;
  final List<int> latencyHistory = [];

  List<Chat> chats = [];
  bool chatsLoading = false;
  final Map<String, List<Message>> _messages = {}; // newest first
  final Map<String, bool> _hasMore = {};
  final Map<String, String> _names = {}; // normalised address -> name
  final Set<String> typing = {};
  final Set<String> _fetchingChats = {};
  String? openChat;

  final _banners = StreamController<MsgBanner>.broadcast();
  Stream<MsgBanner> get banners => _banners.stream;

  bool get privateApi => info?.canUsePrivateApi ?? false;

  // ------------------------------------------------------------ connection

  Future<void> start() async {
    if (settings.serverUrl.isEmpty || settings.password.isEmpty) {
      conn = Conn.notConfigured;
      notifyListeners();
      return;
    }
    _loadLocalCaches();
    _restoreQueue();
    _watchNetwork();
    await connect();
  }

  // ------------------------------------------------------------ connection watching

  Conn _lastConn = Conn.notConfigured;
  Timer? _offlineTimer;
  bool _offlineAlerted = false;

  @override
  void notifyListeners() {
    if (conn != _lastConn) {
      final was = _lastConn;
      _lastConn = conn;
      _connChanged(was, conn);
    }
    super.notifyListeners();
  }

  void _connChanged(Conn was, Conn now) {
    if (now == Conn.online) {
      _offlineTimer?.cancel();
      _offlineTimer = null;
      if (_offlineAlerted) {
        _offlineAlerted = false;
        Push.instance.clearMacOffline();
      }
      if (_queue.isNotEmpty) unawaited(_flushQueue());
    } else if (now == Conn.offline && settings.setupDone) {
      // Only warn if it stays unreachable for a while (Macs blip on network changes).
      _offlineTimer ??= Timer(const Duration(minutes: 3), () {
        _offlineTimer = null;
        if (conn != Conn.online && settings.macOfflineAlert) {
          _offlineAlerted = true;
          Push.instance.showMacOffline();
        }
      });
    }
  }

  // ------------------------------------------------------------ send queue (Mac unreachable)

  /// Messages typed while the Mac couldn't be reached; sent when it's back.
  final List<Map<String, dynamic>> _queue = [];
  bool _flushing = false;

  int get queuedCount => _queue.length;

  void _saveQueue() => settings.prefs.setString('send_queue', jsonEncode(_queue));

  void _restoreQueue() {
    try {
      _queue
        ..clear()
        ..addAll((jsonDecode(settings.prefs.getString('send_queue') ?? '[]') as List).map((e) => Map<String, dynamic>.from(e)));
      for (final q in _queue) {
        _upsert(q['chat'], Message(guid: q['temp'], tempGuid: q['temp'], text: q['text'], isFromMe: true, dateCreated: q['at'], queued: true, threadOriginatorGuid: q['reply']));
      }
    } catch (_) {}
  }

  static bool _unreachable(ApiException e) => e.status == 0 || e.status == 408 || e.status == 502 || e.status == 503 || e.status == 504 || e.status == 530;

  Future<void> _flushQueue() async {
    final a = api;
    if (a == null || _flushing) return;
    _flushing = true;
    try {
      while (_queue.isNotEmpty) {
        final q = _queue.first;
        final g = q['chat'] as String, temp = q['temp'] as String;
        final i = (_messages[g] ?? []).indexWhere((m) => m.guid == temp);
        if (i >= 0) _messages[g]![i] = _messages[g]![i].copyWith(queued: false, sending: true);
        notifyListeners();
        try {
          final sent = await a.sendText(g, q['text'], tempGuid: temp, privateApi: privateApi, replyToGuid: q['reply']);
          _replaceTemp(g, temp, sent);
        } on ApiException catch (e) {
          if (_unreachable(e)) {
            final j = (_messages[g] ?? []).indexWhere((m) => m.guid == temp);
            if (j >= 0) _messages[g]![j] = _messages[g]![j].copyWith(queued: true, sending: false);
            break;
          }
          _markFailed(g, temp);
          lastError = e.message;
        }
        _queue.removeAt(0);
        _saveQueue();
      }
    } finally {
      _flushing = false;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------ edit, unsend, send later

  Future<String?> editMessage(Message m, String text) async {
    if (!privateApi) return 'Editing needs the Private API on your Mac.';
    try {
      await api!.editMessage(m.guid, text.trim());
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<String?> unsendMessage(Message m) async {
    if (!privateApi) return 'Unsending needs the Private API on your Mac.';
    try {
      await api!.unsendMessage(m.guid);
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<String?> scheduleMessage(Chat chat, String text, DateTime at) async {
    final a = api;
    if (a == null) return 'Not connected to your Mac.';
    try {
      await a.scheduleMessage(chat.guid, text.trim(), at, privateApi: privateApi);
      return null;
    } on ApiException catch (e) {
      return e.status == 404 ? 'Your BlueBubbles Server is too old for scheduled messages. Update it on the Mac.' : e.message;
    }
  }

  Future<List<ScheduledMessage>> scheduledFor(Chat chat) async {
    try {
      final all = await api?.scheduledMessages() ?? const <ScheduledMessage>[];
      return all.where((s) => s.chatGuid == chat.guid && s.pending).toList()..sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));
    } catch (_) {
      return const [];
    }
  }

  Future<bool> cancelScheduled(ScheduledMessage s) async {
    try {
      await api?.cancelScheduled(s.id);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// When you last read this chat (ms), for the "New messages" line.
  int lastReadFor(String guid) => _lastRead[guid] ?? 0;

  /// Mark a read chat as unread again (only on this phone).
  void markUnread(Chat c) {
    final m = c.lastMessage;
    if (m == null || m.isFromMe) return;
    _lastRead[c.guid] = m.dateCreated - 1;
    settings.prefs.setString('last_read', jsonEncode(_lastRead));
    notifyListeners();
  }

  // ------------------------------------------------------------ network changes (wifi <-> 5G)

  StreamSubscription? _netSub;
  Timer? _netDebounce;

  void _watchNetwork() {
    if (_netSub != null) return;
    try {
      _netSub = Connectivity().onConnectivityChanged.listen((_) => _networkChanged());
    } catch (_) {}
  }

  /// Switching between wifi and mobile data kills the old socket silently, so
  /// rebuild the connection a moment after the network settles.
  void _networkChanged() {
    _netDebounce?.cancel();
    _netDebounce = Timer(const Duration(milliseconds: 1500), () async {
      if (settings.serverUrl.isEmpty || settings.password.isEmpty) return;
      if (conn == Conn.online) {
        socket.reconnect();
        unawaited(_pollNow());
      } else {
        await connect();
      }
    });
  }

  // ------------------------------------------------------------ polling safety net

  Timer? _pollTimer;
  int _tick = 0;
  bool _polling = false;

  void _startPolling() {
    _pollTimer?.cancel();
    _tick = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pollTick());
  }

  /// If the live link is down (or just as an occasional double-check), ask the
  /// Mac directly for anything new, so messages still show up.
  Future<void> _pollTick() async {
    if (api == null || _polling || !appActive) return;
    _tick++;
    if (live && _tick % 6 != 0) return;
    await _pollNow();
  }

  Future<void> _pollNow() async {
    if (api == null || _polling) return;
    _polling = true;
    try {
      final open = openChat;
      if (open != null) await syncMessages(open);
      await _syncChats();
    } finally {
      _polling = false;
    }
  }

  /// Called when the app comes back to the front.
  Future<void> onResumed() async {
    appActive = true;
    // Coming back to a chat that was left open means you've seen it.
    final open = openChat == null ? null : chatByGuid(openChat!);
    if (open != null) markRead(open);
    if (settings.serverUrl.isEmpty || settings.password.isEmpty) return;
    if (conn != Conn.online) {
      await connect();
    } else {
      if (!live) socket.reconnect();
      await _pollNow();
    }
  }

  /// Connects using saved settings. Returns null on success or an error message.
  Future<String?> connect() async {
    api?.close();
    api = BBApi(serverUrl: settings.serverUrl, password: settings.password);
    conn = Conn.connecting;
    lastError = null;
    notifyListeners();
    try {
      latency = await api!.ping();
      _recordLatency();
      info = await api!.serverInfo();
      // Remembered for replies sent straight from a notification.
      unawaited(settings.prefs.setBool('private_api', privateApi));
    } on ApiException catch (e) {
      if (e.isAuth) {
        conn = Conn.badPassword;
      } else {
        conn = Conn.offline;
        // A trycloudflare URL changes whenever the Mac restarts. Ask Firebase for the new one.
        if (await recoverServerUrl()) return connect();
      }
      lastError = e.message;
      notifyListeners();
      return e.message;
    }
    conn = Conn.online;
    _listenSocket();
    socket.connect(api!.origin, settings.password, api!.headers);
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 45), (_) => _measure());
    _startPolling();
    notifyListeners();
    unawaited(refreshChats().then((_) => avatars.syncGroupIcons(api, chats)));
    unawaited(loadContacts());
    unawaited(avatars.syncContacts(api!));
    if (settings.pushEnabled) unawaited(Push.instance.register(this));
    return null;
  }

  void _listenSocket() {
    _evSub?.cancel();
    _stSub?.cancel();
    _evSub = socket.events.listen(_onEvent);
    _stSub = socket.states.listen((s) {
      if (s == SocketState.badPassword) {
        conn = Conn.badPassword;
      } else if (s == SocketState.connected) {
        conn = Conn.online;
        refreshChats(); // catch up on anything missed while disconnected
        final open = openChat;
        if (open != null) syncMessages(open);
      } else if (s == SocketState.disconnected && conn == Conn.online) {
        conn = Conn.offline;
      }
      notifyListeners();
    });
  }

  Future<void> _measure() async {
    final a = api;
    if (a == null) return;
    try {
      latency = await a.ping();
      _recordLatency();
      if (conn != Conn.online) {
        conn = Conn.online;
        socket.reconnect();
      }
    } on ApiException catch (e) {
      conn = e.isAuth ? Conn.badPassword : Conn.offline;
      lastError = e.message;
      if (!e.isAuth && await recoverServerUrl()) {
        await connect();
        return;
      }
    }
    notifyListeners();
  }

  void _recordLatency() {
    latencyHistory.add(latency!.inMilliseconds);
    if (latencyHistory.length > 30) latencyHistory.removeAt(0);
  }

  /// Uses the Firebase project the Mac was set up with to look up the current
  /// server URL (the Mac publishes it there whenever it changes).
  Future<bool> recoverServerUrl() async {
    final cfgRaw = settings.prefs.getString('fcm_config');
    if (cfgRaw == null) return false;
    try {
      final cfg = jsonDecode(cfgRaw) as Map<String, dynamic>;
      final project = cfg['project_info'] as Map<String, dynamic>;
      final client = (cfg['client'] as List).first as Map<String, dynamic>;
      final apiKey = (client['api_key'] as List).first['current_key'];
      String? url;
      final rtdb = project['firebase_url']?.toString();
      if (rtdb != null && rtdb.isNotEmpty) {
        final r = await http.get(Uri.parse('$rtdb/config.json')).timeout(const Duration(seconds: 10));
        if (r.statusCode == 200 && r.body != 'null') {
          url = (jsonDecode(r.body) as Map?)?['serverUrl']?.toString();
        }
      }
      if (url == null) {
        final pid = project['project_id'];
        final r = await http
            .get(Uri.parse(
                'https://firestore.googleapis.com/v1/projects/$pid/databases/(default)/documents/server/config?key=$apiKey'))
            .timeout(const Duration(seconds: 10));
        if (r.statusCode == 200) {
          url = (jsonDecode(r.body)['fields']?['serverUrl']?['stringValue'])?.toString();
        }
      }
      if (url != null && url.isNotEmpty && BBApi.sanitizeUrl(url) != BBApi.sanitizeUrl(settings.serverUrl)) {
        await settings.updateServerUrl(BBApi.sanitizeUrl(url));
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Used by the setup guide and Settings to try a URL + password before saving.
  static Future<(ServerInfo?, Duration?, String?)> test(String url, String password) async {
    final a = BBApi(serverUrl: url, password: password);
    try {
      final d = await a.ping();
      final i = await a.serverInfo();
      return (i, d, null);
    } on ApiException catch (e) {
      return (null, null, e.message);
    } finally {
      a.close();
    }
  }

  void disconnect() {
    _pingTimer?.cancel();
    _pollTimer?.cancel();
    socket.disconnect();
    conn = Conn.notConfigured;
    notifyListeners();
  }

  // ------------------------------------------------------------ chats

  static const _pageSize = 120;
  bool _chatsHasMore = true;
  bool chatsLoadingMore = false;
  int _chatOffset = 0; // how many chats the Mac has handed us so far
  bool _refreshing = false;
  bool get chatsHasMore => _chatsHasMore;

  /// Newest first. A chat whose last message the Mac didn't include keeps the
  /// place the Mac gave it, instead of sinking to the bottom of the list.
  List<Chat> _ordered(List<Chat> list) {
    var prev = 1 << 62;
    final keyed = <(int, int, Chat)>[];
    for (var i = 0; i < list.length; i++) {
      final d = list[i].lastDate;
      final eff = d > 0 ? d : prev;
      if (d > 0) prev = d;
      keyed.add((eff, i, list[i]));
    }
    keyed.sort((a, b) => b.$1 != a.$1 ? b.$1.compareTo(a.$1) : a.$2.compareTo(b.$2));
    return [for (final k in keyed) k.$3];
  }

  @visibleForTesting
  List<Chat> orderChatsForTest(List<Chat> list) => _ordered(list);

  /// Folds a fresh page of chats into what we already have without ever
  /// dropping a chat or going back to an older last message.
  void _mergeChats(List<Chat> fresh, {bool announce = false}) {
    final byGuid = {for (final c in chats) c.guid: c};
    final seen = <String>{};
    final merged = <Chat>[];
    for (final c in fresh) {
      if (!seen.add(c.guid)) continue;
      final old = byGuid[c.guid];
      var next = c;
      if (old != null) {
        if (old.lastMessage != null && c.lastDate < old.lastDate) next = next.copyWith(lastMessage: old.lastMessage);
        if (next.participants.isEmpty && old.participants.isNotEmpty) next = next.copyWith(participants: old.participants);
        final m = c.lastMessage;
        if (announce && m != null && m.guid != old.lastMessage?.guid && c.lastDate > old.lastDate && !m.isFromMe && !m.isReaction && openChat != c.guid) {
          if (!settings.isMuted(c.guid)) _banners.add(MsgBanner(next, m));
        }
      }
      merged.add(next);
    }
    for (final c in chats) {
      if (!seen.contains(c.guid)) merged.add(c);
    }
    chats = _ordered(merged);
  }

  Future<void> refreshChats() async {
    final a = api;
    if (a == null || _refreshing) return;
    _refreshing = true;
    chatsLoading = true;
    notifyListeners();
    try {
      final list = await a.chats(limit: _pageSize);
      _mergeChats(list);
      if (_chatOffset <= _pageSize) {
        _chatOffset = list.length;
        _chatsHasMore = list.length >= _pageSize;
      }
      _saveChatCache();
    } on ApiException catch (e) {
      lastError = e.message;
    }
    _refreshing = false;
    chatsLoading = false;
    notifyListeners();
  }

  /// Older chats, when the list is scrolled to the bottom.
  Future<void> loadMoreChats() async {
    final a = api;
    if (a == null || !_chatsHasMore || chatsLoadingMore || _refreshing) return;
    chatsLoadingMore = true;
    notifyListeners();
    try {
      final list = await a.chats(limit: _pageSize, offset: _chatOffset);
      _chatOffset += list.length;
      _chatsHasMore = list.length >= _pageSize;
      _mergeChats(list);
    } on ApiException catch (e) {
      lastError = e.message;
    }
    chatsLoadingMore = false;
    notifyListeners();
  }

  /// Quiet background check for new activity (no spinner).
  Future<void> _syncChats() async {
    final a = api;
    if (a == null || _refreshing) return;
    try {
      final list = await a.chats(limit: 40);
      _mergeChats(list, announce: true);
      notifyListeners();
    } on ApiException catch (e) {
      if (e.isAuth) {
        conn = Conn.badPassword;
        notifyListeners();
      }
    }
  }

  Chat? chatByGuid(String guid) {
    for (final c in chats) {
      if (c.guid == guid) return c;
    }
    return null;
  }

  Future<void> loadContacts() async {
    final a = api;
    if (a == null) return;
    try {
      final list = await a.contacts();
      _names.clear();
      for (final c in list) {
        for (final ad in c.addresses) {
          _names[normalizeAddress(ad)] = c.name;
        }
      }
      settings.prefs.setString('contact_names', jsonEncode(_names));
      notifyListeners();
    } catch (_) {}
  }

  String nameFor(String address) => _names[normalizeAddress(address)] ?? _pretty(address);

  static String _pretty(String a) {
    final d = a.replaceAll(RegExp(r'[^0-9+]'), '');
    if (d.length == 12 && d.startsWith('+1')) {
      return '(${d.substring(2, 5)}) ${d.substring(5, 8)}-${d.substring(8)}';
    }
    return a;
  }

  String titleFor(Chat c) {
    if (c.displayName.isNotEmpty) return c.displayName;
    if (c.participants.isEmpty) return c.chatIdentifier;
    final names = c.participants.map((p) => nameFor(p.address)).toList();
    if (!c.isGroup) return names.first;
    final firsts = names.map((n) => n.split(' ').first).toList();
    if (firsts.length <= 3) return firsts.join(', ');
    return '${firsts.take(3).join(', ')} +${firsts.length - 3}';
  }

  String initialsFor(Chat c) {
    final t = titleFor(c);
    final parts = t.split(RegExp(r'[\s,&]+')).where((p) => p.isNotEmpty && RegExp(r'[A-Za-z]').hasMatch(p[0])).toList();
    if (parts.isEmpty) return '#';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  String previewFor(Chat c) {
    final m = c.lastMessage;
    if (m == null) return '';
    if (typing.contains(c.guid)) return 'typing…';
    if (m.isReaction) {
      final who = m.isFromMe ? 'You' : (m.handle != null ? nameFor(m.handle!.address).split(' ').first : 'Someone');
      return '$who reacted ${reactionEmoji[m.reactionKind] ?? ''}';
    }
    String body = m.text;
    if (body.isEmpty && m.attachments.isNotEmpty) {
      final a = m.attachments.first;
      body = a.isImage ? '📷 Photo' : a.isVideo ? '🎬 Video' : a.isAudio ? '🎤 Audio' : '📎 ${a.transferName}';
    }
    if (body.isEmpty && m.isGroupEvent) body = m.groupTitle != null ? 'Named the group “${m.groupTitle}”' : 'Group updated';
    if (c.isGroup && !m.isFromMe && m.handle != null) {
      return '${nameFor(m.handle!.address).split(' ').first}: $body';
    }
    return m.isFromMe ? 'You: $body' : body;
  }

  // ------------------------------------------------------------ unread (kept on the phone)

  Map<String, int> _lastRead = {};

  bool isUnread(Chat c) {
    final m = c.lastMessage;
    if (m == null || m.isFromMe) return false;
    return m.dateCreated > (_lastRead[c.guid] ?? 0);
  }

  int unreadCount(Chat c) {
    if (!isUnread(c)) return 0;
    final list = _messages[c.guid];
    if (list == null) return 1;
    final since = _lastRead[c.guid] ?? 0;
    return list.where((m) => !m.isFromMe && !m.isReaction && m.dateCreated > since).length.clamp(1, 99);
  }

  int get totalUnread => chats.where(isUnread).length;

  void markRead(Chat c) {
    final last = c.lastMessage?.dateCreated ?? DateTime.now().millisecondsSinceEpoch;
    _lastRead[c.guid] = last;
    settings.prefs.setString('last_read', jsonEncode(_lastRead));
    if (privateApi) api?.markRead(c.guid).catchError((_) {});
    Push.instance.clearChat(c.guid);
    notifyListeners();
  }

  // ------------------------------------------------------------ messages

  List<Message> messagesFor(String chatGuid) => _messages[chatGuid] ?? const [];
  bool hasMore(String chatGuid) => _hasMore[chatGuid] ?? true;

  final Set<String> _msgLoading = {};
  final Map<String, String> _msgError = {};
  bool isLoadingMessages(String chatGuid) => _msgLoading.contains(chatGuid);
  String? messageError(String chatGuid) => _msgError[chatGuid];

  Future<void> loadMessages(String chatGuid, {bool older = false}) async {
    final a = api;
    if (a == null) return;
    final current = _messages[chatGuid] ?? [];
    final before = older && current.isNotEmpty ? current.last.dateCreated : null;
    if (!older) {
      _msgLoading.add(chatGuid);
      _msgError.remove(chatGuid);
      notifyListeners();
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final list = await a.messages(chatGuid, limit: 60, before: before);
        if (older) {
          final seen = {for (final m in current) m.guid};
          _messages[chatGuid] = [...current, ...list.where((m) => !seen.contains(m.guid))];
        } else {
          // Keep local in-flight messages that the server doesn't know yet.
          final pending = (_messages[chatGuid] ?? []).where((m) => m.sending || m.failed || m.queued).toList();
          _messages[chatGuid] = [...pending, ...list];
        }
        _hasMore[chatGuid] = list.length >= 60;
        _msgError.remove(chatGuid);
        break;
      } on ApiException catch (e) {
        if (attempt == 1 || e.isAuth) {
          if (!older) _msgError[chatGuid] = e.message;
          lastError = e.message;
        } else {
          await Future.delayed(const Duration(milliseconds: 1200));
        }
      }
    }
    _msgLoading.remove(chatGuid);
    notifyListeners();
  }

  /// Pulls the newest messages and merges them in (used when the live link
  /// missed something). Doesn't touch what's already on screen otherwise.
  Future<void> syncMessages(String chatGuid) async {
    final a = api;
    if (a == null) return;
    try {
      final list = await a.messages(chatGuid, limit: 30);
      var changed = false;
      for (final m in list.reversed) {
        final cur = _messages[chatGuid];
        final i = cur?.indexWhere((x) => x.guid == m.guid) ?? -1;
        if (i < 0) {
          // A message we sent that is still showing as "sending" is this one.
          if (m.isFromMe && cur != null) {
            cur.removeWhere((x) => x.sending && x.text == m.text && (m.dateCreated - x.dateCreated).abs() < 120000);
          }
          _upsert(chatGuid, m);
          changed = true;
        } else {
          final o = cur![i];
          if (o.dateRead != m.dateRead || o.dateDelivered != m.dateDelivered || o.text != m.text || o.attachments.length != m.attachments.length || o.error != m.error) {
            _upsert(chatGuid, m);
            changed = true;
          }
        }
      }
      if (list.isNotEmpty) {
        final c = chatByGuid(chatGuid);
        if (c != null && list.first.dateCreated > c.lastDate) {
          _bumpChat(chatGuid, list.first);
          changed = true;
        }
      }
      if (changed) notifyListeners();
    } catch (_) {}
  }

  void _upsert(String chatGuid, Message m) {
    final list = _messages[chatGuid] ?? [];
    final i = list.indexWhere((x) => x.guid == m.guid || (m.tempGuid != null && x.guid == m.tempGuid));
    if (i >= 0) {
      list[i] = m;
    } else {
      list.insert(0, m);
      list.sort((a, b) => b.dateCreated.compareTo(a.dateCreated));
    }
    _messages[chatGuid] = list;
  }

  void _bumpChat(String chatGuid, Message m) {
    final i = chats.indexWhere((c) => c.guid == chatGuid);
    if (i < 0) {
      // A chat we haven't seen yet (e.g. someone started a new group). Fetch it.
      if (!_fetchingChats.add(chatGuid)) return;
      api?.chat(chatGuid).then((c) {
        if (chats.every((x) => x.guid != c.guid)) {
          chats = _ordered([c.copyWith(lastMessage: m), ...chats]);
          notifyListeners();
        }
      }).catchError((_) {}).whenComplete(() => _fetchingChats.remove(chatGuid));
      return;
    }
    final c = chats.removeAt(i).copyWith(lastMessage: m);
    chats.insert(0, c);
    if (m.isFromMe || openChat == chatGuid) {
      _lastRead[chatGuid] = m.dateCreated;
      settings.prefs.setString('last_read', jsonEncode(_lastRead));
    }
  }

  Future<void> sendText(Chat chat, String text, {String? replyTo}) async {
    final a = api;
    if (a == null || text.trim().isEmpty) return;
    final temp = BBApi.newTempGuid();
    final local = Message(
      guid: temp,
      tempGuid: temp,
      text: text.trim(),
      isFromMe: true,
      dateCreated: DateTime.now().millisecondsSinceEpoch,
      sending: true,
      threadOriginatorGuid: replyTo,
    );
    _upsert(chat.guid, local);
    _bumpChat(chat.guid, local);
    notifyListeners();
    if (conn != Conn.online && conn != Conn.connecting) {
      _enqueue(chat.guid, temp, text.trim(), replyTo, local.dateCreated);
      notifyListeners();
      return;
    }
    try {
      final sent = await a.sendText(chat.guid, text.trim(), tempGuid: temp, privateApi: privateApi, replyToGuid: replyTo);
      _replaceTemp(chat.guid, temp, sent);
    } on ApiException catch (e) {
      if (_unreachable(e)) {
        _enqueue(chat.guid, temp, text.trim(), replyTo, local.dateCreated);
      } else {
        _markFailed(chat.guid, temp);
        lastError = e.message;
      }
    }
    notifyListeners();
  }

  void _enqueue(String chatGuid, String temp, String text, String? replyTo, int at) {
    _queue.add({'chat': chatGuid, 'temp': temp, 'text': text, 'reply': replyTo, 'at': at});
    _saveQueue();
    final list = _messages[chatGuid];
    final i = list?.indexWhere((m) => m.guid == temp) ?? -1;
    if (i >= 0) list![i] = list[i].copyWith(sending: false, queued: true);
  }

  Future<void> sendFile(Chat chat, File file) async {
    final a = api;
    if (a == null) return;
    final temp = BBApi.newTempGuid();
    final local = Message(
      guid: temp,
      tempGuid: temp,
      text: '',
      isFromMe: true,
      dateCreated: DateTime.now().millisecondsSinceEpoch,
      sending: true,
      attachments: [Attachment(guid: temp, transferName: file.path.split(Platform.pathSeparator).last, mimeType: 'local/${file.path}')],
    );
    _upsert(chat.guid, local);
    notifyListeners();
    try {
      final sent = await a.sendAttachment(chat.guid, file, tempGuid: temp, privateApi: privateApi);
      _replaceTemp(chat.guid, temp, sent);
    } on ApiException catch (e) {
      _markFailed(chat.guid, temp);
      lastError = e.message;
    }
    notifyListeners();
  }

  Future<void> retry(Chat chat, Message m) async {
    _messages[chat.guid]?.removeWhere((x) => x.guid == m.guid);
    await sendText(chat, m.text);
  }

  void _replaceTemp(String chatGuid, String temp, Message sent) {
    final list = _messages[chatGuid] ?? [];
    list.removeWhere((x) => x.guid == temp || x.guid == sent.guid);
    _messages[chatGuid] = list;
    _upsert(chatGuid, sent);
    _bumpChat(chatGuid, sent);
  }

  void _markFailed(String chatGuid, String temp) {
    final list = _messages[chatGuid];
    if (list == null) return;
    final i = list.indexWhere((x) => x.guid == temp);
    if (i >= 0) list[i] = list[i].copyWith(sending: false, failed: true);
  }

  Future<String?> react(Chat chat, Message target, String kind) async {
    if (!privateApi) return 'Reactions need the Private API on your Mac (Settings → Mac relay).';
    try {
      await api!.react(chat.guid, target.guid, kind);
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<String?> startChat(List<String> addresses, String message) async {
    final a = api;
    if (a == null) return 'Not connected.';
    try {
      final c = await a.newChat(addresses, message, tempGuid: BBApi.newTempGuid(), privateApi: privateApi);
      await refreshChats();
      if (c != null) openChat = c.guid;
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  // ------------------------------------------------------------ socket events

  void _onEvent(SocketEvent e) {
    final d = e.data;
    switch (e.type) {
      case 'new-message':
      case 'updated-message':
      case 'group-name-change':
      case 'participant-added':
      case 'participant-removed':
      case 'participant-left':
        if (d is! Map) return;
        final m = Message.fromJson(Map<String, dynamic>.from(d));
        for (final g in m.chatGuids) {
          if (m.tempGuid != null) {
            _replaceTemp(g, m.tempGuid!, m);
          } else {
            _upsert(g, m);
            if (e.type != 'updated-message') _bumpChat(g, m);
          }
          if (e.type == 'group-name-change' && m.groupTitle != null) {
            final i = chats.indexWhere((c) => c.guid == g);
            if (i >= 0) chats[i] = chats[i].copyWith(displayName: m.groupTitle);
          }
          if (e.type == 'new-message' && !m.isFromMe && openChat != g && !m.isReaction) {
            final c = chatByGuid(g);
            if (c != null && !settings.isMuted(c.guid)) _banners.add(MsgBanner(c, m));
          } else if (e.type == 'new-message' && !m.isFromMe && openChat == g && appActive) {
            // You're looking at this chat right now: it's read, no notification.
            final c = chatByGuid(g);
            if (c != null) scheduleMicrotask(() => markRead(c));
          }
          typing.remove(g);
        }
        notifyListeners();
      case 'message-send-error':
        if (d is! Map) return;
        final m = Message.fromJson(Map<String, dynamic>.from(d));
        for (final g in m.chatGuids) {
          if (m.tempGuid != null) _markFailed(g, m.tempGuid!);
        }
        notifyListeners();
      case 'typing-indicator':
        if (d is! Map) return;
        final g = d['guid']?.toString();
        if (g == null) return;
        d['display'] == true ? typing.add(g) : typing.remove(g);
        notifyListeners();
      case 'chat-read-status-changed':
        if (d is Map && d['read'] == true && d['chatGuid'] != null) {
          final c = chatByGuid(d['chatGuid'].toString());
          if (c != null) {
            _lastRead[c.guid] = c.lastMessage?.dateCreated ?? 0;
            notifyListeners();
          }
        }
      case 'new-server':
        final url = d?.toString();
        if (url != null && url.startsWith('http')) {
          settings.updateServerUrl(BBApi.sanitizeUrl(url)).then((_) => connect());
        }
    }
  }

  // ------------------------------------------------------------ local caches

  void _loadLocalCaches() {
    try {
      _lastRead = Map<String, int>.from(jsonDecode(settings.prefs.getString('last_read') ?? '{}'));
      _names.addAll(Map<String, String>.from(jsonDecode(settings.prefs.getString('contact_names') ?? '{}')));
      final raw = settings.prefs.getString('chat_cache');
      if (raw != null && chats.isEmpty) {
        chats = (jsonDecode(raw) as List).map((j) => Chat.fromJson(Map<String, dynamic>.from(j))).toList();
      }
    } catch (_) {}
  }

  void _saveChatCache() {
    // Small cache so the list appears instantly on launch, before the Mac answers.
    final slim = chats.take(60).map((c) => {
          'guid': c.guid,
          'style': c.style,
          'chatIdentifier': c.chatIdentifier,
          'displayName': c.displayName,
          'participants': c.participants.map((p) => {'address': p.address, 'service': p.service}).toList(),
          if (c.lastMessage != null)
            'lastMessage': {
              'guid': c.lastMessage!.guid,
              'text': c.lastMessage!.text,
              'isFromMe': c.lastMessage!.isFromMe,
              'dateCreated': c.lastMessage!.dateCreated,
              if (c.lastMessage!.handle != null) 'handle': {'address': c.lastMessage!.handle!.address},
            },
        });
    settings.prefs.setString('chat_cache', jsonEncode(slim.toList()));
  }

  @override
  void dispose() {
    _evSub?.cancel();
    _stSub?.cancel();
    _pingTimer?.cancel();
    _pollTimer?.cancel();
    _netDebounce?.cancel();
    _netSub?.cancel();
    socket.disconnect();
    avatars.dispose();
    super.dispose();
  }
}

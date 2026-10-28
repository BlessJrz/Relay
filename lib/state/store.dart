import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
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

  /// Set from the app lifecycle: false while Relay is in the background or
  /// locked. Polling pauses and nothing is marked read while it's false.
  bool appActive = true;

  /// True while the real-time link to the Mac is up.
  bool get live => socket.state == SocketState.connected;

  /// The Mac answers, but the real-time link dropped (polling fills in).
  bool get liveLinkDown => conn == Conn.online && _liveDown && !live;
  bool _liveDown = false, _wasLive = false;

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
  final Map<String, Timer> _typingTimers = {};
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
      _offlineTimer ??= Timer(const Duration(minutes: 3), () async {
        _offlineTimer = null;
        if (conn != Conn.offline || !settings.macOfflineAlert) return;
        // If the phone itself has no internet, it's not the Mac's fault.
        try {
          final net = await Connectivity().checkConnectivity();
          if (net.every((n) => n == ConnectivityResult.none)) return;
        } catch (_) {}
        if (conn != Conn.offline) return;
        _offlineAlerted = true;
        Push.instance.showMacOffline();
      });
    } else {
      _offlineTimer?.cancel();
      _offlineTimer = null;
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

  /// The message certainly never reached the Mac (so queueing can't double-send).
  /// Timeouts (408/504) might have gone through, so those are shown as failed for a manual retry.
  static bool _unreachable(ApiException e) => e.status == 0 || e.status == 502 || e.status == 503 || e.status == 530;

  Future<void> _flushQueue() async {
    if (api == null || _flushing) return;
    _flushing = true;
    try {
      while (_queue.isNotEmpty) {
        final a = api;
        if (a == null) break;
        final q = _queue.first;
        final g = q['chat'] as String, temp = q['temp'] as String, text = q['text'] as String;
        final i = (_messages[g] ?? []).indexWhere((m) => m.guid == temp);
        if (i < 0) {
          // Already arrived (e.g. the Mac sent it and told us over the socket).
          _queue.remove(q);
          _saveQueue();
          continue;
        }
        _messages[g]![i] = _messages[g]![i].copyWith(queued: false, sending: true);
        notifyListeners();
        try {
          // An earlier try can reach the Mac even though we never heard back:
          // look before sending it again.
          var sent = q['tried'] == false ? null : await _findSent(a, g, text, q['at'] as int);
          if (sent == null) {
            q['tried'] = true;
            sent = await a.sendText(g, text, tempGuid: temp, privateApi: privateApi, replyToGuid: q['reply']);
          }
          _replaceTemp(g, temp, sent);
        } on ApiException catch (e) {
          if (_unreachable(e)) {
            final j = (_messages[g] ?? []).indexWhere((m) => m.guid == temp);
            if (j >= 0) _messages[g]![j] = _messages[g]![j].copyWith(queued: true, sending: false);
            _saveQueue();
            break;
          }
          _markFailed(g, temp);
          lastError = e.message;
        } catch (e) {
          _markFailed(g, temp);
          lastError = 'Couldn’t send: $e';
        }
        _queue.remove(q);
        _saveQueue();
      }
    } finally {
      _flushing = false;
      notifyListeners();
    }
  }

  /// A message from me with this text that the Mac has from [since] on and
  /// that this phone doesn't know yet, i.e. an earlier try that got through.
  Future<Message?> _findSent(BBApi a, String chatGuid, String text, int since) async {
    final recent = await a.messages(chatGuid, limit: 20);
    final known = {for (final m in _messages[chatGuid] ?? const <Message>[]) m.guid};
    for (final m in recent.reversed) {
      if (m.isFromMe && m.error == 0 && m.text == text && m.dateCreated >= since - 10000 && !known.contains(m.guid)) return m;
    }
    return null;
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

  /// "Mark read" on a notification while Relay was closed writes straight to
  /// storage; fold those in (newest wins) so they aren't lost.
  Future<void> _mergeReadFromNotifications() async {
    try {
      await settings.prefs.reload();
      final saved = Map<String, int>.from(jsonDecode(settings.prefs.getString('last_read') ?? '{}'));
      var changed = false;
      saved.forEach((g, t) {
        if (t > (_lastRead[g] ?? 0)) {
          _lastRead[g] = t;
          changed = true;
        }
      });
      if (changed) notifyListeners();
    } catch (_) {}
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
    if (_queue.isNotEmpty && conn == Conn.online) unawaited(_flushQueue());
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
    await _mergeReadFromNotifications();
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

  Future<String?>? _connecting;
  String? _connectingTo;
  BBApi? _connectedApi; // the client the last full connect finished with

  String get _target => '${settings.serverUrl}\n${settings.password}';

  /// Connects using saved settings. Returns null on success or an error message.
  /// Only one runs at a time; a call made meanwhile waits for it (and goes
  /// again if the address or password changed in between).
  Future<String?> connect() async {
    while (true) {
      final running = _connecting;
      if (running == null) break;
      final same = _connectingTo == _target;
      final r = await running;
      if (same) return r;
    }
    _connectingTo = _target;
    final f = _connecting = _connectSafely();
    try {
      return await f;
    } finally {
      if (identical(_connecting, f)) _connecting = null;
    }
  }

  Future<String?> _connectSafely() async {
    try {
      return await _connect();
    } catch (e) {
      // Never stay stuck on "connecting".
      if (conn == Conn.connecting) conn = Conn.offline;
      lastError = 'Couldn’t connect: $e';
      _keepPinging();
      notifyListeners();
      return lastError;
    }
  }

  /// Keeps checking the Mac, so Relay connects by itself once it answers.
  void _keepPinging() {
    if (_pingTimer?.isActive ?? false) return;
    _pingTimer = Timer.periodic(const Duration(seconds: 45), (_) => _measure());
  }

  Future<String?> _connect() async {
    api?.close(); // waits for sends already under way
    final a = api = BBApi(serverUrl: settings.serverUrl, password: settings.password);
    conn = Conn.connecting;
    lastError = null;
    notifyListeners();
    try {
      latency = await a.ping();
      _recordLatency();
      info = await a.serverInfo();
      // Remembered for replies sent straight from a notification.
      unawaited(settings.prefs.setBool('private_api', privateApi));
    } on ApiException catch (e) {
      if (e.isAuth) {
        conn = Conn.badPassword;
      } else {
        conn = Conn.offline;
        // A trycloudflare URL changes whenever the Mac restarts. Ask Firebase for the new one.
        if (await recoverServerUrl()) {
          _connectingTo = _target;
          return _connect();
        }
      }
      lastError = e.message;
      _keepPinging();
      notifyListeners();
      return e.message;
    }
    conn = Conn.online;
    _connectedApi = a;
    _listenSocket();
    socket.connect(a.origin, settings.password, a.headers);
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 45), (_) => _measure());
    _startPolling();
    notifyListeners();
    unawaited(refreshChats().then((_) => avatars.syncGroupIcons(api, chats)));
    unawaited(loadContacts());
    unawaited(avatars.syncContacts(a));
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
        _liveDown = false;
        conn = Conn.online;
        refreshChats(); // catch up on anything missed while disconnected
        final open = openChat;
        if (open != null) syncMessages(open);
      } else if (s == SocketState.disconnected) {
        _liveDown = true;
        _clearTyping(); // no "stopped typing" will arrive now
        // The live link dropped, but the Mac may still answer: check now
        // instead of calling it offline (polling keeps messages coming).
        if (_wasLive && conn == Conn.online) unawaited(_measure(reconnectSocket: false));
      }
      _wasLive = s == SocketState.connected;
      notifyListeners();
    });
  }

  bool _measuring = false;

  Future<void> _measure({bool reconnectSocket = true}) async {
    final a = api;
    if (a == null || _measuring) return;
    _measuring = true;
    try {
      latency = await a.ping();
      _recordLatency();
      if (!identical(_connectedApi, a)) {
        // The Mac answers now, but connecting never finished (e.g. it was
        // away when Relay started): do the whole connect.
        _measuring = false;
        await connect();
        return;
      }
      if (conn != Conn.online) {
        conn = Conn.online;
        if (!live) socket.reconnect();
      } else if (reconnectSocket && socket.state == SocketState.disconnected) {
        socket.reconnect(); // the live link stays down by itself after some drops
      }
      if (_queue.isNotEmpty) unawaited(_flushQueue());
    } on ApiException catch (e) {
      conn = e.isAuth ? Conn.badPassword : Conn.offline;
      lastError = e.message;
      if (!e.isAuth && await recoverServerUrl()) {
        _measuring = false;
        await connect();
        return;
      }
    } catch (e) {
      conn = Conn.offline;
      lastError = '$e';
    } finally {
      _measuring = false;
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
    _offlineTimer?.cancel();
    _offlineTimer = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    _pollTimer?.cancel();
    _connectedApi = null;
    socket.disconnect();
    _clearTyping();
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
        if (announce && m != null && m.guid != old.lastMessage?.guid && c.lastDate > old.lastDate && !m.isFromMe && !m.isReaction && m.hasContent && !m.isGroupEvent && openChat != c.guid) {
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
      contactsRev++;
      notifyListeners();
    } catch (_) {}
  }

  /// Goes up each time contact names reload, so screens know names may have changed.
  int contactsRev = 0;

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
      final n = m.attachments.length;
      body = a.isImage
          ? (n > 1 ? '$n photos' : 'Photo')
          : a.isVideo
              ? 'Video'
              : a.isAudio
                  ? 'Voice message'
                  : (a.transferName.isEmpty ? 'Attachment' : a.transferName);
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

  void markRead(Chat c) => _markRead(c.guid, c.lastMessage?.dateCreated ?? DateTime.now().millisecondsSinceEpoch);

  /// Mark read (or Reply) on a notification: everything up to now is read,
  /// even a message the chat list hasn't caught up with yet.
  void markReadFromNotification(String chatGuid) {
    final last = chatByGuid(chatGuid)?.lastMessage?.dateCreated ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    _markRead(chatGuid, last > now ? last : now);
  }

  void _markRead(String chatGuid, int upTo) {
    _setLastRead(chatGuid, upTo);
    if (privateApi) api?.markRead(chatGuid).catchError((_) {});
    Push.instance.clearChat(chatGuid);
    notifyListeners();
  }

  /// Moves "read up to" forward only (Mark as unread sets it directly).
  void _setLastRead(String chatGuid, int t) {
    if (t <= (_lastRead[chatGuid] ?? 0)) return;
    _lastRead[chatGuid] = t;
    settings.prefs.setString('last_read', jsonEncode(_lastRead));
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
          // Merge rather than replace: keep messages that came over the live
          // link while this loaded, and sends the Mac doesn't know about yet.
          final fetched = {for (final m in list) m.guid};
          var oldest = 0;
          for (final m in list) {
            if (oldest == 0 || m.dateCreated < oldest) oldest = m.dateCreated;
          }
          final keep = [
            for (final m in _messages[chatGuid] ?? const <Message>[])
              if (!fetched.contains(m.guid) && (m.sending || m.failed || m.queued || m.dateCreated >= oldest)) m,
          ];
          for (final m in list.reversed) {
            _claimTemp(keep, m);
          }
          _messages[chatGuid] = [...keep, ...list]..sort((x, y) => y.dateCreated.compareTo(x.dateCreated)); // as _upsert
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
      final local = _messages[chatGuid] ?? const <Message>[];
      final known = {for (final m in local) m.guid};
      final hasReal = local.any((m) => !m.sending && !m.failed && !m.queued);
      if (list.isNotEmpty && hasReal && !list.any((m) => known.contains(m.guid))) {
        // More came in than this looks at: merging would leave a gap. Reload.
        await loadMessages(chatGuid);
        changed = true;
      } else {
        for (final m in list.reversed) {
          final cur = _messages[chatGuid];
          final i = cur?.indexWhere((x) => x.guid == m.guid) ?? -1;
          if (i < 0) {
            // A message of mine still showing as sending (or failed) may be this one.
            if (cur != null) _claimTemp(cur, m);
            _upsert(chatGuid, m);
            changed = true;
          } else {
            final o = cur![i];
            if (o.dateRead != m.dateRead || o.dateDelivered != m.dateDelivered || o.text != m.text || o.attachments.length != m.attachments.length || o.error != m.error || o.dateEdited != m.dateEdited || o.dateRetracted != m.dateRetracted) {
              _upsert(chatGuid, m);
              changed = true;
            }
          }
        }
        _msgError.remove(chatGuid);
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

  /// Photos and videos we just sent, by the Mac's attachment id → the file on
  /// this phone. The chat keeps showing the file instead of downloading it
  /// back from the Mac, so a sent photo doesn't flash blank.
  final Map<String, String> _localCopies = {};
  String? localCopyOf(String attachmentGuid) => _localCopies[attachmentGuid];

  void _keepLocalCopies(Message old, Message sent) {
    final local = old.attachments.where((a) => (a.mimeType ?? '').startsWith('local/')).toList();
    for (var i = 0; i < local.length && i < sent.attachments.length; i++) {
      _localCopies[sent.attachments[i].guid] = local[i].mimeType!.substring(6);
    }
  }

  /// Whether [m], from the Mac, is the copy of [local], a bubble of mine that
  /// is sending, failed or waiting (a failed or waiting one may have got through).
  static bool _sameSend(Message local, Message m) {
    if (!m.isFromMe || local.text.isEmpty || local.text != m.text) return false;
    if (local.attachments.isEmpty != m.attachments.isEmpty) return false;
    final d = m.dateCreated - local.dateCreated;
    if (d < -10000) return false; // clocks can be a few seconds apart
    if (local.sending) return d < 180000;
    if (local.attachments.isNotEmpty || m.error != 0) return false;
    if (local.queued) return true; // may have gone out on any later try
    return local.failed && d < 180000;
  }

  /// [m] came from the Mac: drop the local bubble it stands for (the oldest match).
  void _claimTemp(List<Message> list, Message m) {
    final i = list.lastIndexWhere((x) => _sameSend(x, m));
    if (i < 0) return;
    _keepLocalCopies(list[i], m);
    list.removeAt(i);
  }

  void _upsert(String chatGuid, Message m) {
    final list = _messages[chatGuid] ?? [];
    final i = list.indexWhere((x) => x.guid == m.guid || (m.tempGuid != null && x.guid == m.tempGuid));
    if (i >= 0) {
      if (list[i].guid != m.guid) _keepLocalCopies(list[i], m);
      list[i] = m;
    } else {
      list.insert(0, m);
      list.sort((a, b) => b.dateCreated.compareTo(a.dateCreated));
    }
    _messages[chatGuid] = list;
  }

  /// Puts [m] on the chat-list row and moves the chat to the top. With
  /// [update] (an edit or receipt) it only refreshes the row if [m] is the
  /// message already shown there.
  void _bumpChat(String chatGuid, Message m, {bool update = false}) {
    final i = chats.indexWhere((c) => c.guid == chatGuid);
    if (i < 0) {
      if (update) return;
      // A chat we haven't seen yet (e.g. someone started a new group). Fetch it.
      if (!_fetchingChats.add(chatGuid)) return;
      api?.chat(chatGuid).then((c) {
        if (chats.every((x) => x.guid != c.guid)) {
          chats = _ordered([c.lastDate >= m.dateCreated ? c : c.copyWith(lastMessage: m), ...chats]);
          notifyListeners();
        }
      }).catchError((_) {}).whenComplete(() => _fetchingChats.remove(chatGuid));
      return;
    }
    final cur = chats[i].lastMessage;
    final same = cur != null && (cur.guid == m.guid || (m.tempGuid != null && cur.guid == m.tempGuid));
    if (same) {
      chats[i] = chats[i].copyWith(lastMessage: m);
    } else {
      // Never go back to an older message (late events, slow replies). A
      // bubble still on its way (phone clock) may be replaced, though.
      final localOnly = cur != null && cur.guid == cur.tempGuid;
      if (update || (cur != null && !localOnly && m.dateCreated < cur.dateCreated)) return;
      chats.insert(0, chats.removeAt(i).copyWith(lastMessage: m));
    }
    if (!update && (m.isFromMe || (openChat == chatGuid && appActive))) _setLastRead(chatGuid, m.dateCreated);
  }

  Future<void> sendText(Chat chat, String text, {String? replyTo}) async {
    final a = api;
    final body = text.trim();
    if (a == null || body.isEmpty) return;
    final temp = BBApi.newTempGuid();
    final local = Message(
      guid: temp,
      tempGuid: temp,
      text: body,
      isFromMe: true,
      dateCreated: DateTime.now().millisecondsSinceEpoch,
      sending: true,
      threadOriginatorGuid: replyTo,
    );
    _upsert(chat.guid, local);
    _bumpChat(chat.guid, local);
    notifyListeners();
    if (_queue.isNotEmpty) {
      // Older messages are still waiting: this one goes out after them.
      _enqueue(chat.guid, temp, body, replyTo, local.dateCreated, tried: false);
      notifyListeners();
      unawaited(_flushQueue());
      return;
    }
    // Always try, even if Relay thinks the Mac is away; if it really can't be
    // reached the message waits in the queue.
    try {
      final sent = await a.sendText(chat.guid, body, tempGuid: temp, privateApi: privateApi, replyToGuid: replyTo);
      _replaceTemp(chat.guid, temp, sent);
    } on ApiException catch (e) {
      if (_unreachable(e)) {
        _enqueue(chat.guid, temp, body, replyTo, local.dateCreated);
      } else {
        _markFailed(chat.guid, temp);
        lastError = e.message;
      }
    } catch (e) {
      _markFailed(chat.guid, temp);
      lastError = 'Couldn’t send: $e';
    }
    notifyListeners();
  }

  /// [tried]: a send was already attempted (it may have reached the Mac).
  void _enqueue(String chatGuid, String temp, String text, String? replyTo, int at, {bool tried = true}) {
    _queue.add({'chat': chatGuid, 'temp': temp, 'text': text, 'reply': replyTo, 'at': at, 'tried': tried});
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
    } catch (e) {
      // e.g. the file is gone: show it failed instead of spinning forever.
      _markFailed(chat.guid, temp);
      lastError = 'Couldn’t send: $e';
    }
    notifyListeners();
  }

  /// "Try sending again" on a failed bubble.
  Future<void> retry(Chat chat, Message m) async {
    final g = chat.guid;
    // Photos, videos and voice messages keep the file on this phone.
    final files = [
      for (final att in m.attachments)
        if ((att.mimeType ?? '').startsWith('local/')) att.mimeType!.substring(6),
    ];
    final a = api;
    if (a == null || (files.isEmpty && m.text.isEmpty)) return;
    if (files.isEmpty) {
      // A send that timed out may have reached the Mac after all.
      final i = (_messages[g] ?? []).indexWhere((x) => x.guid == m.guid);
      if (i >= 0) _messages[g]![i] = _messages[g]![i].copyWith(failed: false, sending: true);
      notifyListeners();
      Message? found;
      try {
        found = await _findSent(a, g, m.text, m.dateCreated);
      } catch (_) {}
      if (found != null) {
        _replaceTemp(g, m.guid, found);
        notifyListeners();
        return;
      }
      // Meanwhile a sync may have matched it to the Mac's copy.
      if (!(_messages[g] ?? []).any((x) => x.guid == m.guid)) return;
    }
    _messages[g]?.removeWhere((x) => x.guid == m.guid);
    if (files.isNotEmpty) {
      for (final f in files) {
        await sendFile(chat, File(f));
      }
    } else {
      await sendText(chat, m.text, replyTo: m.threadOriginatorGuid);
    }
  }

  void _replaceTemp(String chatGuid, String temp, Message sent, {bool bump = true}) {
    final list = _messages[chatGuid] ?? [];
    final t = list.indexWhere((x) => x.guid == temp);
    if (t >= 0) _keepLocalCopies(list[t], sent);
    list.removeWhere((x) => x.guid == temp || x.guid == sent.guid);
    _messages[chatGuid] = list;
    _upsert(chatGuid, sent);
    _bumpChat(chatGuid, sent, update: !bump);
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

  /// Feeds a live event in as if it came from the Mac (tests only).
  @visibleForTesting
  void debugEvent(String type, dynamic data) => _onEvent(SocketEvent(type, data));

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
        // An update (receipt, edit) doesn't move the chat to the top.
        final isNew = e.type != 'updated-message';
        for (final g in m.chatGuids) {
          if (m.tempGuid != null) {
            _replaceTemp(g, m.tempGuid!, m, bump: isNew);
          } else {
            _upsert(g, m);
            _bumpChat(g, m, update: !isNew);
          }
          if (e.type == 'group-name-change' && m.groupTitle != null) {
            final i = chats.indexWhere((c) => c.guid == g);
            if (i >= 0) chats[i] = chats[i].copyWith(displayName: m.groupTitle);
          }
          if (e.type == 'new-message' && !m.isFromMe && openChat != g && !m.isReaction) {
            // Only real messages get a banner (not empty ones or group events).
            final c = chatByGuid(g);
            if (c != null && m.hasContent && !m.isGroupEvent && !settings.isMuted(c.guid)) _banners.add(MsgBanner(c, m));
          } else if (e.type == 'new-message' && !m.isFromMe && openChat == g && appActive) {
            // You're looking at this chat right now: it's read, no notification.
            final c = chatByGuid(g);
            if (c != null) scheduleMicrotask(() => markRead(c));
          }
          _setTyping(g, false);
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
        _setTyping(g, d['display'] == true);
        notifyListeners();
      case 'chat-read-status-changed':
        if (d is Map && d['read'] == true && d['chatGuid'] != null) {
          final c = chatByGuid(d['chatGuid'].toString());
          if (c != null) {
            _setLastRead(c.guid, c.lastMessage?.dateCreated ?? 0);
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

  void _setTyping(String chatGuid, bool on) {
    _typingTimers.remove(chatGuid)?.cancel();
    if (!on) {
      typing.remove(chatGuid);
      return;
    }
    typing.add(chatGuid);
    // The "stopped typing" event can get lost: don't show the dots forever.
    _typingTimers[chatGuid] = Timer(const Duration(seconds: 60), () {
      _typingTimers.remove(chatGuid);
      if (typing.remove(chatGuid)) notifyListeners();
    });
  }

  void _clearTyping() {
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    _typingTimers.clear();
    typing.clear();
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
    _offlineTimer?.cancel();
    _evSub?.cancel();
    _stSub?.cancel();
    _pingTimer?.cancel();
    _pollTimer?.cancel();
    _netDebounce?.cancel();
    _netSub?.cancel();
    _clearTyping();
    socket.disconnect();
    avatars.dispose();
    super.dispose();
  }
}

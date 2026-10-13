import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../api/bb_api.dart';
import '../api/models.dart';
import '../api/socket.dart';
import '../push/push.dart';
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
  Store(this.settings);

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
    await connect();
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
    notifyListeners();
    unawaited(refreshChats());
    unawaited(loadContacts());
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
    socket.disconnect();
    conn = Conn.notConfigured;
    notifyListeners();
  }

  // ------------------------------------------------------------ chats

  Future<void> refreshChats() async {
    final a = api;
    if (a == null) return;
    chatsLoading = true;
    notifyListeners();
    try {
      final list = await a.chats(limit: 150);
      list.sort((x, y) => y.lastDate.compareTo(x.lastDate));
      chats = list;
      _saveChatCache();
    } on ApiException catch (e) {
      lastError = e.message;
    }
    chatsLoading = false;
    notifyListeners();
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

  Future<void> loadMessages(String chatGuid, {bool older = false}) async {
    final a = api;
    if (a == null) return;
    final current = _messages[chatGuid] ?? [];
    final before = older && current.isNotEmpty ? current.last.dateCreated : null;
    try {
      final list = await a.messages(chatGuid, limit: 60, before: before);
      if (older) {
        _messages[chatGuid] = [...current, ...list];
      } else {
        // Keep local in-flight messages that the server doesn't know yet.
        final pending = current.where((m) => m.sending || m.failed).toList();
        _messages[chatGuid] = [...pending, ...list];
      }
      _hasMore[chatGuid] = list.length >= 60;
      notifyListeners();
    } on ApiException catch (e) {
      lastError = e.message;
      notifyListeners();
    }
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
      api?.chat(chatGuid).then((c) {
        chats.insert(0, c.copyWith(lastMessage: m));
        notifyListeners();
      }).catchError((_) {});
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
    try {
      final sent = await a.sendText(chat.guid, text.trim(), tempGuid: temp, privateApi: privateApi, replyToGuid: replyTo);
      _replaceTemp(chat.guid, temp, sent);
    } on ApiException catch (e) {
      _markFailed(chat.guid, temp);
      lastError = e.message;
    }
    notifyListeners();
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
            if (c != null) _banners.add(MsgBanner(c, m));
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
    socket.disconnect();
    super.dispose();
  }
}

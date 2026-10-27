import 'dart:convert';
import 'dart:math';
import 'dart:isolate';
import 'dart:ui' show DartPluginRegistrant, IsolateNameServer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' as fln;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/models.dart';
import '../state/store.dart';

/// Runs in its own isolate when a push arrives while the app is in the
/// background or closed. Must be a top-level function.
@pragma('vm:entry-point')
Future<void> relayBackgroundPush(RemoteMessage msg) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload(); // this isolate can outlive changes made in the app
  await Push.initFirebase(prefs);
  await Push.instance.initLocal();
  await Push.instance.handleData(msg.data, prefs);
}

/// Runs when you tap Reply or Mark read on a notification while Relay isn't
/// open (also from a watch). Sends straight to the Mac.
@pragma('vm:entry-point')
Future<void> relayNotificationAction(fln.NotificationResponse r) async {
  DartPluginRegistrant.ensureInitialized();
  // Relay is running: hand the action to it so the live app updates.
  final app = IsolateNameServer.lookupPortByName(Push.actionPort);
  if (app != null && r.payload != null) {
    app.send({'action': r.actionId, 'chat': r.payload, 'text': r.input});
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  await Push.instance.initLocal();
  await Push.instance.handleAction(r, prefs);
}

/// Push notifications. BlueBubbles Server sends data-only FCM messages through
/// the Firebase project you created during Mac setup. We read that project's
/// config from the Mac at runtime, so nothing Firebase-specific is baked in.
class Push {
  Push._();
  static final Push instance = Push._();

  final _local = fln.FlutterLocalNotificationsPlugin();
  bool _localReady = false;
  void Function(String chatGuid)? onOpenChat;

  static const actionPort = 'relay_notification_actions';
  ReceivePort? _port;

  /// While Relay runs, Reply / Mark read taps (which Android delivers to a
  /// separate background isolate) are forwarded here.
  void listenForActions() {
    _port?.close();
    final port = ReceivePort();
    IsolateNameServer.removePortNameMapping(actionPort);
    IsolateNameServer.registerPortWithName(port.sendPort, actionPort);
    port.listen((m) async {
      if (m is! Map) return;
      final prefs = await SharedPreferences.getInstance();
      await handleAction(
        fln.NotificationResponse(
          notificationResponseType: fln.NotificationResponseType.selectedNotificationAction,
          actionId: m['action'] as String?,
          payload: m['chat'] as String?,
          input: m['text'] as String?,
        ),
        prefs,
      );
    });
    _port = port;
  }

  /// Set by the app while it's running, so actions go through the live store.
  /// Returns false if the reply couldn't be handed to the live store.
  Future<bool> Function(String chatGuid, String text)? onReply;
  void Function(String chatGuid)? onMarkRead;
  bool appInForeground = true;

  static const _replyAction = 'reply', _readAction = 'read';
  static const _offlineId = 7001;

  static const _channel = fln.AndroidNotificationDetails(
    'messages',
    'Messages',
    channelDescription: 'New iMessages and texts relayed from your Mac',
    importance: fln.Importance.high,
    priority: fln.Priority.high,
    category: fln.AndroidNotificationCategory.message,
  );

  static FirebaseOptions? _options(Map<String, dynamic> cfg) {
    try {
      final project = Map<String, dynamic>.from(cfg['project_info']);
      final client = Map<String, dynamic>.from((cfg['client'] as List).first);
      String clientId = (client['oauth_client'] as List).first['client_id'].toString();
      if (clientId.contains('-')) clientId = clientId.substring(0, clientId.indexOf('-'));
      final sender = (project['project_number'] ?? clientId).toString();
      return FirebaseOptions(
        apiKey: (client['api_key'] as List).first['current_key'].toString(),
        appId: client['client_info']['mobilesdk_app_id'].toString(),
        messagingSenderId: sender,
        projectId: project['project_id'].toString(),
        storageBucket: project['storage_bucket']?.toString(),
        databaseURL: project['firebase_url']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<bool> initFirebase(SharedPreferences prefs) async {
    if (Firebase.apps.isNotEmpty) return true;
    final raw = prefs.getString('fcm_config');
    if (raw == null) return false;
    final opts = _options(jsonDecode(raw));
    if (opts == null) return false;
    try {
      await Firebase.initializeApp(options: opts);
      return true;
    } catch (e) {
      debugPrint('Firebase init failed: $e');
      return false;
    }
  }

  Future<void> initLocal() async {
    if (_localReady) return;
    const init = fln.InitializationSettings(android: fln.AndroidInitializationSettings('@drawable/ic_stat_relay'));
    await _local.initialize(
      init,
      onDidReceiveNotificationResponse: (r) async {
        if (r.actionId == _replyAction || r.actionId == _readAction) {
          final prefs = await SharedPreferences.getInstance();
          await handleAction(r, prefs);
          return;
        }
        final g = r.payload;
        if (g != null && g.isNotEmpty) onOpenChat?.call(g);
      },
      onDidReceiveBackgroundNotificationResponse: relayNotificationAction,
    );
    _localReady = true;
  }

  /// Chat to open if the app was launched by tapping a notification.
  Future<String?> launchChat() async {
    final d = await _local.getNotificationAppLaunchDetails();
    if (d?.didNotificationLaunchApp == true) return d!.notificationResponse?.payload;
    return null;
  }

  Future<bool> requestPermission() async {
    await initLocal();
    final android = _local.resolvePlatformSpecificImplementation<fln.AndroidFlutterLocalNotificationsPlugin>();
    final ok = await android?.requestNotificationsPermission();
    return ok ?? true;
  }

  /// Fetches the Firebase config from the Mac, starts Firebase and registers
  /// this phone so the Mac can push to it. Returns null on success or a reason.
  Future<String?> register(Store store) async {
    final api = store.api;
    if (api == null) return 'Not connected to your Mac yet.';
    try {
      final cfg = await api.fcmClient();
      if (cfg == null) {
        return 'Your Mac has no Firebase set up, so notifications only arrive while Relay is open. '
            'Finish the Notifications step in BlueBubbles Server on the Mac, then try again.';
      }
      final prefs = store.settings.prefs;
      final old = prefs.getString('fcm_config');
      await prefs.setString('fcm_config', jsonEncode(cfg));
      if (old != null && old != jsonEncode(cfg) && Firebase.apps.isNotEmpty) {
        await Firebase.app().delete();
      }
      if (!await initFirebase(prefs)) return 'Couldn’t start Firebase with your Mac’s settings.';
      await initLocal();
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission();
      final token = await fm.getToken();
      if (token == null) return 'Google Play services didn’t give us a push token.';
      await api.registerDevice('Relay · Android', token);
      fm.onTokenRefresh.listen((t) => store.api?.registerDevice('Relay · Android', t));
      // Relay is open: the live link updates the screen, but a message in a
      // chat you're not looking at still gets a notification.
      FirebaseMessaging.onMessage.listen((rm) => _whileOpenPush(rm.data, store));
      return null;
    } catch (e) {
      return 'Notifications setup failed: $e';
    }
  }

  Future<void> handleData(Map<String, dynamic> data, SharedPreferences prefs) async {
    final type = data['type']?.toString();
    final raw = data['data'];
    dynamic payload;
    try {
      payload = raw is String ? jsonDecode(raw) : raw;
    } catch (_) {
      payload = raw;
    }
    if (type == 'new-server' && payload is String && payload.startsWith('http')) {
      await prefs.setString('server_url', payload);
      return;
    }
    if (type != 'new-message' || payload is! Map) return;
    final m = Message.fromJson(Map<String, dynamic>.from(payload));
    if (m.isFromMe || m.isReaction || !m.hasContent) return;
    final chatGuid = m.chatGuids.isNotEmpty ? m.chatGuids.first : '';
    await showMessage(prefs, chatGuid, m, payload['chats'] is List && (payload['chats'] as List).isNotEmpty ? payload['chats'][0] : null);
  }

  // Messages already shown while Relay was open, so the push and the live
  // link don't both announce the same one.
  final _shownWhileOpen = <String>{};

  Future<void> _whileOpenPush(Map<String, dynamic> data, Store store) async {
    if (data['type']?.toString() != 'new-message') return;
    dynamic payload;
    try {
      payload = data['data'] is String ? jsonDecode(data['data']) : data['data'];
    } catch (_) {
      return;
    }
    if (payload is! Map) return;
    final m = Message.fromJson(Map<String, dynamic>.from(payload));
    if (m.isFromMe || m.isReaction || !m.hasContent || m.chatGuids.isEmpty) return;
    final g = m.chatGuids.first;
    if (store.openChat == g && store.appActive) return; // you're looking at it
    final chat = store.chatByGuid(g);
    await showWhileOpen(store.settings.prefs, g, m, title: chat != null && chat.isGroup ? store.titleFor(chat) : null);
  }

  /// While Relay is on screen: a normal phone notification for a message in a
  /// chat you're not looking at. Returns false if it couldn't be shown (for
  /// example notifications are switched off for Relay).
  Future<bool> showWhileOpen(SharedPreferences prefs, String chatGuid, Message m, {String? title}) async {
    if (m.guid.isNotEmpty) {
      if (_shownWhileOpen.contains(m.guid)) return true;
      if (_shownWhileOpen.length > 300) _shownWhileOpen.clear();
      _shownWhileOpen.add(m.guid);
    }
    try {
      await initLocal();
      final android = _local.resolvePlatformSpecificImplementation<fln.AndroidFlutterLocalNotificationsPlugin>();
      if (android != null && await android.areNotificationsEnabled() == false) return false;
      await showMessage(prefs, chatGuid, m, title == null ? null : {'displayName': title});
      return true;
    } catch (e) {
      debugPrint('Notification failed: $e');
      return false;
    }
  }

  Future<void> showMessage(SharedPreferences prefs, String chatGuid, Message m, dynamic chatJson) async {
    await initLocal();
    if ((prefs.getStringList('muted_chats') ?? const []).contains(chatGuid)) return;
    final names = Map<String, String>.from(jsonDecode(prefs.getString('contact_names') ?? '{}'));
    final addr = m.handle?.address ?? '';
    final sender = names[normalizeAddress(addr)] ?? (addr.isEmpty ? 'New message' : addr);
    String? groupName;
    if (chatJson is Map) {
      final dn = (chatJson['displayName'] ?? '').toString();
      if (dn.isNotEmpty) groupName = dn;
    }
    final isGroup = chatGuid.contains(';+;');
    final previews = prefs.getBool('notif_previews') ?? true;
    var body = m.text;
    if (body.isEmpty && m.attachments.isNotEmpty) body = m.attachments.first.isImage ? '📷 Photo' : '📎 Attachment';
    if (!previews) body = 'New message';

    // Keep the last few lines per chat so the notification shows the conversation.
    final key = 'notif_lines_$chatGuid';
    final lines = (prefs.getStringList(key) ?? [])..add(jsonEncode({'s': sender, 't': body, 'd': m.dateCreated}));
    while (lines.length > 6) {
      lines.removeAt(0);
    }
    await prefs.setStringList(key, lines);

    final style = fln.MessagingStyleInformation(
      const fln.Person(name: 'You'),
      groupConversation: isGroup,
      conversationTitle: isGroup ? (groupName ?? 'Group chat') : null,
      messages: lines.map((l) {
        final j = jsonDecode(l);
        return fln.Message(j['t'], DateTime.fromMillisecondsSinceEpoch(j['d']), fln.Person(name: j['s']));
      }).toList(),
    );
    final details = fln.NotificationDetails(
      android: fln.AndroidNotificationDetails(
        _channel.channelId,
        _channel.channelName,
        channelDescription: _channel.channelDescription,
        importance: fln.Importance.high,
        priority: fln.Priority.high,
        category: fln.AndroidNotificationCategory.message,
        styleInformation: style,
        groupKey: 'relay.messages',
        actions: const [
          fln.AndroidNotificationAction(
            _replyAction,
            'Reply',
            inputs: [fln.AndroidNotificationActionInput(label: 'Message')],
            showsUserInterface: false,
            cancelNotification: false,
          ),
          fln.AndroidNotificationAction(_readAction, 'Mark read', showsUserInterface: false, cancelNotification: true),
        ],
      ),
    );
    await _local.show(chatGuid.hashCode & 0x7fffffff, isGroup ? (groupName ?? sender) : sender, body, details, payload: chatGuid);
  }

  /// Reply / Mark read from a notification (app open or closed).
  Future<void> handleAction(fln.NotificationResponse r, SharedPreferences prefs) async {
    final chatGuid = r.payload ?? '';
    if (chatGuid.isEmpty) return;
    if (r.actionId == _readAction) {
      if (onMarkRead != null) {
        onMarkRead!(chatGuid);
      } else {
        await _markReadDirect(chatGuid, prefs);
      }
      await clearChat(chatGuid);
      return;
    }
    final text = (r.input ?? '').trim();
    if (r.actionId != _replyAction || text.isEmpty) return;
    var viaApp = false;
    if (onReply != null) viaApp = await onReply!(chatGuid, text);
    final ok = viaApp || await _sendDirect(chatGuid, text, prefs);
    // Replying means you've read it; take the notification away.
    await clearChat(chatGuid);
    if (ok) {
      if (!viaApp) await _markReadDirect(chatGuid, prefs);
    } else {
      await _local.show(chatGuid.hashCode & 0x7fffffff, 'Reply not sent', 'Couldn’t reach your Mac. Open Relay to try again.',
          const fln.NotificationDetails(android: _channel), payload: chatGuid);
    }
  }

  static Future<({String url, String password})?> _server(SharedPreferences prefs) async {
    final url = (prefs.getString('server_url') ?? '').replaceAll(RegExp(r'/+$'), '');
    final pw = await const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true)).read(key: 'server_password') ?? '';
    if (url.isEmpty || pw.isEmpty) return null;
    return (url: url, password: pw);
  }

  Future<bool> _sendDirect(String chatGuid, String text, SharedPreferences prefs) async {
    final s = await _server(prefs);
    if (s == null) return false;
    final private = prefs.getBool('private_api') ?? false;
    try {
      final res = await http
          .post(
            Uri.parse('${s.url}/api/v1/message/text').replace(queryParameters: {'guid': s.password}),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'chatGuid': chatGuid,
              'message': text,
              'tempGuid': 'temp-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 30)}',
              'method': private ? 'private-api' : 'apple-script',
            }),
          )
          .timeout(const Duration(seconds: 60));
      return res.statusCode < 400;
    } catch (_) {
      return false;
    }
  }

  Future<void> _markReadDirect(String chatGuid, SharedPreferences prefs, {bool serverToo = true}) async {
    try {
      final read = Map<String, int>.from(jsonDecode(prefs.getString('last_read') ?? '{}'));
      read[chatGuid] = DateTime.now().millisecondsSinceEpoch;
      await prefs.setString('last_read', jsonEncode(read));
      if (!serverToo || !(prefs.getBool('private_api') ?? false)) return;
      final s = await _server(prefs);
      if (s == null) return;
      await http.post(Uri.parse('${s.url}/api/v1/chat/${Uri.encodeComponent(chatGuid)}/read').replace(queryParameters: {'guid': s.password})).timeout(const Duration(seconds: 20));
    } catch (_) {}
  }

  static const _statusChannel = fln.AndroidNotificationDetails(
    'status',
    'Mac status',
    channelDescription: 'Tells you when your Mac stops answering, so messages might not be arriving',
    importance: fln.Importance.defaultImportance,
    priority: fln.Priority.defaultPriority,
    onlyAlertOnce: true,
  );

  Future<void> showMacOffline() async {
    await initLocal();
    await _local.show(_offlineId, 'Your Mac isn’t answering', 'New iMessages won’t come through until it’s back. Check it’s awake and online.',
        const fln.NotificationDetails(android: _statusChannel));
  }

  Future<void> clearMacOffline() async {
    if (!_localReady) return;
    await _local.cancel(_offlineId);
  }

  Future<void> clearChat(String chatGuid) async {
    if (!_localReady) return;
    await _local.cancel(chatGuid.hashCode & 0x7fffffff);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // the background handler writes from another isolate
    await prefs.remove('notif_lines_$chatGuid');
  }

  Future<void> test() async {
    await initLocal();
    await _local.show(
      1,
      'Relay',
      'Notifications are working 🎉',
      const fln.NotificationDetails(android: _channel),
    );
  }
}


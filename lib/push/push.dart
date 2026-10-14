import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' as fln;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/models.dart';
import '../state/store.dart';

/// Runs in its own isolate when a push arrives while the app is in the
/// background or closed. Must be a top-level function.
@pragma('vm:entry-point')
Future<void> relayBackgroundPush(RemoteMessage msg) async {
  final prefs = await SharedPreferences.getInstance();
  await Push.initFirebase(prefs);
  await Push.instance.initLocal();
  await Push.instance.handleData(msg.data, prefs);
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
  bool appInForeground = true;

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
      onDidReceiveNotificationResponse: (r) {
        final g = r.payload;
        if (g != null && g.isNotEmpty) onOpenChat?.call(g);
      },
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
      FirebaseMessaging.onMessage.listen((m) {
        // Foreground: the live socket already updates the UI, and the app shows
        // its own in-app banner, so no system notification here.
      });
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

  Future<void> showMessage(SharedPreferences prefs, String chatGuid, Message m, dynamic chatJson) async {
    await initLocal();
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
      ),
    );
    await _local.show(chatGuid.hashCode & 0x7fffffff, isGroup ? (groupName ?? sender) : sender, body, details, payload: chatGuid);
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


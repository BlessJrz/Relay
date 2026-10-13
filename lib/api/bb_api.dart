import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  final dynamic data;
  ApiException(this.status, this.message, [this.data]);

  bool get isAuth => status == 401;

  @override
  String toString() => message;
}

/// Thin client for the BlueBubbles Server REST API (v1).
/// Auth is the server password sent as the `guid` query parameter on every call.
class BBApi {
  String origin;
  String password;
  final http.Client _http = http.Client();

  BBApi({required String serverUrl, required this.password})
      : origin = sanitizeUrl(serverUrl);

  /// Turns whatever the user typed/scanned into `scheme://host[:port]`.
  static String sanitizeUrl(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      // LAN addresses are plain HTTP; tunnels are HTTPS.
      final looksLan = RegExp(r'^(\d{1,3}\.){3}\d{1,3}').hasMatch(s) ||
          s.startsWith('localhost');
      s = '${looksLan ? 'http' : 'https'}://$s';
    }
    final u = Uri.tryParse(s);
    if (u == null || u.host.isEmpty) return s;
    return u.hasPort && u.port != 80 && u.port != 443
        ? '${u.scheme}://${u.host}:${u.port}'
        : '${u.scheme}://${u.host}';
  }

  Map<String, String> get headers {
    final h = <String, String>{'Accept': 'application/json'};
    if (origin.contains('ngrok')) h['ngrok-skip-browser-warning'] = 'true';
    if (origin.contains('zrok')) h['skip_zrok_interstitial'] = 'true';
    return h;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse('$origin/api/v1$path');
    return base.replace(queryParameters: {
      ...base.queryParameters,
      ...?query,
      'guid': password,
    });
  }

  /// URL for an attachment's bytes (converted to JPEG/MP3 where needed).
  String attachmentUrl(String guid, {int? width}) {
    final q = <String, String>{};
    if (width != null) q['width'] = '$width';
    return _uri('/attachment/${Uri.encodeComponent(guid)}/download', q).toString();
  }

  Future<dynamic> _send(Future<http.Response> Function() call,
      {Duration timeout = const Duration(seconds: 20)}) async {
    http.Response res;
    try {
      res = await call().timeout(timeout);
      // Cloudflare quick tunnels sometimes 502 right after a restart; retry once.
      if (res.statusCode == 502 && origin.contains('trycloudflare')) {
        await Future.delayed(const Duration(milliseconds: 800));
        res = await call().timeout(timeout);
      }
    } on TimeoutException {
      throw ApiException(408, 'Your Mac didn’t answer in time.');
    } on SocketException {
      throw ApiException(0, 'Can’t reach your Mac. Check the server URL and that the Mac is awake.');
    } on HandshakeException {
      throw ApiException(0, 'Secure connection failed. Check the server URL.');
    } on http.ClientException catch (e) {
      throw ApiException(0, 'Connection problem: ${e.message}');
    }

    dynamic body;
    try {
      body = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      if (res.statusCode >= 400) {
        throw ApiException(res.statusCode,
            res.statusCode == 404 ? 'That address isn’t a BlueBubbles server.' : 'Server error (${res.statusCode}).');
      }
      throw ApiException(res.statusCode, 'Unexpected reply from the server.');
    }

    if (res.statusCode == 401) {
      throw ApiException(401, 'Wrong server password.');
    }
    if (res.statusCode >= 400) {
      final err = body is Map ? (body['error'] is Map ? body['error']['message'] : null) : null;
      final msg = err ?? (body is Map ? body['message'] : null) ?? 'Server error (${res.statusCode}).';
      throw ApiException(res.statusCode, msg.toString(), body is Map ? body['data'] : null);
    }
    return body is Map ? body['data'] : body;
  }

  Future<dynamic> get(String path, [Map<String, String>? q]) =>
      _send(() => _http.get(_uri(path, q), headers: headers));

  Future<dynamic> post(String path, [Object? json, Map<String, String>? q, Duration? timeout]) =>
      _send(
        () => _http.post(_uri(path, q),
            headers: {...headers, 'Content-Type': 'application/json'},
            body: jsonEncode(json ?? {})),
        timeout: timeout ?? const Duration(seconds: 20),
      );

  // ---------------- endpoints ----------------

  /// Returns round-trip time. Also proves the password is right (ping is auth-protected).
  Future<Duration> ping() async {
    final sw = Stopwatch()..start();
    await get('/ping');
    sw.stop();
    return sw.elapsed;
  }

  Future<ServerInfo> serverInfo() async =>
      ServerInfo.fromJson(Map<String, dynamic>.from(await get('/server/info') as Map));

  Future<List<Chat>> chats({int limit = 100, int offset = 0}) async {
    final data = await post('/chat/query', {
      'with': ['lastMessage', 'participants'],
      'offset': offset,
      'limit': limit,
      'sort': 'lastmessage',
    });
    return ((data as List?) ?? const [])
        .whereType<Map>()
        .map((c) => Chat.fromJson(Map<String, dynamic>.from(c)))
        .toList();
  }

  Future<Chat> chat(String guid) async {
    final data = await get('/chat/${Uri.encodeComponent(guid)}', {'with': 'participants,lastmessage'});
    return Chat.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<List<Message>> messages(String chatGuid, {int limit = 50, int? before}) async {
    final q = <String, String>{
      'with': 'attachment,handle',
      'limit': '$limit',
      'sort': 'DESC',
    };
    if (before != null) q['before'] = '$before';
    final data = await get('/chat/${Uri.encodeComponent(chatGuid)}/message', q);
    return ((data as List?) ?? const [])
        .whereType<Map>()
        .map((m) => Message.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  static String newTempGuid() {
    final r = Random.secure();
    final hex = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    return 'temp-$hex';
  }

  Future<Message> sendText(String chatGuid, String text,
      {required String tempGuid, bool privateApi = false, String? replyToGuid}) async {
    final body = <String, dynamic>{
      'chatGuid': chatGuid,
      'message': text,
      'tempGuid': tempGuid,
      'method': privateApi ? 'private-api' : 'apple-script',
    };
    if (replyToGuid != null && privateApi) {
      body['selectedMessageGuid'] = replyToGuid;
      body['partIndex'] = 0;
    }
    final data = await post('/message/text', body, null, const Duration(seconds: 90));
    return Message.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<Message> sendAttachment(String chatGuid, File file,
      {required String tempGuid, bool privateApi = false}) async {
    final name = file.path.split(Platform.pathSeparator).last;
    final data = await _send(() async {
      final req = http.MultipartRequest('POST', _uri('/message/attachment'))
        ..headers.addAll(headers)
        ..fields['chatGuid'] = chatGuid
        ..fields['tempGuid'] = tempGuid
        ..fields['name'] = name
        ..fields['method'] = privateApi ? 'private-api' : 'apple-script'
        ..files.add(await http.MultipartFile.fromPath('attachment', file.path, filename: name));
      final streamed = await _http.send(req);
      return http.Response.fromStream(streamed);
    }, timeout: const Duration(minutes: 3));
    return Message.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> react(String chatGuid, String messageGuid, String reaction) =>
      post('/message/react', {
        'chatGuid': chatGuid,
        'selectedMessageGuid': messageGuid,
        'reaction': reaction,
      });

  /// Requires the Private API on the Mac.
  Future<void> markRead(String chatGuid) => post('/chat/${Uri.encodeComponent(chatGuid)}/read');

  Future<Chat?> newChat(List<String> addresses, String message,
      {required String tempGuid, bool privateApi = false, String service = 'iMessage'}) async {
    final data = await post('/chat/new', {
      'addresses': addresses,
      'message': message,
      'tempGuid': tempGuid,
      'service': service,
      'method': privateApi ? 'private-api' : 'apple-script',
    }, null, const Duration(seconds: 90));
    if (data is Map) return Chat.fromJson(Map<String, dynamic>.from(data));
    return null;
  }

  Future<List<Contact>> contacts() async {
    final data = await get('/contact');
    return ((data as List?) ?? const [])
        .whereType<Map>()
        .map((c) => Contact.fromJson(Map<String, dynamic>.from(c)))
        .where((c) => c.name.isNotEmpty)
        .toList();
  }

  /// Contacts including their photos (base64), for profile pictures.
  Future<List<Map<String, dynamic>>> contactsWithPhotos() async {
    final data = await _send(() => _http.get(_uri('/contact', {'extraProperties': 'avatar'}), headers: headers), timeout: const Duration(seconds: 90));
    return ((data as List?) ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }

  /// A group chat's photo, or null if it has none (or can't be fetched).
  Future<List<int>?> chatIcon(String chatGuid) async {
    try {
      final r = await _http
          .get(_uri('/chat/${Uri.encodeComponent(chatGuid)}/icon'), headers: {...headers, 'Accept': '*/*'})
          .timeout(const Duration(seconds: 25));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) return null;
      if ((r.headers['content-type'] ?? '').contains('json')) return null;
      return r.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  /// The google-services.json the Mac was set up with (for push notifications).
  Future<Map<String, dynamic>?> fcmClient() async {
    try {
      final data = await get('/fcm/client');
      return data is Map ? Map<String, dynamic>.from(data) : null;
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  Future<void> registerDevice(String name, String token) =>
      post('/fcm/device', {'name': name, 'identifier': token});

  void close() => _http.close();
}

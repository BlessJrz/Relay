// Runs the real Store against a tiny fake BlueBubbles server to check that
// chats keep their place, older chats page in, messages appear without the
// live socket, and failures show an error instead of a blank screen.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:relay/api/bb_api.dart';
import 'package:relay/state/settings.dart';
import 'package:relay/state/store.dart';

Map<String, dynamic> msg(String guid, String text, int date, {bool me = false}) => {
      'guid': guid,
      'text': text,
      'isFromMe': me,
      'dateCreated': date,
      'handle': {'address': '+15551230000'},
      'attachments': [],
      'chats': [{'guid': 'iMessage;+;grp'}],
    };

void main() {
  late HttpServer server;
  late List<Map<String, dynamic>> chats;
  late List<Map<String, dynamic>> grpMessages;
  late List<String> sent;
  var failMessages = false;

  setUp(() async {
    failMessages = false;
    chats = [
      {'guid': 'iMessage;+;grp', 'style': 43, 'displayName': 'NTR KINGS', 'participants': [{'address': '+15551230000'}], 'lastMessage': msg('m1', 'hello', 5000)},
      for (var i = 0; i < 130; i++)
        {'guid': 'iMessage;-;+1555000${i.toString().padLeft(4, '0')}', 'style': 45, 'participants': [{'address': '+1555000${i.toString().padLeft(4, '0')}'}], 'lastMessage': msg('c$i', 'x', 4000 - i)},
    ];
    grpMessages = [msg('m1', 'hello', 5000)];
    sent = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final path = req.uri.path;
      Object data = [];
      var status = 200;
      if (path == '/api/v1/chat/query') {
        final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
        final off = body['offset'] as int, lim = body['limit'] as int;
        data = chats.skip(off).take(lim).toList();
      } else if (path == '/api/v1/message/text') {
        final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
        sent.add(body['message'] as String);
        data = {'guid': 'srv-${sent.length}', 'tempGuid': body['tempGuid'], 'text': body['message'], 'isFromMe': true, 'dateCreated': 9999};
      } else if (path.endsWith('/message')) {
        if (failMessages) {
          status = 500;
        } else {
          data = grpMessages.reversed.toList();
        }
      }
      req.response.statusCode = status;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'status': status, 'message': 'ok', 'data': data}));
      await req.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  Future<Store> makeStore() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final store = Store(await Settings.load());
    store.api = BBApi(serverUrl: 'http://127.0.0.1:${server.port}', password: 'pw');
    return store;
  }

  test('group chat stays first, paging brings in older chats without losing any', () async {
    final store = await makeStore();
    await store.refreshChats();
    expect(store.chats.first.guid, 'iMessage;+;grp');
    expect(store.chats.length, 120);
    expect(store.chatsHasMore, true);
    await store.loadMoreChats();
    expect(store.chats.length, 131);
    expect(store.chatsHasMore, false);
    expect(store.chats.map((c) => c.guid).toSet().length, 131, reason: 'no duplicates');
    expect(store.chats.first.guid, 'iMessage;+;grp');
  });

  test('a chat the Mac returns without a last message does not sink', () async {
    final store = await makeStore();
    chats[0].remove('lastMessage');
    await store.refreshChats();
    expect(store.chats.first.guid, 'iMessage;+;grp');
  });

  test('new messages appear without the live socket, and bump the chat', () async {
    final store = await makeStore();
    await store.refreshChats();
    await store.loadMessages('iMessage;+;grp');
    expect(store.messagesFor('iMessage;+;grp').length, 1);
    grpMessages.add(msg('m2', 'second', 9000));
    await store.syncMessages('iMessage;+;grp');
    final texts = store.messagesFor('iMessage;+;grp').map((m) => m.text).toList();
    expect(texts, ['second', 'hello']);
    expect(store.chatByGuid('iMessage;+;grp')!.lastMessage!.text, 'second');
  });

  test('a failed load reports an error instead of staying blank, and retry works', () async {
    final store = await makeStore();
    failMessages = true;
    await store.loadMessages('iMessage;+;grp');
    expect(store.messageError('iMessage;+;grp'), isNotNull);
    expect(store.isLoadingMessages('iMessage;+;grp'), false);
    failMessages = false;
    await store.loadMessages('iMessage;+;grp');
    expect(store.messageError('iMessage;+;grp'), isNull);
    expect(store.messagesFor('iMessage;+;grp').length, 1);
  });

  test('messages typed while the Mac is offline wait, then go out when it is back', () async {
    final store = await makeStore();
    await store.refreshChats();
    final chat = store.chatByGuid('iMessage;+;grp')!;
    store.conn = Conn.offline;
    await store.sendText(chat, 'see you at 8');
    expect(store.queuedCount, 1);
    expect(store.messagesFor(chat.guid).first.queued, true);
    expect(sent, isEmpty, reason: 'nothing is sent while offline');
    expect(store.settings.prefs.getString('send_queue'), contains('see you at 8'), reason: 'queue is kept across restarts');

    store.conn = Conn.online;
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    store.notifyListeners();
    for (var i = 0; i < 20 && store.queuedCount > 0; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    expect(sent, ['see you at 8']);
    expect(store.queuedCount, 0);
    final first = store.messagesFor(chat.guid).first;
    expect(first.guid, 'srv-1');
    expect(first.queued, false);
  });
}

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
  // connect() now starts the network watcher, which needs a binding; the test
  // binding fakes HTTP, so switch that off to reach the local fake Mac.
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late HttpServer server;
  late List<Map<String, dynamic>> chats;
  late List<Map<String, dynamic>> grpMessages;
  late List<String> sent;
  var failMessages = false;
  var macDown = false, slowMessages = false, failSend = false, failAttach = false;
  var attachments = 0, pings = 0;

  setUp(() async {
    failMessages = false;
    macDown = slowMessages = failSend = failAttach = false;
    attachments = pings = 0;
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
      if (path == '/api/v1/ping') pings++;
      if (macDown) {
        // Like Cloudflare when the Mac is away: nothing reaches it.
        await req.drain<void>();
        req.response.statusCode = 503;
        await req.response.close();
        return;
      }
      if (path == '/api/v1/chat/query') {
        final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
        final off = body['offset'] as int, lim = body['limit'] as int;
        data = chats.skip(off).take(lim).toList();
      } else if (path == '/api/v1/message/text') {
        final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
        if (failSend) {
          status = 500;
        } else {
          sent.add(body['message'] as String);
          data = {'guid': 'srv-${sent.length}', 'tempGuid': body['tempGuid'], 'text': body['message'], 'isFromMe': true, 'dateCreated': 9999};
        }
      } else if (path == '/api/v1/message/attachment') {
        await req.drain<void>();
        if (failAttach) {
          status = 500;
        } else {
          attachments++;
          data = {
            'guid': 'att-$attachments',
            'text': '',
            'isFromMe': true,
            'dateCreated': DateTime.now().millisecondsSinceEpoch,
            'attachments': [{'guid': 'file-$attachments', 'transferName': 'photo.jpg', 'mimeType': 'image/jpeg'}],
          };
        }
      } else if (path.endsWith('/message')) {
        if (slowMessages) await Future.delayed(const Duration(milliseconds: 300));
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
    macDown = true;
    await store.sendText(chat, 'see you at 8');
    expect(store.queuedCount, 1);
    expect(store.messagesFor(chat.guid).first.queued, true);
    expect(sent, isEmpty, reason: 'nothing is sent while offline');
    expect(store.settings.prefs.getString('send_queue'), contains('see you at 8'), reason: 'queue is kept across restarts');

    macDown = false;
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

  Future<void> waitFor(bool Function() done) async {
    for (var i = 0; i < 40 && !done(); i++) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  test('a queued message the Mac already got is not sent twice', () async {
    final store = await makeStore();
    await store.refreshChats();
    final chat = store.chatByGuid('iMessage;+;grp')!;
    macDown = true;
    await store.sendText(chat, 'on my way');
    expect(store.queuedCount, 1);
    // It reached the Mac after all; only the answer got lost.
    grpMessages.add(msg('srv-x', 'on my way', DateTime.now().millisecondsSinceEpoch, me: true));
    macDown = false;
    store.conn = Conn.online;
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    store.notifyListeners();
    await waitFor(() => store.queuedCount == 0);
    expect(store.queuedCount, 0);
    expect(sent, isEmpty, reason: 'not sent a second time');
    final mine = store.messagesFor(chat.guid).where((m) => m.text == 'on my way');
    expect(mine.map((m) => m.guid).toList(), ['srv-x']);
  });

  test('a message that arrives while the chat is loading is kept', () async {
    final store = await makeStore();
    await store.refreshChats();
    slowMessages = true;
    final loading = store.loadMessages('iMessage;+;grp');
    await Future.delayed(const Duration(milliseconds: 50));
    store.debugEvent('new-message', msg('live1', 'just now', 9000));
    await loading;
    expect(store.messagesFor('iMessage;+;grp').map((m) => m.text).toList(), ['just now', 'hello']);
  });

  test('a send that failed but went through does not leave a red copy', () async {
    final store = await makeStore();
    await store.refreshChats();
    final chat = store.chatByGuid('iMessage;+;grp')!;
    failSend = true;
    await store.sendText(chat, 'running late');
    expect(store.messagesFor(chat.guid).first.failed, true);
    grpMessages.add(msg('srv-late', 'running late', DateTime.now().millisecondsSinceEpoch, me: true));
    await store.syncMessages(chat.guid);
    final mine = store.messagesFor(chat.guid).where((m) => m.text == 'running late').toList();
    expect(mine.map((m) => m.guid).toList(), ['srv-late']);
    expect(mine.single.failed, false);
  });

  test('retrying a failed photo sends the photo again', () async {
    final store = await makeStore();
    await store.refreshChats();
    final chat = store.chatByGuid('iMessage;+;grp')!;
    final f = File('${Directory.systemTemp.path}${Platform.pathSeparator}relay_retry_test.jpg')..writeAsBytesSync([1, 2, 3]);
    failAttach = true;
    await store.sendFile(chat, f);
    final failed = store.messagesFor(chat.guid).first;
    expect(failed.failed, true);
    failAttach = false;
    await store.retry(chat, failed);
    expect(attachments, 1);
    expect(store.messagesFor(chat.guid).first.guid, 'att-1');
    expect(store.messagesFor(chat.guid).where((m) => m.failed), isEmpty);
    expect(store.localCopyOf('file-1'), f.path);
  });

  test('an older message never replaces the newer one in the list; edits update it', () async {
    final store = await makeStore();
    await store.refreshChats();
    const g = 'iMessage;+;grp';
    store.debugEvent('new-message', msg('late', 'from before', 1000));
    expect(store.chatByGuid(g)!.lastMessage!.text, 'hello');
    store.debugEvent('updated-message', msg('m1', 'hello (edited)', 5000));
    expect(store.chatByGuid(g)!.lastMessage!.text, 'hello (edited)');
    expect(store.chats.first.guid, g);
  });

  test('a Mac that is away leaves Relay offline, not stuck connecting, one try at a time', () async {
    final store = await makeStore();
    await store.settings.saveServer('127.0.0.1:${server.port}/', 'pw');
    expect(store.settings.serverUrl, 'http://127.0.0.1:${server.port}');
    macDown = true;
    final r = await Future.wait([store.connect(), store.connect()]);
    expect(store.conn, Conn.offline);
    expect(r.first, isNotNull);
    expect(pings, 1, reason: 'the second call waits for the first');
    store.dispose();
  });
}

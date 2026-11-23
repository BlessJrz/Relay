// Runs the real Store against a tiny fake BlueBubbles server to check that
// chats keep their place, older chats page in, messages appear without the
// live socket, and failures show an error instead of a blank screen.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:relay/api/bb_api.dart';
import 'package:relay/api/models.dart';
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
  final order = <String>[]; // what reached the Mac, in order
  // realDates: the Mac stamps what it sends with its own clock, like the real
  // one (off, sent texts come back dated 9999). slowAttach: uploads take a moment.
  var realDates = false, slowAttach = false;

  setUp(() async {
    failMessages = false;
    macDown = slowMessages = failSend = failAttach = false;
    realDates = slowAttach = false;
    attachments = pings = 0;
    order.clear();
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
          order.add('text:${body['message']}');
          if (realDates) await Future.delayed(const Duration(milliseconds: 5));
          data = {'guid': 'srv-${sent.length}', 'tempGuid': body['tempGuid'], 'text': body['message'], 'isFromMe': true, 'dateCreated': realDates ? DateTime.now().millisecondsSinceEpoch : 9999};
        }
      } else if (path == '/api/v1/message/attachment') {
        await req.drain<void>();
        if (failAttach) {
          status = 500;
        } else {
          attachments++;
          order.add('file');
          if (realDates) await Future.delayed(const Duration(milliseconds: 5));
          if (slowAttach) await Future.delayed(const Duration(milliseconds: 300));
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

  test('photos with a message: every bubble shows at once, photos go first, the text last', () async {
    final store = await makeStore();
    await store.refreshChats();
    final chat = store.chatByGuid('iMessage;+;grp')!;
    final tmp = Directory.systemTemp.path + Platform.pathSeparator;
    final a = File('${tmp}relay_bundle_a.jpg')..writeAsBytesSync([1, 2, 3]);
    final b = File('${tmp}relay_bundle_b.jpg')..writeAsBytesSync([4, 5, 6]);
    final sending = store.sendBundle(chat, [a, b], '  look at these  ');
    // Before the Mac has answered anything: all three are on screen, text newest.
    final shown = store.messagesFor(chat.guid).where((m) => m.sending).toList();
    expect(shown.length, 3);
    expect(shown.first.text, 'look at these');
    expect(shown[1].attachments.single.mimeType, 'local/${b.path}');
    expect(shown[2].attachments.single.mimeType, 'local/${a.path}');
    await sending;
    expect(order, ['file', 'file', 'text:look at these']);
    expect(store.messagesFor(chat.guid).where((m) => m.sending || m.failed), isEmpty);
    expect(store.messagesFor(chat.guid).where((m) => m.text == 'look at these').length, 1);
  });

  test('bubbles keep their order the whole time several photos upload', () async {
    realDates = true;
    final store = await makeStore();
    await store.refreshChats();
    final chat = store.chatByGuid('iMessage;+;grp')!;
    final tmp = Directory.systemTemp.path + Platform.pathSeparator;
    final a = File('${tmp}relay_order_a.jpg')..writeAsBytesSync([1, 2, 3]);
    final b = File('${tmp}relay_order_b.jpg')..writeAsBytesSync([4, 5, 6]);
    // Which of the three a bubble is, whether it's still the phone's copy or
    // already the Mac's.
    String slot(Message m) {
      if (m.text == 'caption') return 'T';
      final local = m.attachments.isEmpty ? null : m.attachments.single.mimeType;
      if (local == 'local/${a.path}' || m.guid == 'att-1') return 'A';
      if (local == 'local/${b.path}' || m.guid == 'att-2') return 'B';
      return '';
    }

    final seen = <String>{};
    void snap() => seen.add(store.messagesFor(chat.guid).map(slot).join());
    store.addListener(snap);
    await store.sendBundle(chat, [a, b], 'caption');
    store.removeListener(snap);
    snap();
    // Newest first, every time anything redrew: caption, second photo, first photo.
    expect(seen, {'TBA'});
    expect(order, ['file', 'file', 'text:caption']);
  });

  test('a caption waiting for its photo is not taken for an earlier identical message', () async {
    slowAttach = true;
    final store = await makeStore();
    await store.refreshChats();
    final chat = store.chatByGuid('iMessage;+;grp')!;
    final f = File('${Directory.systemTemp.path}${Platform.pathSeparator}relay_held.jpg')..writeAsBytesSync([1, 2, 3]);
    // "ok" already went out a moment ago (it's on the Mac)…
    grpMessages.add(msg('srv-earlier', 'ok', DateTime.now().millisecondsSinceEpoch, me: true));
    // …and now a photo with the same word. The chat reloads mid-upload.
    final sending = store.sendBundle(chat, [f], 'ok');
    await store.loadMessages(chat.guid);
    await sending;
    expect(order, ['file', 'text:ok'], reason: 'the caption must still be sent');
    expect(store.messagesFor(chat.guid).where((m) => m.text == 'ok').length, 2);
  });

  test('when the Mac stops answering mid-send, the rest is marked for a retry at once', () async {
    final store = await makeStore();
    await store.refreshChats();
    final chat = store.chatByGuid('iMessage;+;grp')!;
    final tmp = Directory.systemTemp.path + Platform.pathSeparator;
    final files = [for (var i = 0; i < 3; i++) File('${tmp}relay_away_$i.jpg')..writeAsBytesSync([i])];
    macDown = true;
    await store.sendBundle(chat, files, 'see these');
    final mine = store.messagesFor(chat.guid).where((m) => m.isFromMe).toList();
    expect(mine.where((m) => m.attachments.isNotEmpty && m.failed).length, 3, reason: 'all three photos offer a retry');
    // The text waits in the queue and goes by itself when the Mac is back.
    expect(mine.where((m) => m.text == 'see these' && m.queued).length, 1);
    expect(store.queuedCount, 1);
    expect(mine.where((m) => m.sending), isEmpty, reason: 'nothing left spinning');
  });

  test('a photo that fails does not hold its message back', () async {
    final store = await makeStore();
    await store.refreshChats();
    final chat = store.chatByGuid('iMessage;+;grp')!;
    final f = File('${Directory.systemTemp.path}${Platform.pathSeparator}relay_bundle_fail.jpg')..writeAsBytesSync([1, 2, 3]);
    failAttach = true;
    final why = await store.sendBundle(chat, [f], 'caption');
    expect(why, isNotNull, reason: 'the chat is told why the photo did not go');
    expect(order, ['text:caption']);
    final failed = store.messagesFor(chat.guid).where((m) => m.failed).toList();
    expect(failed.length, 1);
    expect(failed.single.attachments, isNotEmpty);
    // Just photos, no text: nothing extra is sent.
    failAttach = false;
    order.clear();
    expect(await store.sendBundle(chat, [f], '   '), isNull);
    expect(order, ['file']);
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

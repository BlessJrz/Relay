// Chat ordering must never lose or bury a chat, and the glass wallpaper
// presets must produce a full palette.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:relay/api/models.dart';
import 'package:relay/skins/glass.dart';
import 'package:relay/state/settings.dart';
import 'package:relay/state/store.dart';

Chat chat(String guid, int? date) => Chat.fromJson({
      'guid': guid,
      'style': 43,
      'displayName': guid,
      if (date != null) 'lastMessage': {'guid': 'm$guid', 'text': 'x', 'dateCreated': date},
    });

void main() {
  test('chats without a last message keep their place instead of sinking', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final store = Store(await Settings.load());
    final ordered = store.orderChatsForTest([chat('a', 300), chat('b', null), chat('c', 200), chat('d', 100)]);
    expect(ordered.map((c) => c.guid).toList(), ['a', 'b', 'c', 'd']);
    final reordered = store.orderChatsForTest([chat('old', 100), chat('new', 500)]);
    expect(reordered.map((c) => c.guid).toList(), ['new', 'old']);
  });

  test('every glass wallpaper gives three blob colours in both modes', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final skin = GlassSkin();
    for (final dark in [false, true]) {
      for (var i = 0; i <= glassCustomIndex; i++) {
        final p = glassWithBackground(skin.palette(dark, 0), i, 200, 300);
        expect(p.blobs.length, 3, reason: 'wallpaper $i dark=$dark');
      }
    }
  });
}

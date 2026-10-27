// Chat ordering must never lose or bury a chat, and every design's own
// bubbles must be readable.
import 'dart:math' as math;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:relay/api/models.dart';
import 'package:relay/state/settings.dart';
import 'package:relay/state/store.dart';
import 'package:relay/ui/kit/scope.dart';

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

  test('every design has readable bubbles in both modes', () {
    for (final skin in skins.values) {
      for (final dark in [false, true]) {
        for (var i = 0; i < skin.accents.length; i++) {
          final p = skin.palette(dark, i);
          final bubble = skin.outgoingBubble(p), ink = skin.outgoingText(p);
          final l1 = bubble.computeLuminance(), l2 = ink.computeLuminance();
          final ratio = (math.max(l1, l2) + .05) / (math.min(l1, l2) + .05);
          expect(ratio, greaterThan(4.0), reason: '${skin.name} dark=$dark accent=$i');
        }
      }
    }
  });
}

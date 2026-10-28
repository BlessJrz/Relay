import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../skins/messengers.dart';
import '../../skins/minimal.dart';
import '../../skins/skin.dart';
import '../../state/settings.dart';
import '../../state/store.dart';

final skins = <DesignId, Skin>{
  DesignId.pinned: PinnedSkin(),
  DesignId.material: MaterialSkin(),
  DesignId.folders: FoldersSkin(),
  DesignId.minimal: MinimalSkin(),
};

/// Gives every widget the current design, colours and app state.
class AppScope extends InheritedWidget {
  final Settings settings;
  final Store store;
  final Skin skin;
  final Palette p;

  const AppScope({
    super.key,
    required this.settings,
    required this.store,
    required this.skin,
    required this.p,
    required super.child,
  });

  static AppScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  /// Whether to run ambient animations.
  bool get ambient => settings.animations && !settings.reduceMotion;

  /// Whether to animate interactions at all.
  bool get motion => settings.animations;

  Duration d(Duration x) => motion ? (settings.reduceMotion ? x ~/ 2 : x) : Duration.zero;

  @override
  // Only rebuilt when Settings change (design, mode, accent, motion), so always notify.
  bool updateShouldNotify(AppScope old) => true;
}

extension ScopeX on BuildContext {
  AppScope get sc => AppScope.of(this);
  Skin get skin => AppScope.of(this).skin;
  Palette get pal => AppScope.of(this).p;
  Store get store => AppScope.of(this).store;
  Settings get settings => AppScope.of(this).settings;
}

/// Picks the palette for the current design/mode/accent.
Palette paletteFor(Settings s, Brightness platform) {
  final skin = skins[s.design]!;
  final dark = switch (s.mode) {
    ThemeModeChoice.dark => true,
    ThemeModeChoice.light => false,
    ThemeModeChoice.system => platform == Brightness.dark,
  };
  final p = skin.palette(dark, s.accentFor(s.design));
  final h = s.highlight;
  return h == null ? p : p.copyWith(highlight: highlightFor(h, dark, against: p.surface));
}

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (math.max(x, y) + .05) / (math.min(x, y) + .05);
}

/// Your highlight colour, nudged just enough to stay readable as text: darker
/// on light backgrounds, lighter on dark ones (keeps its hue).
Color highlightFor(Color c, bool dark, {Color? against}) {
  final bg = against ?? (dark ? const Color(0xFF121318) : const Color(0xFFFFFFFF));
  final toward = dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
  var out = c;
  for (var t = .08; _contrast(out, bg) < 3.6 && t <= .8; t += .08) {
    out = Color.lerp(c, toward, t)!;
  }
  return out;
}

/// Colours offered for the highlight (the design's own red is "Default").
const highlightChoices = <Color>[
  Color(0xFFFF5A52), // red
  Color(0xFFFF8A3D), // orange
  Color(0xFFFFC53D), // gold
  Color(0xFF3DDC84), // green
  Color(0xFF2EC4B6), // teal
  Color(0xFF4D8DFF), // blue
  Color(0xFF8E6CFF), // purple
  Color(0xFFFF5CA8), // pink
  Color(0xFFFFFFFF), // white
];

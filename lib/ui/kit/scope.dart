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
  return h == null ? p : p.copyWith(highlight: highlightFor(h, dark));
}

/// Your highlight colour, nudged so it stays readable: very light picks get
/// darker on a white background, very dark picks get lighter on black.
Color highlightFor(Color c, bool dark) {
  final l = c.computeLuminance();
  if (!dark && l > .45) return Color.lerp(c, const Color(0xFF000000), .35)!;
  if (dark && l < .06) return Color.lerp(c, const Color(0xFFFFFFFF), .35)!;
  return c;
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

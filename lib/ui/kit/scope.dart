import 'package:flutter/widgets.dart';

import '../../skins/glass.dart';
import '../../skins/luxe.dart';
import '../../skins/minimal.dart';
import '../../skins/skin.dart';
import '../../skins/soft.dart';
import '../../state/settings.dart';
import '../../state/store.dart';

final skins = <DesignId, Skin>{
  DesignId.glass: GlassSkin(),
  DesignId.soft: SoftSkin(),
  DesignId.luxe: LuxeSkin(),
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

  /// Whether to run ambient animations (blobs, particles, scan line).
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
  final pal = skin.palette(dark, s.accentFor(s.design));
  return s.design == DesignId.glass ? glassWithBackground(pal, s.glassBg, s.glassHueA, s.glassHueB) : pal;
}

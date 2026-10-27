import 'package:flutter/widgets.dart';

import '../state/settings.dart';

Color withA(Color c, double a) => c.withOpacity(a.clamp(0.0, 1.0));

/// Colours for one design in one mode with one accent.
class Palette {
  final bool dark;
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color inset;
  final Color line;
  final Color lineStrong;
  final Color text;
  final Color text2;
  final Color text3;
  final Color onAccent;
  final Color accent;
  final Color accent2;
  final Color tint;
  final Color glow;
  final Color success;
  final Color warning;
  final Color danger;
  final List<Color> avatars;

  const Palette({
    required this.dark,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.inset,
    required this.line,
    required this.lineStrong,
    required this.text,
    required this.text2,
    required this.text3,
    required this.onAccent,
    required this.accent,
    required this.accent2,
    required this.tint,
    required this.glow,
    required this.success,
    required this.warning,
    required this.danger,
    this.avatars = const [],
  });

  Palette copyWith({Color? bg}) => Palette(
        dark: dark,
        bg: bg ?? this.bg,
        surface: surface,
        surface2: surface2,
        inset: inset,
        line: line,
        lineStrong: lineStrong,
        text: text,
        text2: text2,
        text3: text3,
        onAccent: onAccent,
        accent: accent,
        accent2: accent2,
        tint: tint,
        glow: glow,
        success: success,
        warning: warning,
        danger: danger,
        avatars: avatars,
      );

  Color status(String s) => switch (s) {
        'ok' => success,
        'warn' => warning,
        'bad' => danger,
        _ => text3,
      };
}

class AccentChoice {
  final String name;
  final Color light;
  final Color dark;
  const AccentChoice(this.name, this.light, this.dark);
}

enum Surf { card, control, pill, bubbleIn, bubbleOut, tile }

/// How the screens are arranged (not just coloured).
/// standard: floating tab bar. pinned: big title + pinned chats, no tab bar.
/// material: one rounded sheet + "Start chat" button. folders: menu + folder tabs.
enum AppLayout { standard, pinned, material, folders }

/// A design language. Every screen draws through this, so switching designs in
/// Settings re-skins the whole app without touching any screen code.
abstract class Skin {
  DesignId get id;
  String get name => id.label;
  List<AccentChoice> get accents;
  Palette palette(bool dark, int accent);

  /// Icon stroke cap ("round" or "square") and weight.
  String get iconCap => 'round';
  double get iconStroke => 2;

  AppLayout get layout => AppLayout.standard;

  /// Colour of your own message bubbles and the text on them.
  Color outgoingBubble(Palette p) => p.accent;
  Color outgoingText(Palette p) => p.onAccent;

  /// Unread counts.
  Color badge(Palette p) => p.accent;
  Color onBadge(Palette p) => p.onAccent;

  // Typography
  TextStyle display(Palette p);
  TextStyle title(Palette p);
  TextStyle headline(Palette p);
  TextStyle body(Palette p);
  TextStyle callout(Palette p);
  TextStyle caption(Palette p);
  TextStyle mono(Palette p);
  TextStyle label(Palette p); // small section labels
  String sectionLabel(String s) => s.toUpperCase();

  double radius(Surf s);

  /// Full-screen backdrop (animated blobs, sculpted plain, HUD grid…).
  Widget background(Palette p, {required bool animate, required Widget child});

  /// Main raised container.
  Widget surface(Palette p, {required Widget child, EdgeInsetsGeometry? padding, bool strong = false, double? radius, bool reduceEffects = false});

  /// Recessed area (inputs, wells, tracks).
  Widget well(Palette p, {required Widget child, EdgeInsetsGeometry? padding, double? radius, bool focused = false});

  /// Button face. [pressed] animates between the two states.
  Widget buttonFace(Palette p, {required Widget child, required bool primary, required bool pressed, double? radius});

  /// Selected item in nav bars, segmented controls and menus.
  Widget selectedFace(Palette p, {required Widget child, required bool selected, double? radius});

  Widget toggle(Palette p, bool on);

  Widget sliderTrack(Palette p, double value, {required bool dragging});

  Widget chip(Palette p, {required String label, required Color color});

  Widget bubble(Palette p, {required Widget child, required bool outgoing, bool tail = true});

  /// [image] is a profile photo; when it's null (or can't load) initials are shown.
  Widget avatar(Palette p, String initials, double size, int seed, {bool group = false, ImageProvider? image});

  /// Backdrop for a long, scrolling card (e.g. the chat list). Unlike [surface]
  /// it is a plain decoration, so the list inside can build lazily.
  Decoration listDecoration(Palette p) => BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(radius(Surf.card)));

  /// Accent tile used for logos and important icons.
  Widget accentTile(Palette p, {required Widget child, required double size});

  /// Transition for pushed screens, dialogs and the design switch.
  Widget transition(Animation<double> a, Widget child);

  Duration get pressDuration => const Duration(milliseconds: 140);
  Duration get moveDuration => const Duration(milliseconds: 280);
  Curve get curve => Curves.easeOutCubic;
}

/// A profile photo that fades in over whatever is underneath, and quietly shows
/// nothing if it can't be decoded (so initials stay visible).
Widget photoFill(ImageProvider image, double size) => SizedBox(
      width: size,
      height: size,
      child: Image(
        image: image,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
          opacity: sync || frame != null ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: child,
        ),
      ),
    );

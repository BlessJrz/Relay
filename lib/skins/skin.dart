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
  final Color lightShadow;
  final Color darkShadow;
  final List<Color> blobs;
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
    this.lightShadow = const Color(0x00000000),
    this.darkShadow = const Color(0x00000000),
    this.blobs = const [],
    this.avatars = const [],
  });

  Palette copyWith({Color? bg, List<Color>? blobs}) => Palette(
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
        lightShadow: lightShadow,
        darkShadow: darkShadow,
        blobs: blobs ?? this.blobs,
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

  bool get upperHeadings => false;

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
  Widget surface(Palette p, {required Widget child, EdgeInsetsGeometry? padding, bool strong = false, double? radius, bool reduceEffects = false, bool brackets = true});

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

/// Paints soft inner shadows (CSS `box-shadow: inset`) for neumorphic wells.
class InsetShadowPainter extends CustomPainter {
  final double radius;
  final Color fill;
  final Color dark;
  final Color light;
  final double offset;
  final double blur;

  InsetShadowPainter({required this.radius, required this.fill, required this.dark, required this.light, this.offset = 3, this.blur = 6});

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius.clamp(0, size.shortestSide / 2)));
    canvas.drawRRect(r, Paint()..color = fill);
    canvas.save();
    canvas.clipRRect(r);
    void shadow(Color c, Offset o) {
      final outer = Path()..addRect((Offset.zero & size).inflate(blur * 3 + offset.abs() * 2));
      final hole = Path()..addRRect(r.shift(o));
      final p = Path.combine(PathOperation.difference, outer, hole);
      canvas.drawPath(p, Paint()
        ..color = c
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur / 2));
    }

    shadow(dark, Offset(offset, offset));
    shadow(light, Offset(-offset, -offset));
    canvas.restore();
  }

  @override
  bool shouldRepaint(InsetShadowPainter o) =>
      o.fill != fill || o.dark != dark || o.light != light || o.offset != offset || o.radius != radius;
}

/// Corner brackets for the HUD design.
class BracketPainter extends CustomPainter {
  final Color color;
  final double len;
  final double width;
  final bool all;
  BracketPainter(this.color, {this.len = 9, this.width = 2, this.all = false});

  @override
  void paint(Canvas canvas, Size s) {
    final glow = Paint()
      ..color = withA(color, .55)
      ..strokeWidth = width + 3
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final line = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    final paths = <Path>[
      Path()
        ..moveTo(0, len)
        ..lineTo(0, 0)
        ..lineTo(len, 0),
      Path()
        ..moveTo(s.width - len, s.height)
        ..lineTo(s.width, s.height)
        ..lineTo(s.width, s.height - len),
      if (all) ...[
        Path()
          ..moveTo(s.width - len, 0)
          ..lineTo(s.width, 0)
          ..lineTo(s.width, len),
        Path()
          ..moveTo(0, s.height - len)
          ..lineTo(0, s.height)
          ..lineTo(len, s.height),
      ],
    ];
    for (final p in paths) {
      canvas.drawPath(p, glow);
      canvas.drawPath(p, line);
    }
  }

  @override
  bool shouldRepaint(BracketPainter o) => o.color != color || o.all != all;
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

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';

import '../state/settings.dart';
import 'skin.dart';

/// Design 1 — Liquid Glass: frosted translucent panels over a drifting wallpaper.
class GlassSkin extends Skin {
  @override
  DesignId get id => DesignId.glass;

  @override
  List<AccentChoice> get accents => const [
        AccentChoice('Blue', Color(0xFF3B7BFF), Color(0xFF6EA8FF)),
        AccentChoice('Violet', Color(0xFF8A5CFF), Color(0xFFB07CFF)),
        AccentChoice('Pink', Color(0xFFFF4D9A), Color(0xFFFF7AB6)),
        AccentChoice('Mint', Color(0xFF12B981), Color(0xFF5EE6A8)),
        AccentChoice('Amber', Color(0xFFF59E0B), Color(0xFFFFC470)),
      ];

  @override
  Palette palette(bool dark, int accent) {
    final a = accents[accent.clamp(0, accents.length - 1)];
    final ac = dark ? a.dark : a.light;
    return dark
        ? Palette(
            dark: true,
            bg: const Color(0xFF0A0A1C),
            surface: const Color(0x17FFFFFF),
            surface2: const Color(0x29FFFFFF),
            inset: const Color(0x47000000),
            line: const Color(0x47FFFFFF),
            lineStrong: const Color(0x80FFFFFF),
            text: const Color(0xFFFFFFFF),
            text2: const Color(0xADEBEBF5),
            text3: const Color(0x6BEBEBF5),
            onAccent: const Color(0xFF041230),
            accent: ac,
            accent2: const Color(0xFFB07CFF),
            tint: withA(ac, .22),
            glow: withA(ac, .5),
            success: const Color(0xFF5EE6A8),
            warning: const Color(0xFFFFC470),
            danger: const Color(0xFFFF6B7A),
            darkShadow: const Color(0x8C000000),
            lightShadow: const Color(0x66FFFFFF),
            blobs: const [Color(0xFF3B5BFF), Color(0xFF9B3DFF), Color(0xFF00B8D9)],
            avatars: const [Color(0xFF6EA8FF), Color(0xFFFF8CA0), Color(0xFF4DE6B3), Color(0xFFFFB35A), Color(0xFF8C8CFF), Color(0xFFF27FE6)],
          )
        : Palette(
            dark: false,
            bg: const Color(0xFFEAF0FF),
            surface: const Color(0x85FFFFFF),
            surface2: const Color(0xB8FFFFFF),
            inset: const Color(0x0F0E1330),
            line: const Color(0xCCFFFFFF),
            lineStrong: const Color(0xFFFFFFFF),
            text: const Color(0xFF0E1330),
            text2: const Color(0x9E0E1330),
            text3: const Color(0x660E1330),
            onAccent: const Color(0xFFFFFFFF),
            accent: ac,
            accent2: const Color(0xFF8A5CFF),
            tint: withA(ac, .16),
            glow: withA(ac, .42),
            success: const Color(0xFF12B981),
            warning: const Color(0xFFF59E0B),
            danger: const Color(0xFFEF4455),
            darkShadow: const Color(0x261B2A66),
            lightShadow: const Color(0xF2FFFFFF),
            blobs: const [Color(0xFF7FB2FF), Color(0xFFFFB6D9), Color(0xFFFFD9A8)],
            avatars: const [Color(0xFF6EA8FF), Color(0xFFFF8CA0), Color(0xFF4DE6B3), Color(0xFFFFB35A), Color(0xFF8C8CFF), Color(0xFFF27FE6)],
          );
  }

  TextStyle _t(Palette p, double size, FontWeight w, {double ls = 0, double? h, Color? c}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, letterSpacing: ls, height: h, color: c ?? p.text);

  @override
  TextStyle display(Palette p) => _t(p, 32, FontWeight.w700, ls: -.4, h: 1.2);
  @override
  TextStyle title(Palette p) => _t(p, 22, FontWeight.w600, ls: -.2, h: 1.25);
  @override
  TextStyle headline(Palette p) => _t(p, 16.5, FontWeight.w600, h: 1.3);
  @override
  TextStyle body(Palette p) => _t(p, 15, FontWeight.w400, h: 1.4);
  @override
  TextStyle callout(Palette p) => _t(p, 13, FontWeight.w500, h: 1.35, c: p.text2);
  @override
  TextStyle caption(Palette p) => _t(p, 11, FontWeight.w500, ls: .2, c: p.text3);
  @override
  TextStyle mono(Palette p) => GoogleFonts.jetBrainsMono(fontSize: 12.5, color: p.text2);
  @override
  TextStyle label(Palette p) => _t(p, 11, FontWeight.w600, ls: .9, c: p.text3);

  @override
  double radius(Surf s) => switch (s) {
        Surf.card => 30,
        Surf.control => 999,
        Surf.pill => 999,
        Surf.tile => 16,
        _ => 22,
      };

  @override
  Widget background(Palette p, {required bool animate, required Widget child}) =>
      _GlassBackdrop(p: p, animate: animate, child: child);

  Gradient _edge(Palette p) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [withA(const Color(0xFFFFFFFF), p.dark ? .30 : .8), withA(const Color(0xFFFFFFFF), .04), withA(const Color(0xFFFFFFFF), p.dark ? .18 : .45)],
        stops: const [0, .5, 1],
      );

  /// The glass sheet: blur + translucent fill + gradient rim + top sheen.
  Widget _glass(Palette p, {required Widget child, required double radius, Color? fill, bool shadow = true, bool blur = true, EdgeInsetsGeometry? padding, double sigma = 22}) {
    final br = BorderRadius.circular(radius);
    Widget inner = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: br,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [withA(const Color(0xFFFFFFFF), p.dark ? .08 : .30), withA(const Color(0xFFFFFFFF), 0)],
          stops: const [0, .55],
        ),
      ),
      foregroundDecoration: _RimDecoration(radius: radius, gradient: _edge(p)),
      child: child,
    );
    // The gradient above replaces `color`, so paint the fill underneath it.
    inner = DecoratedBox(decoration: BoxDecoration(borderRadius: br, color: fill ?? p.surface), child: inner);
    if (blur) {
      inner = ClipRRect(
        borderRadius: br,
        child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma), child: inner),
      );
    }
    if (!shadow) return inner;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: br, boxShadow: [BoxShadow(color: p.darkShadow, blurRadius: 30, spreadRadius: -6, offset: const Offset(0, 14))]),
      child: inner,
    );
  }

  @override
  Widget surface(Palette p, {required Widget child, EdgeInsetsGeometry? padding, bool strong = false, double? radius, bool reduceEffects = false, bool brackets = true}) =>
      _glass(p,
          child: child,
          padding: padding,
          radius: radius ?? this.radius(Surf.card),
          fill: strong ? p.surface2 : (reduceEffects ? withA(p.bg, p.dark ? .82 : .78) : p.surface),
          blur: !reduceEffects,
          sigma: strong ? 32 : 22);

  @override
  Widget well(Palette p, {required Widget child, EdgeInsetsGeometry? padding, double? radius, bool focused = false}) {
    final r = radius ?? 16;
    return AnimatedContainer(
      duration: moveDuration,
      curve: curve,
      padding: padding,
      decoration: BoxDecoration(
        color: p.inset,
        borderRadius: BorderRadius.circular(r),
        border: Border.all(color: focused ? p.accent : withA(p.line, .6), width: focused ? 1.5 : 1),
        boxShadow: focused ? [BoxShadow(color: p.glow, blurRadius: 14)] : const [],
      ),
      child: child,
    );
  }

  @override
  Widget buttonFace(Palette p, {required Widget child, required bool primary, required bool pressed, double? radius}) {
    final r = radius ?? 999;
    if (primary) {
      return AnimatedContainer(
        duration: pressDuration,
        curve: curve,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(r),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(p.accent, const Color(0xFFFFFFFF), pressed ? .05 : .22)!, p.accent],
          ),
          boxShadow: [BoxShadow(color: p.glow, blurRadius: pressed ? 8 : 22, offset: Offset(0, pressed ? 2 : 9), spreadRadius: -5)],
          border: Border.all(color: withA(const Color(0xFFFFFFFF), .35)),
        ),
        child: child,
      );
    }
    return AnimatedOpacity(
      duration: pressDuration,
      opacity: pressed ? .85 : 1,
      child: _glass(p, child: child, radius: r, fill: pressed ? p.surface2 : p.surface, shadow: !pressed, sigma: 18),
    );
  }

  @override
  Widget selectedFace(Palette p, {required Widget child, required bool selected, double? radius}) => AnimatedContainer(
        duration: moveDuration,
        curve: Curves.easeOutBack,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius ?? 999),
          color: selected ? p.tint : withA(p.tint, 0),
          border: Border.all(color: selected ? withA(p.line, .9) : withA(p.line, 0)),
          // Same-length shadow lists so easeOutBack's overshoot never scales a
          // shadow by a negative factor (negative blurRadius asserts in debug).
          boxShadow: [BoxShadow(color: withA(p.glow, selected ? .35 : 0), blurRadius: 14, spreadRadius: -6)],
        ),
        child: child,
      );

  @override
  Widget toggle(Palette p, bool on) => AnimatedContainer(
        duration: moveDuration,
        curve: curve,
        width: 54,
        height: 32,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          color: on ? p.accent : p.inset,
          border: Border.all(color: on ? withA(const Color(0xFFFFFFFF), .3) : p.line),
          boxShadow: on ? [BoxShadow(color: p.glow, blurRadius: 14, spreadRadius: -4)] : const [],
        ),
        child: AnimatedAlign(
          duration: moveDuration,
          curve: Curves.easeOutBack,
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 26,
            height: 26,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFFFFFFF),
              boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 3))],
            ),
          ),
        ),
      );

  @override
  Widget sliderTrack(Palette p, double v, {required bool dragging}) => LayoutBuilder(builder: (c, k) {
        final w = k.maxWidth;
        final knob = dragging ? 30.0 : 26.0;
        final x = (w - knob) * v;
        return SizedBox(
          height: 32,
          child: Stack(alignment: Alignment.centerLeft, children: [
            Container(height: 8, decoration: BoxDecoration(color: p.inset, borderRadius: BorderRadius.circular(9), border: Border.all(color: withA(p.line, .7)))),
            Container(width: x + knob / 2, height: 8, decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(9), boxShadow: [BoxShadow(color: p.glow, blurRadius: 10)])),
            Positioned(
              left: x,
              child: AnimatedContainer(
                duration: pressDuration,
                width: knob,
                height: knob,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFFFFFF), boxShadow: [BoxShadow(color: Color(0x47000000), blurRadius: 8, offset: Offset(0, 3))]),
              ),
            ),
          ]),
        );
      });

  @override
  Widget chip(Palette p, {required String label, required Color color}) => _glass(
        p,
        radius: 99,
        shadow: false,
        sigma: 14,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color, boxShadow: [BoxShadow(color: color, blurRadius: 8)])),
          const SizedBox(width: 7),
          Text(label, style: callout(p).copyWith(color: p.text)),
        ]),
      );

  @override
  Widget bubble(Palette p, {required Widget child, required bool outgoing, bool tail = true}) {
    final r = BorderRadius.only(
      topLeft: const Radius.circular(22),
      topRight: const Radius.circular(22),
      bottomLeft: Radius.circular(!outgoing && tail ? 6 : 22),
      bottomRight: Radius.circular(outgoing && tail ? 6 : 22),
    );
    if (outgoing) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: r,
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [p.accent, Color.lerp(p.accent, p.accent2, .55)!]),
          boxShadow: [BoxShadow(color: withA(p.glow, .6), blurRadius: 14, spreadRadius: -6, offset: const Offset(0, 6))],
        ),
        child: child,
      );
    }
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          decoration: BoxDecoration(borderRadius: r, color: p.surface2, border: Border.all(color: withA(p.line, .7))),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget avatar(Palette p, String initials, double size, int seed, {bool group = false}) {
    final a = p.avatars[seed % p.avatars.length];
    final b = p.avatars[(seed + 2) % p.avatars.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [a, b]),
        border: Border.all(color: withA(const Color(0xFFFFFFFF), .55), width: 1.5),
      ),
      child: Text(initials, style: GoogleFonts.inter(fontSize: size * .33, fontWeight: FontWeight.w600, color: const Color(0xFFFFFFFF))),
    );
  }

  @override
  Widget accentTile(Palette p, {required Widget child, required double size}) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * .32),
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.lerp(p.accent, const Color(0xFFFFFFFF), .2)!, p.accent]),
          boxShadow: [BoxShadow(color: p.glow, blurRadius: 18, spreadRadius: -4, offset: const Offset(0, 8))],
          border: Border.all(color: withA(const Color(0xFFFFFFFF), .35)),
        ),
        child: child,
      );

  @override
  Widget transition(Animation<double> a, Widget child) {
    final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return FadeTransition(
      opacity: c,
      child: ScaleTransition(scale: Tween(begin: .96, end: 1.0).animate(c), child: child),
    );
  }

  @override
  Duration get moveDuration => const Duration(milliseconds: 320);
}

class _RimDecoration extends Decoration {
  final double radius;
  final Gradient gradient;
  const _RimDecoration({required this.radius, required this.gradient});
  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _RimPainter(this);
}

class _RimPainter extends BoxPainter {
  final _RimDecoration d;
  _RimPainter(this.d);
  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration cfg) {
    final size = cfg.size!;
    final rect = offset & size;
    final r = RRect.fromRectAndRadius(rect.deflate(.5), Radius.circular(math.min(d.radius, size.shortestSide / 2)));
    canvas.drawRRect(r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = d.gradient.createShader(rect));
  }
}

class _GlassBackdrop extends StatefulWidget {
  final Palette p;
  final bool animate;
  final Widget child;
  const _GlassBackdrop({required this.p, required this.animate, required this.child});
  @override
  State<_GlassBackdrop> createState() => _GlassBackdropState();
}

class _GlassBackdropState extends State<_GlassBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 18));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant _GlassBackdrop old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_c.isAnimating) _c.repeat();
    if (!widget.animate && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    return Stack(fit: StackFit.expand, children: [
      ColoredBox(color: p.bg),
      RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(painter: _BlobPainter(p.blobs, _c.value, p.dark)),
        ),
      ),
      widget.child,
    ]);
  }
}

/// Soft colour blobs drawn with radial gradients (cheap — no blur filter needed).
class _BlobPainter extends CustomPainter {
  final List<Color> colors;
  final double t;
  final bool dark;
  _BlobPainter(this.colors, this.t, this.dark);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final a = t * 2 * math.pi;
    final spots = [
      Offset(w * (.15 + .08 * math.sin(a)), h * (.18 + .05 * math.cos(a))),
      Offset(w * (.85 + .07 * math.cos(a * 1.3)), h * (.48 + .06 * math.sin(a * 1.1))),
      Offset(w * (.25 + .08 * math.sin(a * .8 + 1)), h * (.88 + .04 * math.cos(a * .9))),
    ];
    final radius = math.max(w, h) * .62;
    for (var i = 0; i < 3 && i < colors.length; i++) {
      final c = colors[i];
      final paint = Paint()
        ..shader = RadialGradient(colors: [withA(c, dark ? .9 : .85), withA(c, 0)]).createShader(Rect.fromCircle(center: spots[i], radius: radius));
      canvas.drawCircle(spots[i], radius, paint);
    }
  }

  @override
  bool shouldRepaint(_BlobPainter o) => o.t != t || o.colors != colors;
}

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';

import '../state/settings.dart';
import 'skin.dart';

/// Design 3 — Cyberpunk HUD: neon outlines on black, cut corners, brackets,
/// grid + particle backdrop and a sweeping scan line.
class HudSkin extends Skin {
  @override
  DesignId get id => DesignId.hud;

  @override
  List<AccentChoice> get accents => const [
        AccentChoice('Cyan', Color(0xFF00899A), Color(0xFF00F0FF)),
        AccentChoice('Electric Blue', Color(0xFF1B45C9), Color(0xFF2F6BFF)),
        AccentChoice('Purple', Color(0xFF7A2BD1), Color(0xFFA855FF)),
        AccentChoice('Magenta', Color(0xFFB3128F), Color(0xFFFF2BD6)),
      ];

  static const _alt = [Color(0xFF9A6BFF), Color(0xFF00F0FF), Color(0xFFFF2BD6), Color(0xFF00F0FF)];

  @override
  Palette palette(bool dark, int accent) {
    final i = accent.clamp(0, accents.length - 1);
    final a = accents[i];
    final ac = dark ? a.dark : a.light;
    return dark
        ? Palette(
            dark: true,
            bg: const Color(0xFF04060B),
            surface: const Color(0xD10A1019),
            surface2: const Color(0xFF101A27),
            inset: const Color(0xFF05080E),
            line: const Color(0xFF25364B),
            lineStrong: const Color(0xFF3E5775),
            text: const Color(0xFFE6F4FF),
            text2: const Color(0xFF8CA3B8),
            text3: const Color(0xFF5A6E83),
            onAccent: const Color(0xFF021018),
            accent: ac,
            accent2: _alt[i],
            tint: withA(ac, .14),
            glow: withA(ac, .6),
            success: const Color(0xFF3DFFA2),
            warning: const Color(0xFFFFC857),
            danger: const Color(0xFFFF4D6D),
          )
        : Palette(
            dark: false,
            bg: const Color(0xFFE6EDF5),
            surface: const Color(0xD1FFFFFF),
            surface2: const Color(0xFFF1F6FB),
            inset: const Color(0xFFDCE5EF),
            line: const Color(0xFF9FB2C7),
            lineStrong: const Color(0xFF6F86A0),
            text: const Color(0xFF0B1624),
            text2: const Color(0xFF44566B),
            text3: const Color(0xFF7A8DA2),
            onAccent: const Color(0xFFFFFFFF),
            accent: ac,
            accent2: _alt[i],
            tint: withA(ac, .10),
            glow: withA(a.dark, .25),
            success: const Color(0xFF00A86B),
            warning: const Color(0xFFC98400),
            danger: const Color(0xFFD9234A),
          );
  }

  @override
  String get iconCap => 'square';
  @override
  double get iconStroke => 1.75;
  @override
  bool get upperHeadings => true;

  @override
  TextStyle display(Palette p) => GoogleFonts.orbitron(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: 1, height: 1.2, color: p.text);
  @override
  TextStyle title(Palette p) => GoogleFonts.orbitron(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: .6, height: 1.3, color: p.text);
  @override
  TextStyle headline(Palette p) => GoogleFonts.chakraPetch(fontSize: 16.5, fontWeight: FontWeight.w600, letterSpacing: .2, height: 1.3, color: p.text);
  @override
  TextStyle body(Palette p) => GoogleFonts.chakraPetch(fontSize: 15, fontWeight: FontWeight.w400, letterSpacing: .2, height: 1.4, color: p.text);
  @override
  TextStyle callout(Palette p) => GoogleFonts.chakraPetch(fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: .3, height: 1.35, color: p.text2);
  @override
  TextStyle caption(Palette p) => GoogleFonts.jetBrainsMono(fontSize: 10.5, fontWeight: FontWeight.w500, letterSpacing: 1, color: p.text3);
  @override
  TextStyle mono(Palette p) => GoogleFonts.jetBrainsMono(fontSize: 12.5, color: p.text2);
  @override
  TextStyle label(Palette p) => GoogleFonts.jetBrainsMono(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: p.accent);

  @override
  String sectionLabel(String s) => '// ${s.toUpperCase()}';

  @override
  double radius(Surf s) => switch (s) {
        Surf.card => 6,
        Surf.tile => 3,
        _ => 4,
      };

  /// Cut corners top-left and bottom-right.
  ShapeBorder _cut(double c, {BorderSide side = BorderSide.none}) => BeveledRectangleBorder(
        side: side,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(c), bottomRight: Radius.circular(c), topRight: const Radius.circular(2), bottomLeft: const Radius.circular(2)),
      );

  @override
  Widget background(Palette p, {required bool animate, required Widget child}) => _HudBackdrop(p: p, animate: animate, child: child);

  @override
  Widget surface(Palette p, {required Widget child, EdgeInsetsGeometry? padding, bool strong = false, double? radius, bool reduceEffects = false, bool brackets = true}) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: strong ? p.surface2 : p.surface,
        borderRadius: BorderRadius.circular(radius ?? 6),
        border: Border.all(color: strong ? p.accent : p.line, width: strong ? 1.5 : 1),
        boxShadow: strong ? [BoxShadow(color: p.glow, blurRadius: 24)] : const [],
      ),
      child: child,
    );
    if (!brackets) return box;
    return CustomPaint(foregroundPainter: BracketPainter(p.accent, all: strong), child: box);
  }

  @override
  Widget well(Palette p, {required Widget child, EdgeInsetsGeometry? padding, double? radius, bool focused = false}) => AnimatedContainer(
        duration: moveDuration,
        padding: padding,
        decoration: ShapeDecoration(
          color: p.inset,
          shape: _cut(radius ?? 12, side: BorderSide(color: focused ? p.accent : p.line, width: focused ? 1.5 : 1)),
          shadows: focused ? [BoxShadow(color: p.glow, blurRadius: 14)] : const [],
        ),
        child: child,
      );

  @override
  Widget buttonFace(Palette p, {required Widget child, required bool primary, required bool pressed, double? radius}) => AnimatedContainer(
        duration: pressDuration,
        curve: Curves.easeOut,
        decoration: ShapeDecoration(
          color: primary ? (pressed ? Color.lerp(p.accent, const Color(0xFFFFFFFF), .25) : p.accent) : (pressed ? withA(p.accent, .28) : p.tint),
          shape: _cut(14, side: primary ? BorderSide.none : BorderSide(color: p.accent, width: 1.5)),
          shadows: [BoxShadow(color: p.glow, blurRadius: pressed ? 34 : (primary ? 18 : 10), spreadRadius: pressed ? 3 : 0)],
        ),
        child: child,
      );

  @override
  Widget selectedFace(Palette p, {required Widget child, required bool selected, double? radius}) => AnimatedContainer(
        duration: moveDuration,
        curve: curve,
        decoration: BoxDecoration(
          color: selected ? p.tint : withA(p.tint, 0),
          borderRadius: BorderRadius.circular(2),
          border: Border(bottom: BorderSide(color: selected ? p.accent : withA(p.accent, 0), width: 2)),
        ),
        child: child,
      );

  @override
  Widget toggle(Palette p, bool on) => AnimatedContainer(
        duration: moveDuration,
        width: 56,
        height: 28,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: on ? p.tint : p.inset,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: on ? p.accent : p.lineStrong, width: 1.5),
          boxShadow: on ? [BoxShadow(color: p.glow, blurRadius: 12)] : const [],
        ),
        child: AnimatedAlign(
          duration: moveDuration,
          curve: Curves.easeOutCubic,
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: AnimatedContainer(
            duration: moveDuration,
            width: 19,
            height: 19,
            decoration: BoxDecoration(
              color: on ? p.accent : p.text3,
              borderRadius: BorderRadius.circular(2),
              boxShadow: on ? [BoxShadow(color: p.glow, blurRadius: 10)] : const [],
            ),
          ),
        ),
      );

  @override
  Widget sliderTrack(Palette p, double v, {required bool dragging}) => LayoutBuilder(builder: (c, k) {
        final w = k.maxWidth;
        const knob = 22.0;
        final x = (w - knob) * v;
        return SizedBox(
          height: 30,
          child: Stack(alignment: Alignment.centerLeft, children: [
            Container(height: 4, color: p.line),
            Container(width: x + knob / 2, height: 4, decoration: BoxDecoration(color: p.accent, boxShadow: [BoxShadow(color: p.glow, blurRadius: 10)])),
            Positioned(
              left: x,
              child: AnimatedContainer(
                duration: pressDuration,
                width: knob,
                height: knob,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.surface2,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: p.accent, width: 2),
                  boxShadow: [BoxShadow(color: p.glow, blurRadius: dragging ? 22 : 12)],
                ),
                child: Container(width: 6, height: 6, color: p.accent),
              ),
            ),
          ]),
        );
      });

  @override
  Widget chip(Palette p, {required String label, required Color color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(color: p.inset, borderRadius: BorderRadius.circular(2), border: Border.all(color: color)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, boxShadow: [BoxShadow(color: color, blurRadius: 8)])),
          const SizedBox(width: 8),
          Text(label.toUpperCase(), style: caption(p).copyWith(color: color, fontSize: 11)),
        ]),
      );

  @override
  Widget bubble(Palette p, {required Widget child, required bool outgoing, bool tail = true}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: ShapeDecoration(
          color: outgoing ? p.tint : p.surface2,
          shape: BeveledRectangleBorder(
            side: BorderSide(color: outgoing ? p.accent : p.lineStrong, width: outgoing ? 1.2 : 1),
            borderRadius: outgoing
                ? const BorderRadius.only(topLeft: Radius.circular(12), bottomRight: Radius.circular(12), topRight: Radius.circular(2), bottomLeft: Radius.circular(2))
                : const BorderRadius.only(topRight: Radius.circular(12), bottomLeft: Radius.circular(12), topLeft: Radius.circular(2), bottomRight: Radius.circular(2)),
          ),
          shadows: outgoing ? [BoxShadow(color: withA(p.glow, .6), blurRadius: 12)] : const [],
        ),
        child: child,
      );

  @override
  Widget avatar(Palette p, String initials, double size, int seed, {bool group = false}) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _HexPainter(fill: p.surface2, line: p.accent, glow: p.glow),
          child: Center(child: Text(initials, style: GoogleFonts.jetBrainsMono(fontSize: size * .27, fontWeight: FontWeight.w700, color: p.accent))),
        ),
      );

  @override
  Widget accentTile(Palette p, {required Widget child, required double size}) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: ShapeDecoration(color: p.accent, shape: _cut(size * .2), shadows: [BoxShadow(color: p.glow, blurRadius: 18)]),
        child: child,
      );

  @override
  Widget transition(Animation<double> a, Widget child) {
    final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    // A horizontal wipe with a bright leading edge.
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) => ClipRect(
        clipper: _WipeClipper(c.value),
        child: Opacity(opacity: (.4 + .6 * c.value).clamp(0, 1), child: child),
      ),
    );
  }

  @override
  Duration get pressDuration => const Duration(milliseconds: 120);
  @override
  Duration get moveDuration => const Duration(milliseconds: 240);
}

class _WipeClipper extends CustomClipper<Rect> {
  final double t;
  _WipeClipper(this.t);
  @override
  Rect getClip(Size s) => Rect.fromLTWH(0, 0, s.width, s.height * t.clamp(0.0, 1.0));
  @override
  bool shouldReclip(_WipeClipper o) => o.t != t;
}

class _HexPainter extends CustomPainter {
  final Color fill, line, glow;
  _HexPainter({required this.fill, required this.line, required this.glow});
  @override
  void paint(Canvas canvas, Size s) {
    final r = s.shortestSide / 2;
    final c = s.center(Offset.zero);
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final a = math.pi / 3 * i - math.pi / 2;
      final pt = c + Offset(math.cos(a), math.sin(a)) * (r - 1.5);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(path, Paint()
      ..color = glow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawPath(path, Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_HexPainter o) => o.line != line || o.fill != fill;
}

class _HudBackdrop extends StatefulWidget {
  final Palette p;
  final bool animate;
  final Widget child;
  const _HudBackdrop({required this.p, required this.animate, required this.child});
  @override
  State<_HudBackdrop> createState() => _HudBackdropState();
}

class _HudBackdropState extends State<_HudBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 20));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant _HudBackdrop old) {
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
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        ColoredBox(color: widget.p.bg),
        RepaintBoundary(
          child: AnimatedBuilder(animation: _c, builder: (_, __) => CustomPaint(painter: _GridPainter(widget.p, _c.value))),
        ),
        widget.child,
      ]);
}

class _GridPainter extends CustomPainter {
  final Palette p;
  final double t;
  _GridPainter(this.p, this.t);

  static final List<List<double>> _dots = () {
    final r = math.Random(11);
    return List.generate(70, (_) => [r.nextDouble(), r.nextDouble(), 1.2 + r.nextDouble() * 2, r.nextDouble()]);
  }();

  @override
  void paint(Canvas canvas, Size s) {
    // Corner glow.
    canvas.drawCircle(
      Offset(s.width * .1, s.height * .05),
      s.longestSide * .6,
      Paint()..shader = RadialGradient(colors: [withA(p.accent, p.dark ? .16 : .10), withA(p.accent, 0)]).createShader(Rect.fromCircle(center: Offset(s.width * .1, s.height * .05), radius: s.longestSide * .6)),
    );
    canvas.drawCircle(
      Offset(s.width * .9, s.height * .9),
      s.longestSide * .5,
      Paint()..shader = RadialGradient(colors: [withA(p.accent2, p.dark ? .10 : .06), withA(p.accent2, 0)]).createShader(Rect.fromCircle(center: Offset(s.width * .9, s.height * .9), radius: s.longestSide * .5)),
    );
    // Grid.
    final g = Paint()
      ..color = withA(p.dark ? p.accent : const Color(0xFF0B1624), .07)
      ..strokeWidth = 1;
    for (double x = 0; x <= s.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, s.height), g);
    }
    for (double y = 0; y <= s.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(s.width, y), g);
    }
    // Drifting particles that twinkle.
    final dot = Paint();
    for (final d in _dots) {
      final y = ((d[1] - t * .15) % 1.0) * s.height;
      final tw = .15 + .6 * (.5 + .5 * math.sin((t * 6 + d[3]) * 2 * math.pi));
      dot.color = withA(p.accent, tw * (p.dark ? 1 : .6));
      canvas.drawCircle(Offset(d[0] * s.width, y), d[2] / 2, dot);
    }
    // Scan line sweeping down.
    final sy = (t * 3 % 1.0) * (s.height + 140) - 70;
    final rect = Rect.fromLTWH(0, sy - 35, s.width, 70);
    canvas.drawRect(
      rect,
      Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [withA(p.accent, 0), withA(p.accent, p.dark ? .07 : .05), withA(p.accent, 0)]).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GridPainter o) => o.t != t || o.p != p;
}

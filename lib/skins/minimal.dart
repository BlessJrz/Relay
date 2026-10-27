import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';

import '../state/settings.dart';
import 'skin.dart';

/// Modern Minimal: whitespace, bold clean type, soft corners and one vibrant
/// accent (blue, violet, coral or teal) used sparingly. No borders.
class MinimalSkin extends Skin {
  @override
  DesignId get id => DesignId.minimal;

  @override
  List<AccentChoice> get accents => const [
        AccentChoice('Electric blue', Color(0xFF2F6BFF), Color(0xFF3D74F5)),
        AccentChoice('Violet', Color(0xFF7C3AED), Color(0xFF8B5CF6)),
        AccentChoice('Coral', Color(0xFFDC3B34), Color(0xFFDE3E44)),
        AccentChoice('Teal', Color(0xFF0B8276), Color(0xFF0B8276)),
      ];

  Color _shift(Color c, double deg) {
    final h = HSLColor.fromColor(c);
    return h.withHue((h.hue + deg) % 360).toColor();
  }

  @override
  Palette palette(bool dark, int accent) {
    final a = accents[accent.clamp(0, accents.length - 1)];
    final ac = dark ? a.dark : a.light;
    final ac2 = _shift(ac, 22);
    const avatars = [Color(0xFF5B8DFF), Color(0xFFA78BFA), Color(0xFFFF7F78), Color(0xFF2DD4BF)];
    return dark
        ? Palette(
            dark: true,
            bg: const Color(0xFF0A0E1A),
            surface: const Color(0xFF121827),
            surface2: const Color(0xFF1A2236),
            inset: const Color(0xFF0F1523),
            line: const Color(0x14FFFFFF),
            lineStrong: const Color(0x26FFFFFF),
            text: const Color(0xFFF3F5FB),
            text2: const Color(0xFFA6AFC6),
            text3: const Color(0xFF6C768F),
            onAccent: const Color(0xFFFFFFFF),
            accent: ac,
            accent2: ac2,
            tint: withA(ac, .16),
            glow: withA(ac, .30),
            success: const Color(0xFF34D399),
            warning: const Color(0xFFFBBF24),
            danger: const Color(0xFFFB7185),
            avatars: avatars,
          )
        : Palette(
            dark: false,
            bg: const Color(0xFFF4F5F9),
            surface: const Color(0xFFFFFFFF),
            surface2: const Color(0xFFEAEDF4),
            inset: const Color(0xFFEEF0F6),
            line: const Color(0x0F0F172A),
            lineStrong: const Color(0x1F0F172A),
            text: const Color(0xFF0F1424),
            text2: const Color(0xFF586079),
            text3: const Color(0xFF8D95AB),
            onAccent: const Color(0xFFFFFFFF),
            accent: ac,
            accent2: ac2,
            tint: withA(ac, .11),
            glow: withA(ac, .28),
            success: const Color(0xFF16A36B),
            warning: const Color(0xFFD98A00),
            danger: const Color(0xFFE0455B),
            avatars: avatars,
          );
  }

  TextStyle _t(Palette p, double size, FontWeight w, {double ls = 0, double? h, Color? c}) =>
      GoogleFonts.manrope(fontSize: size, fontWeight: w, letterSpacing: ls, height: h, color: c ?? p.text);

  @override
  TextStyle display(Palette p) => _t(p, 34, FontWeight.w800, ls: -.8, h: 1.12);
  @override
  TextStyle title(Palette p) => _t(p, 23, FontWeight.w800, ls: -.4, h: 1.2);
  @override
  TextStyle headline(Palette p) => _t(p, 16, FontWeight.w700, ls: -.1, h: 1.3);
  @override
  TextStyle body(Palette p) => _t(p, 15, FontWeight.w500, h: 1.42);
  @override
  TextStyle callout(Palette p) => _t(p, 13, FontWeight.w500, h: 1.38, c: p.text2);
  @override
  TextStyle caption(Palette p) => _t(p, 11, FontWeight.w600, c: p.text3);
  @override
  TextStyle mono(Palette p) => GoogleFonts.jetBrainsMono(fontSize: 12.5, color: p.text2);
  @override
  TextStyle label(Palette p) => _t(p, 11, FontWeight.w700, ls: 1.1, c: p.text3);

  @override
  double radius(Surf s) => switch (s) {
        Surf.card => 24,
        Surf.control => 999,
        Surf.pill => 999,
        Surf.tile => 14,
        _ => 20,
      };

  Gradient _grad(Palette p) => LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [p.accent, p.accent2]);

  List<BoxShadow> _soft(Palette p, {double a = .07, double blur = 22, double y = 8}) =>
      p.dark ? const [] : [BoxShadow(color: Color.fromRGBO(15, 23, 42, a), blurRadius: blur, offset: Offset(0, y))];

  @override
  Widget background(Palette p, {required bool animate, required Widget child}) => ColoredBox(color: p.bg, child: child);

  @override
  Widget surface(Palette p, {required Widget child, EdgeInsetsGeometry? padding, bool strong = false, double? radius, bool reduceEffects = false}) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: strong && p.dark ? p.surface2 : p.surface,
          borderRadius: BorderRadius.circular(radius ?? this.radius(Surf.card)),
          boxShadow: _soft(p, a: strong ? .12 : .06),
        ),
        child: child,
      );

  @override
  Widget well(Palette p, {required Widget child, EdgeInsetsGeometry? padding, double? radius, bool focused = false}) => AnimatedContainer(
        duration: moveDuration,
        padding: padding,
        decoration: BoxDecoration(
          color: p.inset,
          borderRadius: BorderRadius.circular(radius ?? 16),
          border: Border.all(color: focused ? p.accent : const Color(0x00000000), width: 1.5),
        ),
        child: child,
      );

  @override
  Widget buttonFace(Palette p, {required Widget child, required bool primary, required bool pressed, double? radius}) => AnimatedContainer(
        duration: pressDuration,
        decoration: BoxDecoration(
          gradient: primary ? _grad(p) : null,
          color: primary ? null : (pressed ? p.line : p.surface2),
          borderRadius: BorderRadius.circular(radius ?? 999),
          boxShadow: primary && !pressed ? [BoxShadow(color: p.glow, blurRadius: 18, offset: const Offset(0, 7), spreadRadius: -6)] : const [],
        ),
        foregroundDecoration: primary && pressed ? BoxDecoration(color: const Color(0x22000000), borderRadius: BorderRadius.circular(radius ?? 999)) : null,
        child: child,
      );

  @override
  Widget selectedFace(Palette p, {required Widget child, required bool selected, double? radius}) => AnimatedContainer(
        duration: moveDuration,
        curve: curve,
        decoration: BoxDecoration(color: selected ? p.tint : const Color(0x00000000), borderRadius: BorderRadius.circular(radius ?? 999)),
        child: child,
      );

  @override
  Widget toggle(Palette p, bool on) => AnimatedContainer(
        duration: moveDuration,
        curve: Curves.easeInOutCubic,
        width: 52,
        height: 30,
        padding: const EdgeInsets.all(3),
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          gradient: on ? _grad(p) : null,
          color: on ? null : p.surface2,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFFFFFF), boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1))]),
        ),
      );

  @override
  Widget sliderTrack(Palette p, double v, {required bool dragging}) => LayoutBuilder(builder: (c, k) {
        final w = k.maxWidth;
        const knob = 26.0;
        final x = (w - knob) * v;
        return SizedBox(
          height: 34,
          child: Stack(alignment: Alignment.centerLeft, children: [
            Container(width: w, height: 6, decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(3))),
            Container(width: x + knob / 2, height: 6, decoration: BoxDecoration(gradient: _grad(p), borderRadius: BorderRadius.circular(3))),
            Positioned(
              left: x,
              child: AnimatedContainer(
                duration: pressDuration,
                width: knob,
                height: knob,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFFFFF),
                  boxShadow: [BoxShadow(color: const Color(0x40000000), blurRadius: dragging ? 9 : 5, offset: const Offset(0, 2))],
                ),
              ),
            ),
          ]),
        );
      });

  @override
  Widget chip(Palette p, {required String label, required Color color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: withA(color, .14), borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
          const SizedBox(width: 7),
          Text(label, style: callout(p).copyWith(color: p.text, fontWeight: FontWeight.w700, fontSize: 12)),
        ]),
      );

  @override
  Widget bubble(Palette p, {required Widget child, required bool outgoing, bool tail = true}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          gradient: outgoing ? _grad(p) : null,
          color: outgoing ? null : p.surface2,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(!outgoing && tail ? 6 : 20),
            bottomRight: Radius.circular(outgoing && tail ? 6 : 20),
          ),
        ),
        child: child,
      );

  @override
  Widget avatar(Palette p, String initials, double size, int seed, {bool group = false, ImageProvider? image}) {
    final c = p.avatars[seed % p.avatars.length];
    final text = Text(initials, style: _t(p, size * .34, FontWeight.w800, c: c));
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: withA(c, .16)),
      child: image == null ? text : Stack(alignment: Alignment.center, children: [text, ClipOval(child: photoFill(image, size))]),
    );
  }

  @override
  Decoration listDecoration(Palette p) => BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(radius(Surf.card)), boxShadow: _soft(p, a: .06));

  @override
  Widget accentTile(Palette p, {required Widget child, required double size}) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: _grad(p),
          borderRadius: BorderRadius.circular(size * .32),
          boxShadow: [BoxShadow(color: p.glow, blurRadius: 16, offset: const Offset(0, 7), spreadRadius: -5)],
        ),
        child: DefaultTextStyle.merge(style: TextStyle(color: p.onAccent), child: child),
      );

  @override
  Widget transition(Animation<double> a, Widget child) {
    final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return FadeTransition(opacity: c, child: SlideTransition(position: Tween(begin: const Offset(0, .035), end: Offset.zero).animate(c), child: child));
  }

  @override
  Duration get pressDuration => const Duration(milliseconds: 130);
  @override
  Duration get moveDuration => const Duration(milliseconds: 230);
}

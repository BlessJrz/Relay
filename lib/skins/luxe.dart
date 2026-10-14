import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';

import '../state/settings.dart';
import 'skin.dart';

/// Monochrome Luxe: black, graphite, white and silver. Flat surfaces, hairline
/// edges, an editorial serif for headings, and no glow, gradients or shadows.
class LuxeSkin extends Skin {
  @override
  DesignId get id => DesignId.luxe;

  @override
  double get iconStroke => 1.6;

  @override
  List<AccentChoice> get accents => const [
        AccentChoice('Silver', Color(0xFF3F3F46), Color(0xFFD4D4D8)),
        AccentChoice('Pearl', Color(0xFF000000), Color(0xFFFFFFFF)),
        AccentChoice('Graphite', Color(0xFF71717A), Color(0xFFA1A1AA)),
      ];

  @override
  Palette palette(bool dark, int accent) {
    final a = accents[accent.clamp(0, accents.length - 1)];
    final ac = dark ? a.dark : a.light;
    final on = ac.computeLuminance() > .45 ? const Color(0xFF0A0A0A) : const Color(0xFFFFFFFF);
    const grays = [Color(0xFF8E8E93), Color(0xFFAEAEB2), Color(0xFF636366), Color(0xFFC7C7CC)];
    return dark
        ? Palette(
            dark: true,
            bg: const Color(0xFF000000),
            surface: const Color(0xFF0D0D0E),
            surface2: const Color(0xFF181819),
            inset: const Color(0xFF131314),
            line: const Color(0x1FFFFFFF),
            lineStrong: const Color(0x38FFFFFF),
            text: const Color(0xFFF5F5F4),
            text2: const Color(0xFFA1A1A6),
            text3: const Color(0xFF6C6C70),
            onAccent: on,
            accent: ac,
            accent2: ac,
            tint: withA(ac, .10),
            glow: const Color(0x00000000),
            success: const Color(0xFFB8D8C0),
            warning: const Color(0xFFD9CFA8),
            danger: const Color(0xFFE0A9A9),
            avatars: grays,
          )
        : Palette(
            dark: false,
            bg: const Color(0xFFFFFFFF),
            surface: const Color(0xFFF7F7F6),
            surface2: const Color(0xFFECECEA),
            inset: const Color(0xFFF1F1F0),
            line: const Color(0x14000000),
            lineStrong: const Color(0x2E000000),
            text: const Color(0xFF0A0A0A),
            text2: const Color(0xFF58585D),
            text3: const Color(0xFF8E8E93),
            onAccent: on,
            accent: ac,
            accent2: ac,
            tint: withA(ac, .08),
            glow: const Color(0x00000000),
            success: const Color(0xFF3F7A52),
            warning: const Color(0xFF8A7430),
            danger: const Color(0xFFA14545),
            avatars: grays,
          );
  }

  TextStyle _sans(Palette p, double size, FontWeight w, {double ls = 0, double? h, Color? c}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, letterSpacing: ls, height: h, color: c ?? p.text);
  TextStyle _serif(Palette p, double size, FontWeight w, {double ls = 0, double? h, Color? c}) =>
      GoogleFonts.cormorantGaramond(fontSize: size, fontWeight: w, letterSpacing: ls, height: h, color: c ?? p.text);

  @override
  TextStyle display(Palette p) => _serif(p, 38, FontWeight.w600, ls: -.4, h: 1.1);
  @override
  TextStyle title(Palette p) => _serif(p, 26, FontWeight.w600, ls: -.1, h: 1.15);
  @override
  TextStyle headline(Palette p) => _sans(p, 15.5, FontWeight.w600, ls: -.1, h: 1.3);
  @override
  TextStyle body(Palette p) => _sans(p, 15, FontWeight.w400, h: 1.42);
  @override
  TextStyle callout(Palette p) => _sans(p, 13, FontWeight.w400, h: 1.38, c: p.text2);
  @override
  TextStyle caption(Palette p) => _sans(p, 11, FontWeight.w500, ls: .3, c: p.text3);
  @override
  TextStyle mono(Palette p) => GoogleFonts.jetBrainsMono(fontSize: 12.5, color: p.text2);
  @override
  TextStyle label(Palette p) => _sans(p, 10.5, FontWeight.w600, ls: 1.8, c: p.text3);

  @override
  double radius(Surf s) => switch (s) {
        Surf.card => 20,
        Surf.control => 999,
        Surf.pill => 999,
        Surf.tile => 12,
        _ => 18,
      };

  Border _edge(Palette p, {bool strong = false}) => Border.all(color: strong ? p.lineStrong : p.line, width: .8);

  @override
  Widget background(Palette p, {required bool animate, required Widget child}) => ColoredBox(color: p.bg, child: child);

  @override
  Widget surface(Palette p, {required Widget child, EdgeInsetsGeometry? padding, bool strong = false, double? radius, bool reduceEffects = false, bool brackets = true}) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: strong ? p.surface2 : p.surface,
          borderRadius: BorderRadius.circular(radius ?? this.radius(Surf.card)),
          border: _edge(p),
        ),
        child: child,
      );

  @override
  Widget well(Palette p, {required Widget child, EdgeInsetsGeometry? padding, double? radius, bool focused = false}) => AnimatedContainer(
        duration: moveDuration,
        padding: padding,
        decoration: BoxDecoration(
          color: p.inset,
          borderRadius: BorderRadius.circular(radius ?? 14),
          border: Border.all(color: focused ? p.text2 : p.line, width: focused ? 1 : .8),
        ),
        child: child,
      );

  @override
  Widget buttonFace(Palette p, {required Widget child, required bool primary, required bool pressed, double? radius}) => AnimatedContainer(
        duration: pressDuration,
        decoration: BoxDecoration(
          color: primary ? p.accent.withOpacity(pressed ? .82 : 1) : (pressed ? p.surface2 : p.surface),
          borderRadius: BorderRadius.circular(radius ?? 14),
          border: primary ? null : _edge(p, strong: true),
        ),
        child: child,
      );

  @override
  Widget selectedFace(Palette p, {required Widget child, required bool selected, double? radius}) => AnimatedContainer(
        duration: moveDuration,
        curve: curve,
        decoration: BoxDecoration(
          color: selected ? p.surface2 : const Color(0x00000000),
          borderRadius: BorderRadius.circular(radius ?? 999),
          border: Border.all(color: selected ? p.lineStrong : const Color(0x00000000), width: .8),
        ),
        child: child,
      );

  @override
  Widget toggle(Palette p, bool on) => AnimatedContainer(
        duration: moveDuration,
        curve: Curves.easeInOutCubic,
        width: 50,
        height: 30,
        padding: const EdgeInsets.all(3),
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          color: on ? p.accent : const Color(0x00000000),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: on ? p.accent : p.lineStrong, width: 1),
        ),
        child: AnimatedContainer(
          duration: moveDuration,
          width: 22,
          height: 22,
          decoration: BoxDecoration(shape: BoxShape.circle, color: on ? p.onAccent : p.text3),
        ),
      );

  @override
  Widget sliderTrack(Palette p, double v, {required bool dragging}) => LayoutBuilder(builder: (c, k) {
        final w = k.maxWidth;
        final knob = dragging ? 22.0 : 18.0;
        final x = (w - knob) * v;
        return SizedBox(
          height: 34,
          child: Stack(alignment: Alignment.centerLeft, children: [
            Container(width: w, height: 3, decoration: BoxDecoration(color: p.lineStrong, borderRadius: BorderRadius.circular(2))),
            Container(width: x + knob / 2, height: 3, decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(2))),
            Positioned(
              left: x,
              child: AnimatedContainer(
                duration: pressDuration,
                width: knob,
                height: knob,
                decoration: BoxDecoration(shape: BoxShape.circle, color: p.accent, border: Border.all(color: p.bg, width: 3)),
              ),
            ),
          ]),
        );
      });

  @override
  Widget chip(Palette p, {required String label, required Color color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), border: _edge(p, strong: true)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
          const SizedBox(width: 7),
          Text(label, style: callout(p).copyWith(color: p.text, fontSize: 12)),
        ]),
      );

  @override
  Widget bubble(Palette p, {required Widget child, required bool outgoing, bool tail = true}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          color: outgoing ? p.accent : p.surface2,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(!outgoing && tail ? 5 : 18),
            bottomRight: Radius.circular(outgoing && tail ? 5 : 18),
          ),
          border: outgoing ? null : _edge(p),
        ),
        child: child,
      );

  @override
  Widget avatar(Palette p, String initials, double size, int seed, {bool group = false, ImageProvider? image}) {
    final text = Text(initials, style: _serif(p, size * .42, FontWeight.w600, c: p.text2));
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: p.surface2, border: _edge(p, strong: true)),
      child: image == null ? text : Stack(alignment: Alignment.center, children: [text, ClipOval(child: photoFill(image, size - 2))]),
    );
  }

  @override
  Decoration listDecoration(Palette p) => BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(radius(Surf.card)), border: _edge(p));

  @override
  Widget accentTile(Palette p, {required Widget child, required double size}) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(size * .28)),
        child: DefaultTextStyle.merge(style: TextStyle(color: p.onAccent), child: child),
      );

  @override
  Widget transition(Animation<double> a, Widget child) {
    final c = CurvedAnimation(parent: a, curve: Curves.easeOutQuart, reverseCurve: Curves.easeInCubic);
    return FadeTransition(opacity: c, child: ScaleTransition(scale: Tween(begin: .985, end: 1.0).animate(c), child: child));
  }

  @override
  Duration get pressDuration => const Duration(milliseconds: 120);
  @override
  Duration get moveDuration => const Duration(milliseconds: 240);
  @override
  Curve get curve => Curves.easeOutQuart;
}

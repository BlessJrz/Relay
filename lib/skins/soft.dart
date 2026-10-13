import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';

import '../state/settings.dart';
import 'skin.dart';

/// Design 2 — Neumorphism: everything is sculpted from one surface colour.
class SoftSkin extends Skin {
  @override
  DesignId get id => DesignId.soft;

  @override
  List<AccentChoice> get accents => const [
        AccentChoice('Teal', Color(0xFF0E9384), Color(0xFF2DD4BF)),
        AccentChoice('Indigo', Color(0xFF5B6CFF), Color(0xFF8E9BFF)),
        AccentChoice('Coral', Color(0xFFE2625A), Color(0xFFFF8A80)),
        AccentChoice('Gold', Color(0xFFC98A00), Color(0xFFFBBF24)),
        AccentChoice('Green', Color(0xFF22A06B), Color(0xFF4ADE80)),
      ];

  @override
  Palette palette(bool dark, int accent) {
    final a = accents[accent.clamp(0, accents.length - 1)];
    final ac = dark ? a.dark : a.light;
    return dark
        ? Palette(
            dark: true,
            bg: const Color(0xFF262A32),
            surface: const Color(0xFF262A32),
            surface2: const Color(0xFF2B3039),
            inset: const Color(0xFF1F2228),
            line: const Color(0x8C13151A),
            lineStrong: const Color(0xFF13151A),
            text: const Color(0xFFE9EDF5),
            text2: const Color(0xFFA3ADBE),
            text3: const Color(0xFF707A8D),
            onAccent: const Color(0xFF06211D),
            accent: ac,
            accent2: ac,
            tint: withA(ac, .16),
            glow: withA(ac, .32),
            success: const Color(0xFF4ADE80),
            warning: const Color(0xFFFBBF24),
            danger: const Color(0xFFFB7185),
            lightShadow: const Color(0xFF383E4A),
            darkShadow: const Color(0xE613151A),
            avatars: const [Color(0xFF2DD4BF), Color(0xFF8E9BFF), Color(0xFFFF8A80), Color(0xFFFBBF24)],
          )
        : Palette(
            dark: false,
            bg: const Color(0xFFE7EBF1),
            surface: const Color(0xFFE7EBF1),
            surface2: const Color(0xFFEDF0F5),
            inset: const Color(0xFFDEE3EA),
            line: const Color(0x73B4BFD0),
            lineStrong: const Color(0xFFB4BFD0),
            text: const Color(0xFF2A3342),
            text2: const Color(0xFF667186),
            text3: const Color(0xFF98A2B5),
            onAccent: const Color(0xFFFFFFFF),
            accent: ac,
            accent2: ac,
            tint: withA(ac, .14),
            glow: withA(ac, .35),
            success: const Color(0xFF22A06B),
            warning: const Color(0xFFD98A00),
            danger: const Color(0xFFD6455D),
            lightShadow: const Color(0xFFFFFFFF),
            darkShadow: const Color(0xD9B4BFD0),
            avatars: const [Color(0xFF0E9384), Color(0xFF5B6CFF), Color(0xFFE2625A), Color(0xFFC98A00)],
          );
  }

  TextStyle _t(Palette p, double size, FontWeight w, {double ls = 0, double? h, Color? c}) =>
      GoogleFonts.nunito(fontSize: size, fontWeight: w, letterSpacing: ls, height: h, color: c ?? p.text);

  @override
  TextStyle display(Palette p) => _t(p, 32, FontWeight.w800, ls: -.3, h: 1.2);
  @override
  TextStyle title(Palette p) => _t(p, 22, FontWeight.w700, h: 1.25);
  @override
  TextStyle headline(Palette p) => _t(p, 16.5, FontWeight.w700, h: 1.3);
  @override
  TextStyle body(Palette p) => _t(p, 15, FontWeight.w500, h: 1.4);
  @override
  TextStyle callout(Palette p) => _t(p, 13, FontWeight.w600, h: 1.35, c: p.text2);
  @override
  TextStyle caption(Palette p) => _t(p, 11, FontWeight.w600, ls: .2, c: p.text3);
  @override
  TextStyle mono(Palette p) => GoogleFonts.jetBrainsMono(fontSize: 12.5, color: p.text2);
  @override
  TextStyle label(Palette p) => _t(p, 11, FontWeight.w700, ls: 1, c: p.text3);

  @override
  double radius(Surf s) => switch (s) {
        Surf.card => 28,
        Surf.control => 999,
        Surf.pill => 999,
        Surf.tile => 14,
        _ => 22,
      };

  List<BoxShadow> _raise(Palette p, double o, double b) => [
        BoxShadow(color: p.lightShadow, offset: Offset(-o, -o), blurRadius: b),
        BoxShadow(color: p.darkShadow, offset: Offset(o, o), blurRadius: b),
      ];

  @override
  Widget background(Palette p, {required bool animate, required Widget child}) =>
      ColoredBox(color: p.bg, child: child);

  @override
  Widget surface(Palette p, {required Widget child, EdgeInsetsGeometry? padding, bool strong = false, double? radius, bool reduceEffects = false, bool brackets = true}) {
    final o = strong ? 12.0 : 8.0;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(radius ?? this.radius(Surf.card)),
        boxShadow: _raise(p, o, o * 2.2),
      ),
      child: child,
    );
  }

  Widget _inset(Palette p, {required Widget child, EdgeInsetsGeometry? padding, required double radius, double o = 3}) => CustomPaint(
        painter: InsetShadowPainter(radius: radius, fill: p.inset, dark: p.darkShadow, light: p.lightShadow, offset: o, blur: o * 2.4),
        child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
      );

  @override
  Widget well(Palette p, {required Widget child, EdgeInsetsGeometry? padding, double? radius, bool focused = false}) {
    final r = radius ?? 16;
    return AnimatedContainer(
      duration: moveDuration,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        border: Border.all(color: focused ? p.accent : withA(p.accent, 0), width: 1.5),
      ),
      child: _inset(p, child: child, padding: padding, radius: r),
    );
  }

  @override
  Widget buttonFace(Palette p, {required Widget child, required bool primary, required bool pressed, double? radius}) {
    final r = radius ?? 999;
    final raised = AnimatedContainer(
      duration: pressDuration,
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: primary ? p.accent : p.surface,
        borderRadius: BorderRadius.circular(r),
        boxShadow: pressed
            ? _raise(p, 0, 0)
            : [..._raise(p, 5, 11), if (primary) BoxShadow(color: p.glow, blurRadius: 16, offset: const Offset(0, 6), spreadRadius: -6)],
      ),
      child: child,
    );
    return Stack(children: [
      raised,
      Positioned.fill(
        child: IgnorePointer(
          child: AnimatedOpacity(
            duration: pressDuration,
            opacity: pressed ? 1 : 0,
            child: CustomPaint(
              painter: InsetShadowPainter(
                radius: r,
                fill: withA(primary ? p.accent : p.inset, primary ? .0 : .0),
                dark: primary ? withA(const Color(0xFF000000), .35) : p.darkShadow,
                light: primary ? withA(const Color(0xFFFFFFFF), .25) : p.lightShadow,
                offset: 3,
                blur: 7,
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  @override
  Widget selectedFace(Palette p, {required Widget child, required bool selected, double? radius}) {
    final r = radius ?? 999;
    return Stack(children: [
      Positioned.fill(
        child: AnimatedOpacity(
          duration: moveDuration,
          opacity: selected ? 1 : 0,
          child: CustomPaint(painter: InsetShadowPainter(radius: r, fill: p.inset, dark: p.darkShadow, light: p.lightShadow, offset: 3, blur: 7)),
        ),
      ),
      child,
    ]);
  }

  @override
  Widget toggle(Palette p, bool on) => SizedBox(
        width: 58,
        height: 32,
        child: Stack(children: [
          Positioned.fill(
            child: CustomPaint(
              painter: InsetShadowPainter(radius: 16, fill: on ? Color.alphaBlend(p.tint, p.inset) : p.inset, dark: p.darkShadow, light: p.lightShadow, offset: 2.5, blur: 6),
            ),
          ),
          AnimatedAlign(
            duration: moveDuration,
            curve: Curves.easeInOutCubic,
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.all(4),
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: p.surface, boxShadow: _raise(p, 2.5, 6)),
              child: AnimatedContainer(
                duration: moveDuration,
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? p.accent : p.text3,
                  boxShadow: on ? [BoxShadow(color: p.glow, blurRadius: 6)] : const [],
                ),
              ),
            ),
          ),
        ]),
      );

  @override
  Widget sliderTrack(Palette p, double v, {required bool dragging}) => LayoutBuilder(builder: (c, k) {
        final w = k.maxWidth;
        const knob = 30.0;
        final x = (w - knob) * v;
        return SizedBox(
          height: 34,
          child: Stack(alignment: Alignment.centerLeft, children: [
            SizedBox(height: 10, width: w, child: CustomPaint(painter: InsetShadowPainter(radius: 5, fill: p.inset, dark: p.darkShadow, light: p.lightShadow, offset: 2, blur: 4))),
            Container(width: x + knob / 2, height: 10, decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(5), boxShadow: [BoxShadow(color: p.glow, blurRadius: 8)])),
            Positioned(
              left: x,
              child: AnimatedContainer(
                duration: pressDuration,
                width: knob,
                height: knob,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: p.surface, boxShadow: dragging ? _raise(p, 1.5, 4) : _raise(p, 3, 7)),
                child: Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: p.accent)),
              ),
            ),
          ]),
        );
      });

  @override
  Widget chip(Palette p, {required String label, required Color color}) => _inset(
        p,
        radius: 99,
        o: 2.5,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color, boxShadow: [BoxShadow(color: color, blurRadius: 6)])),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      decoration: BoxDecoration(
        color: outgoing ? p.accent : p.surface,
        borderRadius: r,
        boxShadow: outgoing
            ? [..._raise(p, 3, 8), BoxShadow(color: p.glow, blurRadius: 12, spreadRadius: -6, offset: const Offset(0, 6))]
            : _raise(p, 3, 8),
      ),
      child: child,
    );
  }

  @override
  Widget avatar(Palette p, String initials, double size, int seed, {bool group = false, ImageProvider? image}) {
    final text = Text(initials, style: GoogleFonts.nunito(fontSize: size * .33, fontWeight: FontWeight.w800, color: p.avatars[seed % p.avatars.length]));
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: p.surface, boxShadow: _raise(p, 4, 9)),
      child: image == null ? text : Stack(alignment: Alignment.center, children: [text, ClipOval(child: photoFill(image, size - 6))]),
    );
  }

  @override
  Decoration listDecoration(Palette p) => BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(radius(Surf.card)),
        boxShadow: _raise(p, 8, 17.6),
      );

  @override
  Widget accentTile(Palette p, {required Widget child, required double size}) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: p.accent,
          borderRadius: BorderRadius.circular(size * .32),
          boxShadow: [..._raise(p, 4, 9), BoxShadow(color: p.glow, blurRadius: 14, offset: const Offset(0, 6), spreadRadius: -5)],
        ),
        child: child,
      );

  @override
  Widget transition(Animation<double> a, Widget child) {
    final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return FadeTransition(
      opacity: c,
      child: SlideTransition(position: Tween(begin: const Offset(0, .03), end: Offset.zero).animate(c), child: child),
    );
  }

  @override
  Duration get pressDuration => const Duration(milliseconds: 160);
  @override
  Duration get moveDuration => const Duration(milliseconds: 260);
}

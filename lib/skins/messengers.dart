import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';

import '../state/settings.dart';
import 'skin.dart';

/// Shared drawing for the three layout-led designs (Pinned, Material,
/// Folders): flat surfaces, no glow, colour does the work.
abstract class FlatSkin extends Skin {
  TextStyle font(Palette p, double size, FontWeight w, {double ls = 0, double? h, Color? c});

  double get cardR => 20;
  double get bubbleR => 19;
  double get tailR => 5;

  /// Inputs drawn as an outline instead of a filled well.
  bool get outlinedWell => false;

  @override
  TextStyle display(Palette p) => font(p, 34, FontWeight.w800, ls: -.6, h: 1.1);
  @override
  TextStyle title(Palette p) => font(p, 24, FontWeight.w700, ls: -.3, h: 1.2);
  @override
  TextStyle headline(Palette p) => font(p, 16.5, FontWeight.w600, h: 1.3);
  @override
  TextStyle body(Palette p) => font(p, 16, FontWeight.w400, h: 1.38);
  @override
  TextStyle callout(Palette p) => font(p, 14, FontWeight.w400, h: 1.35, c: p.text2);
  @override
  TextStyle caption(Palette p) => font(p, 12, FontWeight.w500, c: p.text3);
  @override
  TextStyle mono(Palette p) => GoogleFonts.jetBrainsMono(fontSize: 12.5, color: p.text2);
  @override
  TextStyle label(Palette p) => font(p, 12.5, FontWeight.w600, ls: .4, c: p.text2);
  @override
  String sectionLabel(String s) => s;

  @override
  double radius(Surf s) => switch (s) {
        Surf.card => cardR,
        Surf.control => 999,
        Surf.pill => 999,
        Surf.tile => 12,
        _ => bubbleR,
      };

  @override
  Widget background(Palette p, {required bool animate, required Widget child}) => ColoredBox(color: p.bg, child: child);

  @override
  Widget surface(Palette p, {required Widget child, EdgeInsetsGeometry? padding, bool strong = false, double? radius, bool reduceEffects = false}) => Container(
        padding: padding,
        decoration: BoxDecoration(color: strong ? p.surface2 : p.surface, borderRadius: BorderRadius.circular(radius ?? cardR)),
        child: child,
      );

  @override
  Widget well(Palette p, {required Widget child, EdgeInsetsGeometry? padding, double? radius, bool focused = false}) => AnimatedContainer(
        duration: moveDuration,
        padding: padding,
        decoration: BoxDecoration(
          color: outlinedWell ? const Color(0x00000000) : p.inset,
          borderRadius: BorderRadius.circular(radius ?? 14),
          border: Border.all(color: focused ? p.accent : (outlinedWell ? p.lineStrong : const Color(0x00000000)), width: focused ? 1.5 : 1),
        ),
        child: child,
      );

  @override
  Widget buttonFace(Palette p, {required Widget child, required bool primary, required bool pressed, double? radius}) => AnimatedContainer(
        duration: pressDuration,
        decoration: BoxDecoration(
          color: primary ? p.accent : (pressed ? p.line : p.surface2),
          borderRadius: BorderRadius.circular(radius ?? 999),
        ),
        foregroundDecoration: primary && pressed ? BoxDecoration(color: const Color(0x26000000), borderRadius: BorderRadius.circular(radius ?? 999)) : null,
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
        width: 51,
        height: 31,
        padding: const EdgeInsets.all(2.5),
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(color: on ? p.accent : p.surface2, borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 26,
          height: 26,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFFFFFF), boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1))]),
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
            Container(width: w, height: 5, decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(3))),
            Container(width: x + knob / 2, height: 5, decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(3))),
            Positioned(
              left: x,
              child: AnimatedContainer(
                duration: pressDuration,
                width: knob,
                height: knob,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFFFFF),
                  boxShadow: [BoxShadow(color: const Color(0x40000000), blurRadius: dragging ? 9 : 4, offset: const Offset(0, 1))],
                ),
              ),
            ),
          ]),
        );
      });

  @override
  Widget chip(Palette p, {required String label, required Color color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(color: withA(color, .16), borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
          const SizedBox(width: 6),
          Text(label, style: font(p, 12.5, FontWeight.w600, c: p.text)),
        ]),
      );

  @override
  Widget bubble(Palette p, {required Widget child, required bool outgoing, bool tail = true}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: outgoing ? outgoingBubble(p) : p.surface2,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(bubbleR),
            topRight: Radius.circular(bubbleR),
            bottomLeft: Radius.circular(!outgoing && tail ? tailR : bubbleR),
            bottomRight: Radius.circular(outgoing && tail ? tailR : bubbleR),
          ),
        ),
        child: child,
      );

  /// Background and initials colour for an avatar.
  (Color, Color) avatarColors(Palette p, int seed) {
    final bg = p.avatars[seed % p.avatars.length];
    return (bg, bg.computeLuminance() > .45 ? const Color(0xFF111318) : const Color(0xFFFFFFFF));
  }

  @override
  Widget avatar(Palette p, String initials, double size, int seed, {bool group = false, ImageProvider? image}) {
    final (bg, ink) = avatarColors(p, seed);
    final text = Text(initials, style: font(p, size * .38, FontWeight.w600, c: ink));
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
      child: image == null ? text : Stack(alignment: Alignment.center, children: [text, ClipOval(child: photoFill(image, size))]),
    );
  }

  @override
  Decoration listDecoration(Palette p) => const BoxDecoration();

  @override
  Widget accentTile(Palette p, {required Widget child, required double size}) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(size * .3)),
        child: DefaultTextStyle.merge(style: TextStyle(color: p.onAccent), child: child),
      );

  @override
  Widget transition(Animation<double> a, Widget child) {
    final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return FadeTransition(opacity: c, child: SlideTransition(position: Tween(begin: const Offset(0, .03), end: Offset.zero).animate(c), child: child));
  }

  @override
  Duration get pressDuration => const Duration(milliseconds: 120);
  @override
  Duration get moveDuration => const Duration(milliseconds: 220);
}

Palette _pal({
  required bool dark,
  required Color bg,
  required Color surface,
  required Color surface2,
  required Color inset,
  required Color line,
  required Color text,
  required Color text2,
  required Color text3,
  required Color accent,
  Color? accent2,
  required List<Color> avatars,
  Color success = const Color(0xFF34C759),
  Color warning = const Color(0xFFFFB020),
  Color danger = const Color(0xFFFF453A),
}) =>
    Palette(
      dark: dark,
      bg: bg,
      surface: surface,
      surface2: surface2,
      inset: inset,
      line: line,
      lineStrong: Color.alphaBlend(withA(text, .16), bg),
      text: text,
      text2: text2,
      text3: text3,
      onAccent: accent.computeLuminance() > .45 ? const Color(0xFF0B1220) : const Color(0xFFFFFFFF),
      accent: accent,
      accent2: accent2 ?? accent,
      tint: withA(accent, dark ? .2 : .12),
      glow: const Color(0x00000000),
      success: success,
      warning: warning,
      danger: danger,
      avatars: avatars,
    );

// ---------------------------------------------------------------- Pinned

/// Pinned: a big "Messages" title, your favourite chats as large circles at
/// the top, edge-to-edge list, blue/grey bubbles with tails.
class PinnedSkin extends FlatSkin {
  @override
  DesignId get id => DesignId.pinned;
  @override
  AppLayout get layout => AppLayout.pinned;
  @override
  bool get outlinedWell => true;

  @override
  List<AccentChoice> get accents => const [
        AccentChoice('Blue', Color(0xFF2F6BF0), Color(0xFF2F6BF0)),
        AccentChoice('Red', Color(0xFFD62C26), Color(0xFFE5302A)),
        AccentChoice('Graphite', Color(0xFF3A3A3E), Color(0xFF5A5A60)),
      ];

  @override
  Palette palette(bool dark, int accent) {
    final a = accents[accent.clamp(0, accents.length - 1)];
    return dark
        ? _pal(
            dark: true,
            bg: const Color(0xFF000000),
            surface: const Color(0xFF151517),
            surface2: const Color(0xFF26262A),
            inset: const Color(0xFF1C1C1E),
            line: const Color(0xFF38383A),
            text: const Color(0xFFFFFFFF),
            text2: const Color(0xFF9A9AA0),
            text3: const Color(0xFF7C7C82),
            accent: a.dark,
            avatars: const [Color(0xFFE5302A), Color(0xFF2F6BF0), Color(0xFF55555B)],
          )
        : _pal(
            dark: false,
            bg: const Color(0xFFFFFFFF),
            surface: const Color(0xFFF2F2F7),
            surface2: const Color(0xFFE9E9EB),
            inset: const Color(0xFFF2F2F7),
            line: const Color(0xFFD8D8DC),
            text: const Color(0xFF000000),
            text2: const Color(0xFF66666B),
            text3: const Color(0xFF6E6E73),
            accent: a.light,
            avatars: const [Color(0xFFD62C26), Color(0xFF2F6BF0), Color(0xFF8E8E93)],
            danger: const Color(0xFFD62C26),
          );
  }

  @override
  TextStyle font(Palette p, double size, FontWeight w, {double ls = 0, double? h, Color? c}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, letterSpacing: ls, height: h, color: c ?? p.text);

  @override
  TextStyle headline(Palette p) => font(p, 16.5, FontWeight.w700, h: 1.3);
}

// ---------------------------------------------------------------- Material

/// Material: title with search and a profile button, chats on one rounded
/// sheet, a "Start chat" button, tonal bubbles and a big round send button.
class MaterialSkin extends FlatSkin {
  @override
  DesignId get id => DesignId.material;
  @override
  AppLayout get layout => AppLayout.material;
  @override
  double get cardR => 28;
  @override
  double get bubbleR => 22;
  @override
  double get tailR => 6;

  @override
  List<AccentChoice> get accents => const [
        AccentChoice('Blue', Color(0xFF0B57D0), Color(0xFFAECBFA)),
        AccentChoice('Red', Color(0xFFC0262D), Color(0xFFFFB4AB)),
        AccentChoice('Slate', Color(0xFF3F4759), Color(0xFFC7C6D0)),
      ];

  @override
  Color outgoingBubble(Palette p) => p.accent2;
  @override
  Color outgoingText(Palette p) => p.dark ? p.text : const Color(0xFF041E49);
  @override
  Color badge(Palette p) => p.dark ? const Color(0xFFFF6B63) : const Color(0xFFC0262D);
  @override
  Color onBadge(Palette p) => p.dark ? const Color(0xFF2A0A08) : const Color(0xFFFFFFFF);

  AccentChoice _accentOf(Palette p) => accents.firstWhere((a) => a.dark == p.accent || a.light == p.accent, orElse: () => accents.first);

  // Like Google Messages: a deep blue button with a light icon at night,
  // a pale blue one with a dark icon by day.
  @override
  Color fab(Palette p) {
    final a = _accentOf(p).light;
    return p.dark ? Color.lerp(a, const Color(0xFF000000), .18)! : Color.lerp(a, const Color(0xFFFFFFFF), .8)!;
  }

  @override
  Color onFab(Palette p) {
    final a = _accentOf(p);
    return p.dark ? Color.lerp(a.dark, const Color(0xFFFFFFFF), .35)! : Color.lerp(a.light, const Color(0xFF000000), .35)!;
  }

  @override
  Palette palette(bool dark, int accent) {
    final a = accents[accent.clamp(0, accents.length - 1)];
    return dark
        ? _pal(
            dark: true,
            bg: const Color(0xFF121318),
            surface: const Color(0xFF1C1D24),
            surface2: const Color(0xFF2A2B33),
            inset: const Color(0xFF2A2B33),
            line: const Color(0xFF30313A),
            text: const Color(0xFFE3E2E6),
            text2: const Color(0xFFA6A7B2),
            text3: const Color(0xFF8D8E99),
            accent: a.dark,
            accent2: const Color(0xFF2B3A62),
            avatars: const [Color(0xFFFFB4AB), Color(0xFFAECBFA), Color(0xFFC7C6D0)],
            danger: const Color(0xFFFF6B63),
          )
        : _pal(
            dark: false,
            bg: const Color(0xFFF2F4F8),
            surface: const Color(0xFFFFFFFF),
            surface2: const Color(0xFFE9EEF6),
            inset: const Color(0xFFE9EEF6),
            line: const Color(0xFFDDE2EA),
            text: const Color(0xFF1B1B1F),
            text2: const Color(0xFF545766),
            text3: const Color(0xFF6A6D7A),
            accent: a.light,
            accent2: const Color(0xFFD3E3FD),
            avatars: const [Color(0xFFFFDAD6), Color(0xFFD3E3FD), Color(0xFFE3E2EC)],
            danger: const Color(0xFFC0262D),
          );
  }

  @override
  TextStyle font(Palette p, double size, FontWeight w, {double ls = 0, double? h, Color? c}) =>
      GoogleFonts.outfit(fontSize: size, fontWeight: w, letterSpacing: ls, height: h, color: c ?? p.text);

  @override
  TextStyle display(Palette p) => font(p, 28, FontWeight.w600, ls: -.2, h: 1.15);
  @override
  TextStyle headline(Palette p) => font(p, 17, FontWeight.w500, h: 1.3);
  @override
  TextStyle body(Palette p) => font(p, 16.5, FontWeight.w400, h: 1.38);
}

// ---------------------------------------------------------------- Folders

/// Folders: menu button, folder tabs (All / Unread / Groups / People), ticks
/// and times inside bubbles, a dotted chat wallpaper.
class FoldersSkin extends FlatSkin {
  @override
  DesignId get id => DesignId.folders;
  @override
  AppLayout get layout => AppLayout.folders;
  @override
  double get cardR => 14;
  @override
  double get bubbleR => 15;
  @override
  double get tailR => 4;

  @override
  List<AccentChoice> get accents => const [
        AccentChoice('Blue', Color(0xFF2F7BEA), Color(0xFF2F7BEA)),
        AccentChoice('Red', Color(0xFFD2343A), Color(0xFFE5383B)),
        AccentChoice('Steel', Color(0xFF4A6076), Color(0xFF5B7A99)),
      ];

  @override
  Color outgoingBubble(Palette p) => p.accent2;
  @override
  Color outgoingText(Palette p) => p.dark ? const Color(0xFFFFFFFF) : const Color(0xFF0F1722);
  @override
  Color badge(Palette p) => p.dark ? const Color(0xFFE5383B) : const Color(0xFFD2343A);
  @override
  Color onBadge(Palette p) => const Color(0xFFFFFFFF);

  @override
  Palette palette(bool dark, int accent) {
    final a = accents[accent.clamp(0, accents.length - 1)];
    return dark
        ? _pal(
            dark: true,
            bg: const Color(0xFF0F1722),
            surface: const Color(0xFF17212E),
            surface2: const Color(0xFF182533),
            inset: const Color(0xFF1E2A39),
            line: const Color(0xFF1E2A39),
            text: const Color(0xFFF2F5F8),
            text2: const Color(0xFF8A98AA),
            text3: const Color(0xFF7D8B9C),
            accent: a.dark,
            accent2: Color.lerp(a.dark, const Color(0xFF0F1722), .25)!,
            avatars: const [Color(0xFFE5383B), Color(0xFF2F7BEA), Color(0xFF5B6B7F)],
          )
        : _pal(
            dark: false,
            bg: const Color(0xFFFFFFFF),
            surface: const Color(0xFFF1F4F7),
            surface2: const Color(0xFFFFFFFF),
            inset: const Color(0xFFF1F4F7),
            line: const Color(0xFFE3E8ED),
            text: const Color(0xFF0F1722),
            text2: const Color(0xFF5A6878),
            text3: const Color(0xFF66748A),
            accent: a.light,
            accent2: const Color(0xFFD7E8FF),
            avatars: const [Color(0xFFD2343A), Color(0xFF2F7BEA), Color(0xFF66748A)],
            danger: const Color(0xFFD2343A),
          );
  }

  @override
  TextStyle font(Palette p, double size, FontWeight w, {double ls = 0, double? h, Color? c}) =>
      GoogleFonts.rubik(fontSize: size, fontWeight: w, letterSpacing: ls, height: h, color: c ?? p.text);

  @override
  TextStyle display(Palette p) => font(p, 22, FontWeight.w600, h: 1.2);
  @override
  TextStyle body(Palette p) => font(p, 15.5, FontWeight.w400, h: 1.35);
}

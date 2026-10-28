import 'dart:math' as math;

import 'package:flutter/material.dart' show TextField, InputDecoration, InputBorder, TextInputAction;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../skins/skin.dart';
import 'icons.dart';
import 'motion.dart';
import 'scope.dart';

export 'motion.dart' show Haptics;

/// Tap target that scales down slightly and gives a light haptic.
class Pressable extends StatefulWidget {
  final Widget Function(bool pressed) builder;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;
  const Pressable({super.key, required this.builder, this.onTap, this.onLongPress, this.scale = .97, this.haptic = true});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    final sc = context.sc;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: () => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) Haptics.tap();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              _set(false);
              Haptics.hold();
              widget.onLongPress!();
            },
      child: AnimatedScale(
        scale: _down && sc.motion ? widget.scale : 1,
        duration: sc.d(sc.skin.pressDuration),
        curve: Curves.easeOut,
        child: Opacity(opacity: enabled ? 1 : .45, child: widget.builder(_down)),
      ),
    );
  }
}

class SkButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final String? icon;
  final bool expand;
  final bool busy;
  final double height;
  const SkButton(this.label, {super.key, this.onTap, this.primary = true, this.icon, this.expand = false, this.busy = false, this.height = 52});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    final fg = primary ? p.onAccent : p.text;
    final text = label;
    return Pressable(
      onTap: busy ? null : onTap,
      builder: (pressed) => SizedBox(
        height: height,
        width: expand ? double.infinity : null,
        child: skin.buttonFace(
          p,
          primary: primary,
          pressed: pressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Center(
              widthFactor: 1,
              child: busy
                  ? Spinner(color: fg, size: 18)
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      if (icon != null) ...[Ic(icon!, size: 18, color: fg), const SizedBox(width: 8)],
                      Flexible(
                        child: Text(text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: skin.headline(p).copyWith(color: fg, fontSize: 15.5, letterSpacing: 0)),
                      ),
                    ]),
            ),
          ),
        ),
      ),
    );
  }
}

class SkIconButton extends StatelessWidget {
  final String icon;
  final VoidCallback? onTap;
  final double size;
  final Color? color;
  final int badge;
  const SkIconButton(this.icon, {super.key, this.onTap, this.size = 46, this.color, this.badge = 0});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    return Pressable(
      onTap: onTap,
      builder: (pressed) => SizedBox(
        width: size,
        height: size,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: skin.buttonFace(p, primary: false, pressed: pressed, radius: 999, child: Center(child: Ic(icon, size: size * .46, color: color ?? p.text))),
          ),
          if (badge > 0)
            Positioned(right: -2, top: -2, child: CountBadge(badge)),
        ]),
      ),
    );
  }
}

class CountBadge extends StatelessWidget {
  final int n;
  const CountBadge(this.n, {super.key});
  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.accent,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: p.glow, blurRadius: 8)],
      ),
      child: Text(n > 99 ? '99+' : '$n', style: skin.caption(p).copyWith(color: p.onAccent, fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 0)),
    );
  }
}

class SkToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const SkToggle({super.key, required this.value, this.onChanged});
  @override
  Widget build(BuildContext context) => Pressable(
        scale: .94,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        builder: (_) => context.skin.toggle(context.pal, value),
      );
}

class SkSlider extends StatefulWidget {
  final double value; // 0..1
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final int? divisions;
  const SkSlider({super.key, required this.value, required this.onChanged, this.onChangeEnd, this.divisions});
  @override
  State<SkSlider> createState() => _SkSliderState();
}

class _SkSliderState extends State<SkSlider> {
  bool _drag = false;
  double _v = 0;

  void _update(Offset local, double width) {
    var v = (local.dx / width).clamp(0.0, 1.0);
    if (widget.divisions != null && widget.divisions! > 0) {
      v = (v * widget.divisions!).round() / widget.divisions!;
    }
    if (v != _v) {
      _v = v;
      Haptics.tap();
      widget.onChanged(v);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, k) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) {
            setState(() => _drag = true);
            _update(d.localPosition, k.maxWidth);
          },
          onHorizontalDragUpdate: (d) => _update(d.localPosition, k.maxWidth),
          onHorizontalDragEnd: (_) {
            setState(() => _drag = false);
            widget.onChangeEnd?.call(_v);
          },
          onTapDown: (d) {
            _update(d.localPosition, k.maxWidth);
            widget.onChangeEnd?.call(_v);
          },
          child: context.skin.sliderTrack(context.pal, widget.value.clamp(0, 1), dragging: _drag),
        ),
      );
}

class SkSegmented extends StatelessWidget {
  final List<String> options;
  final int index;
  final ValueChanged<int> onChanged;
  final bool expand;
  const SkSegmented({super.key, required this.options, required this.index, required this.onChanged, this.expand = false});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    final items = [
      for (var i = 0; i < options.length; i++)
        Expanded(
          flex: expand ? 1 : 0,
          child: Pressable(
            onTap: () => onChanged(i),
            builder: (_) => skin.selectedFace(
              p,
              selected: i == index,
              radius: 999,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                child: Text(
                  options[i],
                  maxLines: 1,
                  style: skin.callout(p).copyWith(
                        color: i == index ? p.text : p.text2,
                        fontWeight: i == index ? FontWeight.w700 : FontWeight.w500,
                        letterSpacing: 0,
                      ),
                ),
              ),
            ),
          ),
        ),
    ];
    return skin.well(
      p,
      radius: 999,
      padding: const EdgeInsets.all(4),
      child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, children: expand ? items : items.map((e) => e.child).toList()),
    );
  }
}

class SkField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final String? icon;
  final bool obscure;
  final bool autofocus;
  final TextInputType? keyboard;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final Widget? trailing;
  final Widget? leading;
  final FocusNode? focusNode;
  final TextInputAction? action;
  final TextCapitalization capitalization;
  const SkField({
    super.key,
    required this.controller,
    required this.hint,
    this.icon,
    this.obscure = false,
    this.autofocus = false,
    this.keyboard,
    this.onSubmitted,
    this.onChanged,
    this.maxLines = 1,
    this.trailing,
    this.leading,
    this.focusNode,
    this.action,
    this.capitalization = TextCapitalization.none,
  });

  @override
  State<SkField> createState() => _SkFieldState();
}

class _SkFieldState extends State<SkField> {
  late final FocusNode _f = widget.focusNode ?? FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _f.addListener(() => setState(() => _focused = _f.hasFocus));
  }

  @override
  void dispose() {
    if (widget.focusNode == null) _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    return skin.well(
      p,
      focused: _focused,
      radius: widget.maxLines > 1 ? 22 : 999,
      padding: EdgeInsets.only(left: widget.leading != null ? 4 : 16, right: widget.trailing != null ? 4 : 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 50),
        child: Row(children: [
          if (widget.leading != null) widget.leading!,
          if (widget.icon != null) ...[Ic(widget.icon!, size: 19, color: _focused ? p.accent : p.text2), const SizedBox(width: 10)],
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _f,
              autofocus: widget.autofocus,
              obscureText: widget.obscure,
              keyboardType: widget.keyboard,
              textInputAction: widget.action,
              textCapitalization: widget.capitalization,
              onSubmitted: widget.onSubmitted,
              onChanged: widget.onChanged,
              minLines: 1,
              maxLines: widget.obscure ? 1 : widget.maxLines,
              cursorColor: p.accent,
              style: skin.body(p).copyWith(color: p.text),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: skin.body(p).copyWith(color: p.text3),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (widget.trailing != null) widget.trailing!,
        ]),
      ),
    );
  }
}

class SkCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool strong;
  const SkCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.strong = false});
  @override
  Widget build(BuildContext context) => context.skin.surface(context.pal, child: child, padding: padding, strong: strong, reduceEffects: context.settings.reduceMotion);
}

class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(children: [
        Text(skin.sectionLabel(text), style: skin.label(p)),
        const Spacer(),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class SkDivider extends StatelessWidget {
  final double indent;
  const SkDivider({super.key, this.indent = 0});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      margin: EdgeInsets.only(left: indent),
      height: 1,
      color: p.line,
    );
  }
}

/// Coloured square/circle used inside rows.
class IconTile extends StatelessWidget {
  final String icon;
  final double size;
  final Color? color;
  const IconTile(this.icon, {super.key, this.size = 40, this.color});
  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    return SizedBox(
      width: size,
      height: size,
      child: skin.well(p, radius: size * .3, child: Center(child: Ic(icon, size: size * .5, color: color ?? p.accent))),
    );
  }
}

class SettingsRow extends StatelessWidget {
  final String? icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;
  final Color? iconColor;
  final Color? titleColor;
  const SettingsRow({super.key, this.icon, required this.title, this.subtitle, this.trailing, this.onTap, this.chevron = false, this.iconColor, this.titleColor});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        if (icon != null) ...[IconTile(icon!, color: iconColor), const SizedBox(width: 14)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: skin.headline(p).copyWith(fontSize: 15.5, color: titleColor)),
            if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: skin.callout(p))],
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        if (chevron) ...[const SizedBox(width: 6), Ic('chevron', size: 18, color: p.text3)],
      ]),
    );
    if (onTap == null) return row;
    return Pressable(onTap: onTap, scale: .985, builder: (_) => row);
  }
}

/// A card containing rows separated by dividers.
class RowGroup extends StatelessWidget {
  final String? label;
  final List<Widget> children;
  const RowGroup({super.key, this.label, required this.children});
  @override
  Widget build(BuildContext context) {
    final list = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) list.add(const SkDivider(indent: 14));
      list.add(children[i]);
    }
    // min: only as tall as its rows (inside a sheet it used to fill the screen).
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (label != null) SectionLabel(label!),
      SkCard(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(mainAxisSize: MainAxisSize.min, children: list)),
    ]);
  }
}

class StatusChip extends StatelessWidget {
  final String label;
  final String kind; // ok | warn | bad | idle
  const StatusChip(this.label, {super.key, this.kind = 'ok'});
  @override
  Widget build(BuildContext context) => context.skin.chip(context.pal, label: label, color: context.pal.status(kind));
}

class Spinner extends StatefulWidget {
  final Color? color;
  final double size;
  const Spinner({super.key, this.color, this.size = 22});
  @override
  State<Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<Spinner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.pal.accent;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(painter: _SpinPainter(_c.value, color)),
      ),
    );
  }
}

class _SpinPainter extends CustomPainter {
  final double t;
  final Color c;
  _SpinPainter(this.t, this.c);
  @override
  void paint(Canvas canvas, Size s) {
    final paint = Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final r = Offset.zero & s;
    canvas.drawArc(r.deflate(2), t * 2 * math.pi, math.pi * 1.3, false, paint);
  }

  @override
  bool shouldRepaint(_SpinPainter o) => o.t != t;
}

/// Fades/slides children in one after another the first time they appear.
class Stagger extends StatefulWidget {
  final int index;
  final Widget child;
  const Stagger({super.key, required this.index, required this.child});
  @override
  State<Stagger> createState() => _StaggerState();
}

class _StaggerState extends State<Stagger> {
  // Decided once, when the row first appears. If it were re-decided when the
  // row moves (say from 12th to 1st), the row would be rebuilt and fade in again.
  bool? _animate;
  int _delay = 0;

  @override
  Widget build(BuildContext context) {
    // Only the first few rows animate in; rows built later while scrolling just appear.
    if (_animate == null) {
      _animate = context.sc.motion && widget.index < 9;
      _delay = widget.index * 40;
    }
    if (!_animate!) return widget.child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + _delay),
      curve: Interval(_delay / (380 + _delay), 1, curve: Curves.easeOutCubic),
      builder: (_, v, c) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 12 * (1 - v)), child: c)),
      child: widget.child,
    );
  }
}

/// Tiny bar/line chart for latency.
class Sparkline extends StatelessWidget {
  final List<int> values;
  final double height;
  const Sparkline(this.values, {super.key, this.height = 36});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: CustomPaint(painter: _SparkPainter(values, context.pal), size: Size.infinite),
      );
}

class _SparkPainter extends CustomPainter {
  final List<int> v;
  final Palette p;
  _SparkPainter(this.v, this.p);
  @override
  void paint(Canvas canvas, Size s) {
    if (v.isEmpty) return;
    final maxV = v.reduce(math.max).toDouble().clamp(20, 100000);
    final path = Path();
    for (var i = 0; i < v.length; i++) {
      final x = v.length == 1 ? s.width : s.width * i / (v.length - 1);
      final y = s.height - (v[i] / maxV) * (s.height - 4) - 2;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    final fill = Path.from(path)
      ..lineTo(s.width, s.height)
      ..lineTo(0, s.height)
      ..close();
    canvas.drawPath(fill, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [withA(p.accent, .3), withA(p.accent, 0)]).createShader(Offset.zero & s));
    canvas.drawPath(path, Paint()
      ..color = p.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_SparkPainter o) => true;
}

/// Heading text that respects the design's casing.
class Heading extends StatelessWidget {
  final String text;
  final bool large;
  final TextAlign? align;
  const Heading(this.text, {super.key, this.large = true, this.align});
  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    return Text(text, textAlign: align, style: large ? skin.display(p) : skin.title(p));
  }
}

/// Small "// LABEL" eyebrow (HUD) or muted caption (others).
class Eyebrow extends StatelessWidget {
  final String text;
  const Eyebrow(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    return Text(text, style: skin.caption(p).copyWith(fontSize: 12));
  }
}

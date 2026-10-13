import 'package:flutter/widgets.dart';

import '../../skins/skin.dart';
import '../../state/ui_state.dart';
import '../kit/controls.dart';
import '../kit/scope.dart';

class _Tip {
  final String key;
  final String title;
  final String body;
  const _Tip(this.key, this.title, this.body);
}

const _tips = [
  _Tip('nav', 'Switch screens', 'Chats, Groups, your Mac relay and Settings live here. Unfold your phone and this turns into a side rail.'),
  _Tip('search', 'Find anything', 'Search every iMessage and SMS synced from your Mac — names, numbers or words.'),
  _Tip('status', 'Relay status', 'Green means your Mac is online. Tap it to see latency, reconnect, or fix the address.'),
  _Tip('plus', 'Start a chat', 'Message one person or several at once to start a new group.'),
];

/// Spotlight tutorial shown after setup (and from Settings → Show tips again).
class CoachMarks extends StatefulWidget {
  final VoidCallback onDone;
  const CoachMarks({super.key, required this.onDone});
  @override
  State<CoachMarks> createState() => _CoachMarksState();
}

class _CoachMarksState extends State<CoachMarks> {
  int i = 0;
  Rect? rect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    if (!mounted) return;
    // Skip targets that aren't on screen.
    while (i < _tips.length) {
      final ctx = ui.keys[_tips[i].key]?.currentContext;
      final box = ctx?.findRenderObject() as RenderBox?;
      final me = context.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize && me != null) {
        final o = box.localToGlobal(Offset.zero, ancestor: me);
        setState(() => rect = (o & box.size).inflate(8));
        return;
      }
      i++;
    }
    widget.onDone();
  }

  void _next() {
    if (i >= _tips.length - 1) {
      widget.onDone();
      return;
    }
    setState(() => i++);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    final r = rect;
    if (r == null || i >= _tips.length) return const SizedBox.shrink();
    final tip = _tips[i];
    final size = MediaQuery.of(context).size;
    final below = r.center.dy < size.height / 2;
    final radius = skin.upperHeadings ? 4.0 : (r.height / 2).clamp(0, 30).toDouble();
    final cardW = size.width < 520 ? size.width - 40 : 380.0;
    final cardLeft = (r.center.dx - cardW / 2).clamp(20.0, size.width - cardW - 20);
    final dur = context.sc.d(const Duration(milliseconds: 420));

    return Stack(children: [
      // Scrim with a hole, animated between targets.
      Positioned.fill(
        child: GestureDetector(
          onTap: _next,
          child: TweenAnimationBuilder<Rect?>(
            tween: RectTween(end: r),
            duration: dur,
            curve: Curves.easeInOutCubic,
            builder: (_, v, __) => CustomPaint(painter: _ScrimPainter(v ?? r, radius, p.accent, p.glow)),
          ),
        ),
      ),
      AnimatedPositioned(
        duration: dur,
        curve: Curves.easeInOutCubic,
        left: cardLeft,
        top: below ? r.bottom + 18 : null,
        bottom: below ? null : size.height - r.top + 18,
        width: cardW,
        child: TweenAnimationBuilder<double>(
          key: ValueKey(i),
          tween: Tween(begin: 0, end: 1),
          duration: dur,
          curve: Curves.easeOutBack,
          builder: (_, v, c) => Opacity(opacity: v.clamp(0, 1), child: Transform.scale(scale: .9 + .1 * v, child: c)),
          child: skin.surface(
            p,
            strong: true,
            padding: const EdgeInsets.all(18),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(skin.sectionLabel('${i + 1} of ${_tips.length}'), style: skin.label(p)),
                const Spacer(),
                Pressable(onTap: widget.onDone, builder: (_) => Text('Skip tips', style: skin.callout(p))),
              ]),
              const SizedBox(height: 8),
              Heading(tip.title, large: false),
              const SizedBox(height: 6),
              Text(tip.body, style: skin.body(p).copyWith(color: p.text2)),
              const SizedBox(height: 14),
              Row(children: [
                for (var k = 0; k < _tips.length; k++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.only(right: 5),
                    width: k == i ? 22 : 7,
                    height: 7,
                    decoration: BoxDecoration(color: k <= i ? p.accent : withA(p.text3, .4), borderRadius: BorderRadius.circular(skin.upperHeadings ? 1 : 4)),
                  ),
                const Spacer(),
                SkButton(i == _tips.length - 1 ? 'Got it' : 'Next', height: 44, onTap: _next),
              ]),
            ]),
          ),
        ),
      ),
    ]);
  }
}

class _ScrimPainter extends CustomPainter {
  final Rect hole;
  final double radius;
  final Color ring;
  final Color glow;
  _ScrimPainter(this.hole, this.radius, this.ring, this.glow);

  @override
  void paint(Canvas canvas, Size s) {
    final rr = RRect.fromRectAndRadius(hole, Radius.circular(radius));
    final path = Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & s), Path()..addRRect(rr));
    canvas.drawPath(path, Paint()..color = const Color(0xA6000000));
    canvas.drawRRect(rr, Paint()
      ..color = glow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.drawRRect(rr, Paint()
      ..color = ring
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_ScrimPainter o) => o.hole != hole || o.ring != ring;
}

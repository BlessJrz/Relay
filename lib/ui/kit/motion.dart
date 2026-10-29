import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../skins/skin.dart';
import 'scope.dart';

/// One place for vibration, so every screen feels the same.
class Haptics {
  /// Tapping a button or row.
  static void tap() => HapticFeedback.selectionClick();

  /// Something happened: a message sent, a reaction, a reply armed.
  static void confirm() => HapticFeedback.lightImpact();

  /// Holding something down to open its menu, or starting a recording.
  static void hold() => HapticFeedback.mediumImpact();
}

/// A new message growing in at the bottom of the chat. It opens up its own
/// height (so the messages above glide up instead of jumping), fades in and
/// rises slightly from the side it was sent from.
class Arrive extends StatefulWidget {
  final bool animate;
  final bool fromMe;
  final Widget child;
  const Arrive({super.key, required this.animate, required this.fromMe, required this.child});

  @override
  State<Arrive> createState() => _ArriveState();
}

class _ArriveState extends State<Arrive> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  Animation<double>? _a;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null || !widget.animate || !context.sc.motion) return;
    _c = AnimationController(vsync: this, duration: context.sc.d(const Duration(milliseconds: 340)))..forward();
    _a = CurvedAnimation(parent: _c!, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    if (a == null) return widget.child;
    final align = widget.fromMe ? Alignment.bottomRight : Alignment.bottomLeft;
    // Only clipped while it's growing: once it's in, a reaction pill or a
    // swipe icon may poke past the row's edge, like on any other message.
    return AnimatedBuilder(
      animation: a,
      child: FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween(begin: .9, end: 1.0).animate(a),
          alignment: align,
          child: widget.child,
        ),
      ),
      builder: (_, child) => ClipRect(
        clipBehavior: a.isCompleted ? Clip.none : Clip.hardEdge,
        child: Align(alignment: Alignment.bottomCenter, heightFactor: a.value.clamp(0.0, 1.0), child: child),
      ),
    );
  }
}

/// A row in a list that slides to its new place when the list reorders
/// (for example a chat jumping to the top when a message comes in),
/// instead of snapping there.
class Glide extends StatefulWidget {
  final int index;
  final Widget child;
  const Glide({super.key, required this.index, required this.child});

  @override
  State<Glide> createState() => _GlideState();
}

class _GlideState extends State<Glide> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  double _from = 0;

  double get _offset => _from * (1 - Curves.easeOutCubic.transform(_c.value));

  @override
  void didUpdateWidget(covariant Glide old) {
    super.didUpdateWidget(old);
    if (old.index == widget.index || !context.sc.motion) return;
    final box = context.findRenderObject();
    final h = box is RenderBox && box.hasSize ? box.size.height : 0.0;
    if (h <= 0) return;
    // Start from where the row was drawn last frame, capped so a row coming
    // from far away doesn't fly across the whole screen.
    final from = ((old.index - widget.index) * h + (_c.isAnimating ? _offset : 0)).clamp(-640.0, 640.0);
    _from = from;
    _c.duration = context.sc.d(const Duration(milliseconds: 380));
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      // Always the same wrapper, so the row underneath is never rebuilt.
      builder: (_, child) => Transform.translate(offset: Offset(0, _c.isAnimating ? _offset : 0), child: child),
    );
  }
}

/// Page transition for full screens. Most designs slide in from the right
/// edge like on iPhone, while the screen underneath drifts left behind it.
/// Material does what Google Messages does: the new screen is there almost at
/// once (a very quick fade with a small nudge from the right).
class SlideRoute<T> extends PageRouteBuilder<T> {
  final bool quick;
  SlideRoute(WidgetBuilder builder, {required AppScope scope})
      : quick = scope.skin.layout == AppLayout.material,
        super(
          transitionDuration: scope.d(Duration(milliseconds: scope.skin.layout == AppLayout.material ? 190 : 420)),
          reverseTransitionDuration: scope.d(Duration(milliseconds: scope.skin.layout == AppLayout.material ? 150 : 340)),
          pageBuilder: (c, a, s) => ColoredBox(color: scope.p.bg, child: builder(c)),
          transitionsBuilder: scope.skin.layout == AppLayout.material ? _fadeIn : _slideIn,
        );

  static Widget _slideIn(BuildContext c, Animation<double> a, Animation<double> s, Widget child) {
    final cv = CurvedAnimation(parent: a, curve: Curves.easeOutQuart, reverseCurve: Curves.easeOutCubic.flipped);
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(cv),
      child: DecoratedBox(
        decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 18)]),
        child: RepaintBoundary(child: child),
      ),
    );
  }

  static Widget _fadeIn(BuildContext c, Animation<double> a, Animation<double> s, Widget child) {
    final fade = CurvedAnimation(parent: a, curve: Curves.easeOut, reverseCurve: Curves.easeIn);
    final move = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(.06, 0), end: Offset.zero).animate(move),
        child: RepaintBoundary(child: child),
      ),
    );
  }

  @override
  DelegatedTransitionBuilder? get delegatedTransition => quick ? null : _under;

  /// What the screen underneath does while this one slides over it.
  static Widget? _under(BuildContext context, Animation<double> animation, Animation<double> secondary, bool allowSnapshotting, Widget? child) {
    final cv = CurvedAnimation(parent: secondary, curve: Curves.easeOutQuart, reverseCurve: Curves.easeOutCubic.flipped);
    return SlideTransition(
      position: Tween<Offset>(begin: Offset.zero, end: const Offset(-.28, 0)).animate(cv),
      child: child,
    );
  }
}

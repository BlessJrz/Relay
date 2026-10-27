import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../../skins/skin.dart';
import '../../state/video_thumbs.dart';
import '../kit/controls.dart';
import '../kit/icons.dart';
import '../kit/link_text.dart' show openLink;
import '../kit/overlays.dart';
import '../kit/scope.dart';

/// Plays a video full screen inside Relay (streams it from the Mac, or plays
/// a local file for videos you're sending).
Future<void> openVideo(BuildContext context, {String? url, Map<String, String> headers = const {}, String? file, String title = ''}) =>
    pushScreen(context, (c) => VideoScreen(url: url, headers: headers, file: file, title: title));

class VideoScreen extends StatefulWidget {
  final String? url;
  final Map<String, String> headers;
  final String? file;
  final String title;
  const VideoScreen({super.key, this.url, this.headers = const {}, this.file, this.title = ''});
  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  late final VideoPlayerController _c = widget.file != null
      ? VideoPlayerController.file(File(widget.file!))
      : VideoPlayerController.networkUrl(Uri.parse(widget.url!), httpHeaders: widget.headers);
  bool _ready = false;
  String? _error;
  bool _controls = true;
  bool _dragging = false;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _c.addListener(_tick);
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _c.play();
      _scheduleHide();
    }).catchError((Object e) {
      if (mounted) setState(() => _error = '$e');
    });
  }

  void _tick() {
    if (!mounted) return;
    if (_c.value.hasError && _error == null) _error = _c.value.errorDescription ?? 'Playback error';
    setState(() {});
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && _c.value.isPlaying && !_dragging) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  void _playPause() {
    if (!_ready) return;
    if (_c.value.isPlaying) {
      _c.pause();
      _hide?.cancel();
    } else {
      if (_c.value.position >= _c.value.duration) _c.seekTo(Duration.zero);
      _c.play();
      _scheduleHide();
    }
  }

  void _seekTo(double fraction) {
    final d = _c.value.duration;
    if (d == Duration.zero) return;
    _c.seekTo(d * fraction.clamp(0.0, 1.0));
  }

  @override
  void dispose() {
    _hide?.cancel();
    _c.removeListener(_tick);
    _c.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes, s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    final mq = MediaQuery.of(context);
    const white = Color(0xFFFFFFFF);
    final v = _c.value;
    final dur = v.duration;
    final frac = dur.inMilliseconds == 0 ? 0.0 : (v.position.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);

    Widget middle;
    if (_error != null) {
      middle = Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Ic('alert', size: 30, color: p.warning),
          const SizedBox(height: 12),
          Text('This video can’t play inside Relay.', textAlign: TextAlign.center, style: skin.headline(p).copyWith(color: white)),
          const SizedBox(height: 16),
          if (widget.url != null) SkButton('Open in another app', icon: 'external', onTap: () => openLink(widget.url!)),
        ]),
      );
    } else if (!_ready) {
      middle = const Spinner(size: 30, color: white);
    } else {
      middle = AspectRatio(aspectRatio: v.aspectRatio, child: VideoPlayer(_c));
    }

    return ColoredBox(
      color: const Color(0xFF000000),
      child: Stack(fit: StackFit.expand, children: [
        GestureDetector(behavior: HitTestBehavior.opaque, onTap: _toggleControls, onDoubleTap: _playPause, child: Center(child: middle)),
        IgnorePointer(
          ignoring: !_controls,
          child: AnimatedOpacity(
            opacity: _controls ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Stack(children: [
              Positioned(
                top: mq.padding.top + 10,
                left: 14,
                right: 14,
                child: Row(children: [
                  SkIconButton('x', onTap: () => Navigator.of(context).pop()),
                  const SizedBox(width: 12),
                  Expanded(child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: skin.callout(p).copyWith(color: white))),
                  if (widget.url != null) SkIconButton('external', onTap: () => openLink(widget.url!)),
                ]),
              ),
              if (_ready)
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: mq.padding.bottom + 16,
                  child: skin.surface(
                    p,
                    strong: true,
                    padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
                    child: Row(children: [
                      SkIconButton(v.isPlaying ? 'pause' : 'play', size: 44, onTap: _playPause),
                      const SizedBox(width: 10),
                      Text(_fmt(v.position), style: skin.caption(p).copyWith(color: p.text)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (c, k) => GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (d) => _seekTo(d.localPosition.dx / k.maxWidth),
                            onHorizontalDragStart: (_) => setState(() => _dragging = true),
                            onHorizontalDragUpdate: (d) => _seekTo(d.localPosition.dx / k.maxWidth),
                            onHorizontalDragEnd: (_) {
                              setState(() => _dragging = false);
                              _scheduleHide();
                            },
                            child: skin.sliderTrack(p, frac, dragging: _dragging),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(_fmt(dur), style: skin.caption(p).copyWith(color: p.text)),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// The tile shown in a chat for a video, drawn like iMessage: the first
/// frame fills a rounded bubble with a frosted play button in the middle.
class VideoTile extends StatelessWidget {
  final String label;
  final String size;
  final bool outgoing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Future<VideoThumb?>? thumb;
  const VideoTile({super.key, required this.label, required this.size, required this.outgoing, this.onTap, this.onLongPress, this.thumb});

  static String length(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final skin = context.skin, p = context.pal;
    final r = BorderRadius.circular(skin.radius(Surf.bubbleIn));
    return FutureBuilder<VideoThumb?>(
      future: thumb,
      builder: (context, snap) {
        final t = snap.data;
        const w = 230.0;
        final h = t == null ? 160.0 : (w / t.aspect).clamp(130.0, 330.0);
        const white = Color(0xFFFFFFFF);
        return Semantics(
          button: true,
          label: 'Play video${t != null ? ', ${length(t.duration)}' : ''}',
          child: Pressable(
            onTap: onTap,
            onLongPress: onLongPress,
            haptic: false,
            scale: .97,
            builder: (_) => AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: w,
              height: h,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(borderRadius: r, color: p.surface2),
              child: Stack(fit: StackFit.expand, children: [
                if (t != null)
                  Image.file(
                    File(t.path),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    frameBuilder: (c, child, frame, sync) => AnimatedOpacity(opacity: sync || frame != null ? 1 : 0, duration: const Duration(milliseconds: 250), child: child),
                  )
                else if (snap.connectionState != ConnectionState.done)
                  Center(child: Padding(padding: const EdgeInsets.only(top: 90), child: Spinner(size: 16, color: p.text3))),
                Center(
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: withA(const Color(0xFF000000), .28)),
                        child: const Center(child: Padding(padding: EdgeInsets.only(left: 3), child: Ic('play', size: 24, color: white))),
                      ),
                    ),
                  ),
                ),
                if (t != null && t.duration > Duration.zero)
                  Positioned(
                    left: 10,
                    bottom: 8,
                    child: Text(
                      length(t.duration),
                      style: skin.caption(p).copyWith(color: white, fontWeight: FontWeight.w600, shadows: const [Shadow(color: Color(0x99000000), blurRadius: 6)]),
                    ),
                  ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

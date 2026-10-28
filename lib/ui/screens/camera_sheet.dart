import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../../skins/skin.dart';
import '../kit/controls.dart';
import '../kit/icons.dart';
import '../kit/overlays.dart';
import '../kit/scope.dart';

/// Opens the camera with your recent photos underneath (like Google Messages).
/// Returns the files to send, in order, or null if you closed it.
Future<List<File>?> showCameraSheet(BuildContext context) {
  final scope = context.sc;
  return Navigator.of(context).push<List<File>>(PageRouteBuilder<List<File>>(
    transitionDuration: scope.d(const Duration(milliseconds: 380)),
    reverseTransitionDuration: scope.d(const Duration(milliseconds: 260)),
    pageBuilder: (c, a, s) => AppScope(
      settings: scope.settings,
      store: scope.store,
      skin: scope.skin,
      p: scope.p,
      child: const CameraSheet(),
    ),
    transitionsBuilder: (c, a, s, child) {
      final cv = CurvedAnimation(parent: a, curve: Curves.easeOutQuart, reverseCurve: Curves.easeInCubic);
      return SlideTransition(position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(cv), child: child);
    },
  ));
}

const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF000000);

class CameraSheet extends StatefulWidget {
  const CameraSheet({super.key});
  @override
  State<CameraSheet> createState() => _CameraSheetState();
}

class _CameraSheetState extends State<CameraSheet> with WidgetsBindingObserver {
  // ------------------------------------------------ camera
  List<CameraDescription> _cams = const [];
  CameraController? _cam;
  int _camIndex = 0;
  String? _camError;
  FlashMode _flash = FlashMode.off;
  double _minZoom = 1, _maxZoom = 1, _zoom = 1, _zoomAtPinch = 1;
  bool _videoMode = false;
  bool _micOn = true; // false once the microphone was refused: photos still work, videos are silent
  bool _recording = false;
  final _recSecs = ValueNotifier<int>(0);
  Timer? _recTimer;
  Offset? _focusAt; // where you tapped to focus (shown briefly)

  // What you just shot, waiting for Send or Retake.
  XFile? _shot;
  bool _shotIsVideo = false;

  // ------------------------------------------------ recent photos
  bool _galleryAsked = false;
  PermissionState? _galleryPerm;
  AssetPathEntity? _recent;
  final List<AssetEntity> _assets = [];
  bool _loadingMore = false, _noMore = false;
  final List<AssetEntity> _picked = [];
  bool _sending = false;

  final _sheet = DraggableScrollableController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // One permission question at a time: Android can only show one, and a
    // second asked at the same moment can come back as "denied".
    _startCamera().whenComplete(_loadGallery);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recTimer?.cancel();
    _recSecs.dispose();
    _cam?.dispose();
    _sheet.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The camera has to be let go while Relay is in the background. (Not on
    // "inactive": permission pop-ups cause that, and we'd drop the camera
    // while it's starting.)
    if (state == AppLifecycleState.paused) {
      _releasing ??= _releaseCamera().whenComplete(() => _releasing = null);
    } else if (state == AppLifecycleState.resumed && _cam == null && !_opening && _cams.isNotEmpty) {
      _openCamera(_camIndex);
    }
  }

  bool _opening = false;
  Future<void>? _releasing;

  /// Lets go of the camera. A video being recorded is stopped and kept, so
  /// it's waiting in the preview when you come back.
  Future<void> _releaseCamera() async {
    final c = _cam;
    if (c == null) return;
    final wasRecording = _recording;
    _cam = null;
    _recording = false;
    _stopRecordingTimer();
    if (mounted) setState(() {});
    if (wasRecording) {
      try {
        final f = await c.stopVideoRecording();
        if (mounted) {
          setState(() {
            _shot = f;
            _shotIsVideo = true;
          });
        }
      } catch (_) {}
    }
    await c.dispose();
  }

  Future<void> _startCamera() async {
    try {
      _cams = await availableCameras();
      if (_cams.isEmpty) {
        setState(() => _camError = 'No camera found on this phone.');
        return;
      }
      final back = _cams.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      await _openCamera(back < 0 ? 0 : back);
    } catch (e) {
      if (mounted) setState(() => _camError = _cameraMessage(e));
    }
  }

  /// Opens camera [index]. `_camIndex` only changes once it's running.
  Future<void> _openCamera(int index) async {
    if (_opening) return;
    _opening = true;
    try {
      await _releasing;
      // camerax's dispose() shuts down the shared camera, so the old one has
      // to go before the new one starts. Drop it from the screen first so the
      // preview is never built with a disposed controller.
      final old = _cam;
      if (old != null) {
        if (mounted) setState(() => _cam = null);
        await old.dispose();
      }
      while (true) {
        final c = CameraController(_cams[index], ResolutionPreset.veryHigh, enableAudio: _micOn);
        try {
          await c.initialize();
          if (!mounted) {
            await c.dispose();
            return;
          }
          if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused) {
            // Went to the background while starting: let go (and start again if already back).
            await c.dispose();
            if (mounted && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) continue;
            return;
          }
          _minZoom = await c.getMinZoomLevel();
          _maxZoom = await c.getMaxZoomLevel();
          _zoom = 1.clamp(_minZoom, _maxZoom).toDouble();
          await c.setZoomLevel(_zoom);
          await c.setFlashMode(_flash);
          setState(() {
            _cam = c;
            _camIndex = index;
            _camError = null;
          });
          return;
        } catch (e) {
          await c.dispose();
          if (_micOn && e is CameraException && e.code.startsWith('AudioAccess')) {
            // Microphone refused: open it again without sound.
            _micOn = false;
            continue;
          }
          if (mounted) setState(() => _camError = _cameraMessage(e));
          return;
        }
      }
    } finally {
      _opening = false;
    }
  }

  String _cameraMessage(Object e) {
    final s = e is CameraException ? e.code : '$e';
    if (!s.contains('Audio') && (s.contains('Access') || s.contains('ermission'))) return 'Allow the camera for Relay in Android Settings to take photos here.';
    return 'The camera couldn’t start. Close this and try again.';
  }

  Future<void> _flip() async {
    if (_cams.length < 2 || _recording || _opening) return;
    Haptics.tap();
    final want = _cams[_camIndex].lensDirection == CameraLensDirection.back ? CameraLensDirection.front : CameraLensDirection.back;
    final i = _cams.indexWhere((c) => c.lensDirection == want);
    await _openCamera(i >= 0 ? i : (_camIndex + 1) % _cams.length);
  }

  Future<void> _cycleFlash() async {
    final c = _cam;
    if (c == null) return;
    Haptics.tap();
    final next = switch (_flash) { FlashMode.off => FlashMode.auto, FlashMode.auto => FlashMode.always, _ => FlashMode.off };
    try {
      await c.setFlashMode(next);
      setState(() => _flash = next);
    } catch (_) {}
  }

  Future<void> _setZoom(double z) async {
    final c = _cam;
    if (c == null) return;
    z = z.clamp(_minZoom, _maxZoom).toDouble();
    _zoom = z;
    setState(() {});
    try {
      await c.setZoomLevel(z);
    } catch (_) {}
  }

  Future<void> _focus(TapUpDetails d, Size size) async {
    final c = _cam;
    if (c == null) return;
    setState(() => _focusAt = d.localPosition);
    final p = Offset((d.localPosition.dx / size.width).clamp(0, 1), (d.localPosition.dy / size.height).clamp(0, 1));
    try {
      if (c.value.focusPointSupported) await c.setFocusPoint(p);
      if (c.value.exposurePointSupported) await c.setExposurePoint(p);
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) setState(() => _focusAt = null);
  }

  Future<void> _shutter() async {
    final c = _cam;
    if (c == null || !c.value.isInitialized || c.value.isTakingPicture) return;
    if (!_videoMode) {
      Haptics.confirm();
      try {
        final f = await c.takePicture();
        if (mounted) {
          setState(() {
            _shot = f;
            _shotIsVideo = false;
          });
        }
      } catch (e) {
        if (mounted) Toaster.show(context, 'Couldn’t take the photo: $e', icon: 'alert');
      }
      return;
    }
    if (!_recording) {
      Haptics.hold();
      try {
        await c.startVideoRecording();
        _recSecs.value = 0;
        _recTimer = Timer.periodic(const Duration(seconds: 1), (_) => _recSecs.value++);
        setState(() => _recording = true);
      } catch (e) {
        if (mounted) Toaster.show(context, 'Couldn’t start recording: $e', icon: 'alert');
      }
    } else {
      Haptics.confirm();
      try {
        final f = await c.stopVideoRecording();
        _stopRecordingTimer();
        if (mounted) {
          setState(() {
            _recording = false;
            _shot = f;
            _shotIsVideo = true;
          });
        }
      } catch (e) {
        _stopRecordingTimer();
        if (mounted) setState(() => _recording = false);
      }
    }
  }

  void _stopRecordingTimer() {
    _recTimer?.cancel();
    _recTimer = null;
  }

  // ------------------------------------------------ recent photos

  Future<void> _loadGallery({bool ask = true}) async {
    try {
      final perm = ask ? await PhotoManager.requestPermissionExtend() : await PhotoManager.getPermissionState(requestOption: const PermissionRequestOption());
      _galleryAsked = true;
      _galleryPerm = perm;
      if (!perm.hasAccess) {
        if (mounted) setState(() {});
        return;
      }
      final paths = await PhotoManager.getAssetPathList(onlyAll: true, type: RequestType.common);
      _recent = paths.isEmpty ? null : paths.first;
      _assets.clear();
      _noMore = false;
      await _loadMore();
    } catch (_) {
      _galleryAsked = true;
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadMore() async {
    final r = _recent;
    if (r == null || _loadingMore || _noMore) return;
    _loadingMore = true;
    try {
      const size = 90;
      final page = await r.getAssetListPaged(page: _assets.length ~/ size, size: size);
      _assets.addAll(page);
      if (page.length < size) _noMore = true;
    } catch (_) {
      _noMore = true;
    }
    _loadingMore = false;
    if (mounted) setState(() {});
  }

  /// "Select photos" access (Android 14+): pick more for Relay to see.
  Future<void> _chooseMore() async {
    try {
      await PhotoManager.presentLimited(type: RequestType.common);
    } catch (_) {}
    await _loadGallery(ask: false);
  }

  void _toggle(AssetEntity a) {
    Haptics.tap();
    setState(() => _picked.contains(a) ? _picked.remove(a) : _picked.add(a));
  }

  Future<void> _sendPicked() async {
    if (_picked.isEmpty || _sending) return;
    setState(() => _sending = true);
    final files = <File>[];
    var unreadable = 0;
    try {
      for (final a in List.of(_picked)) {
        try {
          final f = await a.file;
          if (f == null) {
            unreadable++;
          } else {
            files.add(f);
          }
        } catch (_) {
          unreadable++;
        }
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    if (!mounted) return;
    if (files.isEmpty) {
      Toaster.show(context, 'Those photos aren’t on the phone yet (still in the cloud?).', icon: 'alert');
      return;
    }
    if (unreadable > 0) Toaster.show(context, '$unreadable couldn’t be read, so ${unreadable == 1 ? 'it wasn’t' : 'they weren’t'} sent.', icon: 'alert');
    Haptics.confirm();
    Navigator.of(context).pop(files);
  }

  void _sendShot() {
    final s = _shot;
    if (s == null) return;
    Haptics.confirm();
    Navigator.of(context).pop([File(s.path)]);
  }

  /// The phone's own full picker, for older photos, albums and files.
  Future<void> _allPhotos() async {
    try {
      final picked = await ImagePicker().pickMultipleMedia(imageQuality: 90);
      if (picked.isEmpty || !mounted) return;
      Navigator.of(context).pop(picked.map((x) => File(x.path)).toList());
    } catch (e) {
      if (mounted) Toaster.show(context, 'Couldn’t open your photos: $e', icon: 'alert');
    }
  }

  // ------------------------------------------------ layout

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final pad = mq.padding;
    final h = mq.size.height;
    // The camera takes the top ~57%; the photo sheet starts just below it
    // (drag it up to see more photos).
    final camH = h * .57;
    final sheetStart = ((h - camH - 10) / h).clamp(.3, .6).toDouble();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: PopScope(
        canPop: _shot == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _shot != null) setState(() => _shot = null);
        },
        child: ColoredBox(
          color: _black,
          child: Stack(children: [
            Positioned(left: 0, right: 0, top: 0, height: camH, child: _cameraArea(pad.top)),
            DraggableScrollableSheet(
              controller: _sheet,
              initialChildSize: sheetStart,
              minChildSize: sheetStart,
              maxChildSize: 1,
              snap: true,
              snapSizes: [sheetStart, 1],
              builder: (context, scroll) => _galleryArea(scroll, pad),
            ),
            if (_shot != null) Positioned.fill(child: _ShotPreview(shot: _shot!, video: _shotIsVideo, onRetake: () => setState(() => _shot = null), onSend: _sendShot)),
          ]),
        ),
      ),
    );
  }

  Widget _cameraArea(double topPad) {
    final c = _cam;
    final ready = c != null && c.value.isInitialized;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      child: LayoutBuilder(builder: (context, k) {
        final size = Size(k.maxWidth, k.maxHeight);
        return Stack(fit: StackFit.expand, children: [
          if (ready)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _focus(d, size),
              onScaleStart: (_) => _zoomAtPinch = _zoom,
              onScaleUpdate: (d) {
                if (d.pointerCount > 1) _setZoom(_zoomAtPinch * d.scale);
              },
              child: _Preview(controller: c),
            )
          else
            Container(
              color: const Color(0xFF111114),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(32),
              child: _camError == null
                  ? const Spinner(color: _white)
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_camError!, textAlign: TextAlign.center, style: const TextStyle(color: _white, fontSize: 15)),
                      const SizedBox(height: 14),
                      Pressable(
                        onTap: () => PhotoManager.openSetting(),
                        builder: (_) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(99)),
                          child: const Text('Open settings', style: TextStyle(color: _white, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ]),
            ),
          if (_focusAt != null)
            Positioned(
              left: _focusAt!.dx - 32,
              top: _focusAt!.dy - 32,
              child: IgnorePointer(
                child: Container(width: 64, height: 64, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _white, width: 1.5))),
              ),
            ),
          // Top bar: close, recording time, flash.
          Positioned(
            left: 8,
            right: 8,
            top: topPad + 4,
            child: Row(children: [
              _RoundIcon('x', label: 'Close', onTap: () => Navigator.of(context).maybePop()),
              const Spacer(),
              if (_recording)
                ValueListenableBuilder<int>(
                  valueListenable: _recSecs,
                  builder: (_, s, __) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: const Color(0xFFE5383B), borderRadius: BorderRadius.circular(99)),
                    child: Text('${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}', style: const TextStyle(color: _white, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
                  ),
                ),
              const Spacer(),
              _RoundIcon(
                _flash == FlashMode.off ? 'boltoff' : 'bolt',
                label: switch (_flash) { FlashMode.off => 'Flash off', FlashMode.auto => 'Flash auto', _ => 'Flash on' },
                badge: _flash == FlashMode.auto ? 'A' : null,
                onTap: ready ? _cycleFlash : null,
              ),
            ]),
          ),
          // Bottom: zoom, shutter, flip, photo/video.
          Positioned(
            left: 0,
            right: 0,
            bottom: 18,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (ready && _zoomStops().length > 1) ...[_zoomBar(), const SizedBox(height: 18)],
              SizedBox(
                height: 84,
                child: Row(children: [
                  const Expanded(child: SizedBox()),
                  _Shutter(video: _videoMode, recording: _recording, onTap: ready ? _shutter : null),
                  Expanded(
                    child: Center(
                      child: _cams.length > 1 && !_recording
                          ? Semantics(
                              button: true,
                              label: 'Switch camera',
                              child: Pressable(
                                haptic: false,
                                onTap: _flip,
                                builder: (_) => Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _white, width: 2.5), color: const Color(0x33000000)),
                                  child: const Center(child: Ic('refresh', size: 26, color: _white)),
                                ),
                              ),
                            )
                          : const SizedBox(),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              if (!_recording) _modeSwitch() else const SizedBox(height: 40),
            ]),
          ),
        ]);
      }),
    );
  }

  List<double> _zoomStops() => [
        if (_minZoom < .95) _minZoom,
        1.0,
        if (_maxZoom >= 2) 2.0,
        if (_maxZoom >= 5) 5.0,
      ];

  Widget _zoomBar() {
    final stops = _zoomStops();
    // The stop you're closest to is highlighted.
    var near = stops.first;
    for (final s in stops) {
      if ((s - _zoom).abs() < (near - _zoom).abs()) near = s;
    }
    String label(double s) => s == near && (_zoom - s).abs() > .05 ? '${_zoom.toStringAsFixed(1)}×' : (s >= 1 ? s.toStringAsFixed(s % 1 == 0 ? 0 : 1) : s.toStringAsFixed(1));
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: const Color(0x55000000), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final s in stops)
          Pressable(
            onTap: () => _setZoom(s),
            builder: (_) => AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 46,
              height: 46,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(shape: BoxShape.circle, color: s == near ? const Color(0xFFD9DCEC) : const Color(0x33FFFFFF)),
              alignment: Alignment.center,
              child: Text(label(s), style: TextStyle(color: s == near ? _black : _white, fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
      ]),
    );
  }

  Widget _modeSwitch() {
    Widget item(String text, bool on, VoidCallback onTap) => Pressable(
          onTap: onTap,
          builder: (_) => AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
            decoration: BoxDecoration(color: on ? const Color(0xFFD9DCEC) : const Color(0x00000000), borderRadius: BorderRadius.circular(99)),
            child: Text(text, style: TextStyle(color: on ? _black : _white, fontSize: 16, fontWeight: FontWeight.w500)),
          ),
        );
    return SizedBox(
      height: 40,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        item('Photo', !_videoMode, () => setState(() => _videoMode = false)),
        const SizedBox(width: 10),
        item('Video', _videoMode, () {
          if (!_micOn && !_videoMode) {
            Toaster.show(context, 'Videos will have no sound. Allow the microphone for Relay in Android Settings.', title: 'Microphone is off for Relay', icon: 'mic');
          }
          setState(() => _videoMode = true);
        }),
      ]),
    );
  }

  Widget _galleryArea(ScrollController scroll, EdgeInsets pad) {
    final skin = context.skin, p = context.pal;
    final sheetColor = p.dark ? const Color(0xFF1C1C1F) : p.surface;
    final cols = (MediaQuery.sizeOf(context).width / 130).floor().clamp(3, 8);
    final noAccess = _galleryAsked && !(_galleryPerm?.hasAccess ?? false);

    return Container(
      decoration: BoxDecoration(color: sheetColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.extentAfter < 600) _loadMore();
            return false;
          },
          child: CustomScrollView(
            controller: scroll,
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 44,
                  child: Stack(children: [
                    Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: p.text3, borderRadius: BorderRadius.circular(9)))),
                    if (_galleryPerm == PermissionState.limited)
                      Positioned(
                        left: 6,
                        top: 0,
                        bottom: 0,
                        child: Pressable(
                          onTap: _chooseMore,
                          builder: (_) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Center(child: Text('Choose more', style: skin.callout(p).copyWith(color: p.accent, fontWeight: FontWeight.w600))),
                          ),
                        ),
                      ),
                    Positioned(
                      right: 6,
                      top: 0,
                      bottom: 0,
                      child: Pressable(
                        onTap: _allPhotos,
                        builder: (_) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Center(child: Text('All photos', style: skin.callout(p).copyWith(color: p.accent, fontWeight: FontWeight.w600))),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
              if (noAccess)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                    child: Column(children: [
                      Ic('image', size: 30, color: p.text2),
                      const SizedBox(height: 12),
                      Text('Let Relay see your photos to pick them here.', textAlign: TextAlign.center, style: skin.callout(p)),
                      const SizedBox(height: 14),
                      SizedBox(width: 200, child: SkButton('Allow photos', icon: 'image', onTap: () async {
                        await PhotoManager.openSetting();
                      })),
                      const SizedBox(height: 8),
                      Pressable(
                        onTap: () => _loadGallery(),
                        builder: (_) => Padding(padding: const EdgeInsets.all(8), child: Text('I’ve allowed it — reload', style: skin.caption(p).copyWith(color: p.accent))),
                      ),
                    ]),
                  ),
                )
              else if (!_galleryAsked || (_assets.isEmpty && _loadingMore))
                const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Center(child: Spinner())))
              else if (_assets.isEmpty)
                SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(40), child: Center(child: Text('No photos yet.', style: skin.callout(p)))))
              else
                SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 2, crossAxisSpacing: 2),
                  delegate: SliverChildBuilderDelegate(
                    (c, i) {
                      final a = _assets[i];
                      final n = _picked.indexOf(a);
                      return _Thumb(key: ValueKey(a.id), asset: a, number: n < 0 ? null : n + 1, onTap: () => _toggle(a));
                    },
                    childCount: _assets.length,
                  ),
                ),
              SliverToBoxAdapter(child: SizedBox(height: pad.bottom + (_picked.isEmpty ? 16 : 96))),
            ],
          ),
        ),
        // Send bar slides up once something is picked.
        AnimatedPositioned(
          duration: context.sc.d(const Duration(milliseconds: 260)),
          curve: Curves.easeOutCubic,
          left: 16,
          right: 16,
          bottom: _picked.isEmpty ? -90 : pad.bottom + 16,
          child: Center(
            child: Semantics(
              button: true,
              label: 'Send ${_picked.length}',
              child: Pressable(
                haptic: false,
                onTap: _sendPicked,
                builder: (_) => Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 26),
                  decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(99), boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 18, offset: Offset(0, 6))]),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_sending) Spinner(size: 18, color: p.onAccent) else Ic('send', size: 20, color: p.onAccent),
                    const SizedBox(width: 10),
                    Text('Send ${_picked.length}', style: skin.headline(p).copyWith(color: p.onAccent)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// The live camera, filling its box without stretching.
class _Preview extends StatelessWidget {
  final CameraController controller;
  const _Preview({required this.controller});
  @override
  Widget build(BuildContext context) {
    final s = controller.value.previewSize;
    if (s == null) return CameraPreview(controller);
    // previewSize is reported sideways (landscape) on phones.
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(width: s.shortestSide, height: s.longestSide, child: CameraPreview(controller)),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final String icon;
  final String label;
  final String? badge;
  final VoidCallback? onTap;
  const _RoundIcon(this.icon, {required this.label, this.badge, this.onTap});
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        onTap: onTap,
        builder: (_) => SizedBox(
          width: 52,
          height: 52,
          child: Stack(alignment: Alignment.center, children: [
            Ic(icon, size: 28, color: _white),
            if (badge != null) Positioned(right: 8, bottom: 10, child: Text(badge!, style: const TextStyle(color: _white, fontSize: 11, fontWeight: FontWeight.w800))),
          ]),
        ),
      ),
    );
  }
}

class _Shutter extends StatelessWidget {
  final bool video;
  final bool recording;
  final VoidCallback? onTap;
  const _Shutter({required this.video, required this.recording, this.onTap});
  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFE5383B);
    return Semantics(
      button: true,
      label: video ? (recording ? 'Stop recording' : 'Start recording') : 'Take photo',
      child: Pressable(
        haptic: false,
        scale: .92,
        onTap: onTap,
        builder: (_) => Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _white, width: 5)),
          alignment: Alignment.center,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: recording ? 30 : 64,
            height: recording ? 30 : 64,
            decoration: BoxDecoration(
              color: video ? red : _white,
              borderRadius: BorderRadius.circular(recording ? 8 : 32),
            ),
          ),
        ),
      ),
    );
  }
}

/// One photo or video in the grid. Thumbnails are small and cached, so the
/// grid scrolls smoothly.
class _Thumb extends StatefulWidget {
  final AssetEntity asset;
  final int? number;
  final VoidCallback onTap;
  const _Thumb({super.key, required this.asset, required this.number, required this.onTap});
  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
  // The last ~300 thumbnails, oldest first (a Dart map keeps insertion order).
  static final Map<String, Future<Uint8List?>> _cache = {};
  static const _cacheMax = 300;
  late final Future<Uint8List?> _data = _thumb(widget.asset);

  static Future<Uint8List?> _thumb(AssetEntity a) {
    final f = _cache.remove(a.id) ?? a.thumbnailDataWithSize(const ThumbnailSize.square(260), quality: 82);
    _cache[a.id] = f; // now the newest
    while (_cache.length > _cacheMax) {
      _cache.remove(_cache.keys.first);
    }
    return f;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal, skin = context.skin;
    final a = widget.asset;
    final picked = widget.number != null;
    final secs = a.type == AssetType.video ? a.videoDuration.inSeconds : null;
    return Pressable(
      haptic: false,
      scale: .95,
      onTap: widget.onTap,
      builder: (_) => Stack(fit: StackFit.expand, children: [
        ColoredBox(
          color: p.inset,
          child: FutureBuilder<Uint8List?>(
            future: _data,
            builder: (c, s) => s.data == null
                ? const SizedBox()
                : TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 180),
                    builder: (_, v, child) => Opacity(opacity: v, child: child),
                    child: Image.memory(s.data!, fit: BoxFit.cover, gaplessPlayback: true),
                  ),
          ),
        ),
        if (picked) DecoratedBox(decoration: BoxDecoration(border: Border.all(color: p.accent, width: 3), color: withA(p.accent, .18))),
        if (secs != null)
          Positioned(
            left: 6,
            bottom: 5,
            child: Text('${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}',
                style: const TextStyle(color: _white, fontSize: 12, fontWeight: FontWeight.w600, shadows: [Shadow(color: Color(0x99000000), blurRadius: 4)])),
          ),
        Positioned(
          right: 6,
          top: 6,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: picked ? p.accent : const Color(0x33000000),
              border: Border.all(color: _white, width: 1.6),
            ),
            alignment: Alignment.center,
            child: picked ? Text('${widget.number}', style: skin.caption(p).copyWith(color: p.onAccent, fontSize: 12, fontWeight: FontWeight.w700)) : null,
          ),
        ),
      ]),
    );
  }
}

/// What you just shot, full screen, with Retake and Send.
class _ShotPreview extends StatefulWidget {
  final XFile shot;
  final bool video;
  final VoidCallback onRetake;
  final VoidCallback onSend;
  const _ShotPreview({required this.shot, required this.video, required this.onRetake, required this.onSend});
  @override
  State<_ShotPreview> createState() => _ShotPreviewState();
}

class _ShotPreviewState extends State<_ShotPreview> {
  VideoPlayerController? _v;

  @override
  void initState() {
    super.initState();
    if (widget.video) {
      _v = VideoPlayerController.file(File(widget.shot.path))
        ..setLooping(true)
        ..initialize().then((_) {
          if (mounted) {
            setState(() {});
            _v?.play();
          }
        });
    }
  }

  @override
  void dispose() {
    _v?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal, skin = context.skin;
    final pad = MediaQuery.paddingOf(context);
    final v = _v;
    final media = widget.video
        ? (v != null && v.value.isInitialized
            ? Center(child: AspectRatio(aspectRatio: v.value.aspectRatio, child: VideoPlayer(v)))
            : const Center(child: Spinner(color: _white)))
        : Image.file(File(widget.shot.path), fit: BoxFit.contain, cacheWidth: (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).round());
    return ColoredBox(
      color: _black,
      child: Stack(children: [
        Positioned.fill(child: media),
        Positioned(
          left: 20,
          right: 20,
          bottom: pad.bottom + 24,
          child: Row(children: [
            Pressable(
              onTap: widget.onRetake,
              builder: (_) => Container(
                height: 54,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(99)),
                alignment: Alignment.center,
                child: const Text('Retake', style: TextStyle(color: _white, fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            const Spacer(),
            Semantics(
              button: true,
              label: 'Send',
              child: Pressable(
                haptic: false,
                onTap: widget.onSend,
                builder: (_) => Container(
                  height: 58,
                  padding: const EdgeInsets.symmetric(horizontal: 26),
                  decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(99)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Ic('send', size: 20, color: p.onAccent),
                    const SizedBox(width: 10),
                    Text('Send', style: skin.headline(p).copyWith(color: p.onAccent)),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

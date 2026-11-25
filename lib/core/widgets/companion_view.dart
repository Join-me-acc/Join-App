import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Short reactions, followed by a quiet idle. A changed [CompanionView.reaction]
/// replays a gesture without replacing the widget or its decoded images.
enum CompanionMotion { idle, greet, thinking, nod, celebrate }

/// Articulates the original illustrations with a small textured mesh. Each
/// companion has its own landmarks, eyelids and gestures; feet stay planted.
class CompanionView extends StatefulWidget {
  final String asset;
  final double? width;
  final double? height;
  final bool portrait;
  final bool animationsEnabled;
  final CompanionMotion motion;
  final int reaction;

  const CompanionView({
    super.key,
    required this.asset,
    this.width,
    this.height,
    this.portrait = false,
    this.animationsEnabled = true,
    this.motion = CompanionMotion.idle,
    this.reaction = 0,
  });

  @override
  State<CompanionView> createState() => _CompanionViewState();
}

class _CompanionViewState extends State<CompanionView>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _idle;
  late final AnimationController _gesture;
  late final Listenable _repaint;
  ImageStream? _imageStream;
  ImageStream? _blinkStream;
  ImageStreamListener? _imageListener;
  ImageStreamListener? _blinkListener;
  ImageInfo? _image;
  ImageInfo? _blink;
  _CompanionMesh? _mesh;
  int _imageGeneration = 0;
  bool _running = false;
  bool _foreground = true;
  bool _reducedMotion = false;
  bool _tickerEnabled = true;
  bool _pendingGesture = true;

  _CompanionRig? get _rig => _CompanionRig.forAsset(widget.asset);
  bool get _usesGif =>
      widget.asset == 'assets/images/mascota/DRAGO.png' &&
      !widget.portrait &&
      widget.animationsEnabled &&
      !_reducedMotion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _idle =
        AnimationController(vsync: this, duration: const Duration(seconds: 13));
    _gesture = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    );
    _repaint = Listenable.merge([_idle, _gesture]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    if (_rig != null && _imageStream == null) _loadImages();
    _syncPlayback();
  }

  void _loadImages() {
    final rig = _rig!;
    final generation = _imageGeneration;
    final configuration = createLocalImageConfiguration(context);
    // Shared ImageCache keys across instances; no full-size PNG per avatar.
    _imageStream = ResizeImage(AssetImage(widget.asset), width: 640)
        .resolve(configuration);
    _imageListener = ImageStreamListener((info, synchronousCall) {
      if (!mounted || generation != _imageGeneration) {
        info.dispose();
        return;
      }
      void accept() {
        _image?.dispose();
        _image = info;
        _mesh = _CompanionMesh(info.image, rig);
      }

      if (synchronousCall) {
        accept();
      } else {
        setState(accept);
      }
    });
    _imageStream!.addListener(_imageListener!);
    _blinkStream =
        ResizeImage(AssetImage(rig.eyelids), width: 640).resolve(configuration);
    _blinkListener = ImageStreamListener((info, synchronousCall) {
      if (!mounted || generation != _imageGeneration) {
        info.dispose();
        return;
      }
      void accept() {
        _blink?.dispose();
        _blink = info;
      }

      if (synchronousCall) {
        accept();
      } else {
        setState(accept);
      }
    }, onError: (Object error, StackTrace? stack) {
      // The original illustration remains usable if an optional eyelid fails.
      debugPrint('Companion eyelids unavailable: $error');
    });
    _blinkStream!.addListener(_blinkListener!);
  }

  @override
  void didUpdateWidget(CompanionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset != widget.asset) {
      _releaseImages();
      if (_rig != null) _loadImages();
      _idle.value = 0;
      _pendingGesture = true;
    }
    if (oldWidget.motion != widget.motion ||
        oldWidget.reaction != widget.reaction ||
        (!oldWidget.animationsEnabled && widget.animationsEnabled)) {
      _pendingGesture = true;
    }
    _syncPlayback();
  }

  void _syncPlayback() {
    final run = _rig != null &&
        !_usesGif &&
        widget.animationsEnabled &&
        !_reducedMotion &&
        _tickerEnabled &&
        _foreground;
    if (run != _running) {
      _running = run;
      if (run) {
        _idle.repeat();
        if (!_pendingGesture && _gesture.value > 0 && _gesture.value < 1) {
          _gesture.forward();
        }
      } else {
        _idle.stop();
        _gesture.stop();
      }
    }
    if (run && _pendingGesture) {
      _pendingGesture = false;
      _gesture.forward(from: 0);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncPlayback();
    if (_usesGif) setState(() {});
  }

  void _releaseImages() {
    _imageGeneration++;
    if (_imageListener != null) _imageStream?.removeListener(_imageListener!);
    if (_blinkListener != null) _blinkStream?.removeListener(_blinkListener!);
    _imageStream = null;
    _blinkStream = null;
    _image?.dispose();
    _blink?.dispose();
    _image = null;
    _blink = null;
    _mesh = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _releaseImages();
    _idle.dispose();
    _gesture.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_usesGif) {
      return RepaintBoundary(
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: AspectRatio(
            aspectRatio: 2 / 3,
            child: ExcludeSemantics(
              child: TickerMode(
                enabled: _tickerEnabled && _foreground,
                child: Image.asset(
                  'assets/images/mascota/animado/DRAGO',
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) =>
                      Image.asset(widget.asset, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
        ),
      );
    }
    final image = _image?.image;
    final child = _rig != null && image != null && _mesh != null
        ? CustomPaint(
            painter: _CompanionPainter(
              image: image,
              blink: _blink?.image,
              mesh: _mesh!,
              idle: _idle,
              gesture: _gesture,
              repaint: _repaint,
              motion: widget.motion,
              portrait: widget.portrait,
              enabled: widget.animationsEnabled && !_reducedMotion,
            ),
          )
        : Image.asset(widget.asset, fit: BoxFit.contain, cacheWidth: 640);
    return RepaintBoundary(
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: AspectRatio(
          aspectRatio: widget.portrait ? 1 : 2 / 3,
          child: ExcludeSemantics(child: child),
        ),
      ),
    );
  }
}

double _smooth(double start, double end, double value) {
  final t = ((value - start) / (end - start)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

enum _CompanionKind { eli, drago, halo }

/// Landmarks use the original PNG coordinates, not the decoded cache size.
/// The meshes share an implementation, but never another character's anatomy.
class _CompanionRig {
  final _CompanionKind kind;
  final String eyelids;
  final Size reference;
  final Rect portrait;
  final Rect fullBody;
  final Offset headPivot;
  final Offset handPivot;
  final Offset? otherHandPivot;
  final Rect leftEye;
  final Rect rightEye;
  final double headFadeStart;
  final double headFadeEnd;
  final double breathFadeStart;
  final double breathFadeEnd;
  final double tailBaseY;
  final double greetingTilt;
  final double handSwing;
  final double greetingNod;

  const _CompanionRig({
    required this.kind,
    required this.eyelids,
    required this.reference,
    required this.portrait,
    required this.fullBody,
    required this.headPivot,
    required this.handPivot,
    this.otherHandPivot,
    required this.leftEye,
    required this.rightEye,
    required this.headFadeStart,
    required this.headFadeEnd,
    required this.breathFadeStart,
    required this.breathFadeEnd,
    required this.tailBaseY,
    required this.greetingTilt,
    required this.handSwing,
    this.greetingNod = 0,
  });

  static _CompanionRig? forAsset(String asset) => switch (asset) {
        'assets/images/mascota/ELI.png' => eli,
        'assets/images/mascota/DRAGO.png' => drago,
        'assets/images/mascota/HALO.png' => halo,
        _ => null,
      };

  static const eli = _CompanionRig(
    kind: _CompanionKind.eli,
    eyelids: 'assets/images/mascota/ELI-blink.png',
    reference: Size(1024, 1536),
    portrait: Rect.fromLTWH(35, 10, 675, 675),
    fullBody: Rect.fromLTWH(-40, -24, 1104, 1584),
    headPivot: Offset(385, 615),
    handPivot: Offset(760, 666),
    leftEye: Rect.fromLTWH(65, 239, 184, 236),
    rightEye: Rect.fromLTWH(410, 143, 224, 260),
    headFadeStart: 570,
    headFadeEnd: 750,
    breathFadeStart: 1050,
    breathFadeEnd: 1400,
    tailBaseY: 1380,
    greetingTilt: -.045,
    handSwing: .18,
  );

  static const drago = _CompanionRig(
    kind: _CompanionKind.drago,
    eyelids: 'assets/images/mascota/DRAGO-blink.png',
    reference: Size(1268, 1977),
    portrait: Rect.fromLTWH(375, 30, 790, 790),
    fullBody: Rect.fromLTWH(-50, -30, 1368, 2037),
    headPivot: Offset(785, 735),
    handPivot: Offset(1060, 1120),
    leftEye: Rect.fromLTWH(463, 213, 266, 264),
    rightEye: Rect.fromLTWH(916, 213, 200, 266),
    headFadeStart: 650,
    headFadeEnd: 865,
    breathFadeStart: 1430,
    breathFadeEnd: 1690,
    tailBaseY: 1640,
    greetingTilt: -.034,
    handSwing: .13,
    greetingNod: 6,
  );

  static const halo = _CompanionRig(
    kind: _CompanionKind.halo,
    eyelids: 'assets/images/mascota/HALO-blink.png',
    reference: Size(1268, 2167),
    portrait: Rect.fromLTWH(280, 10, 865, 865),
    fullBody: Rect.fromLTWH(-50, -32, 1368, 2231),
    headPivot: Offset(755, 810),
    handPivot: Offset(485, 1390),
    otherHandPivot: Offset(1030, 1400),
    leftEye: Rect.fromLTWH(382, 326, 304, 280),
    rightEye: Rect.fromLTWH(905, 296, 184, 264),
    headFadeStart: 700,
    headFadeEnd: 1030,
    breathFadeStart: 1570,
    breathFadeEnd: 1880,
    tailBaseY: 1830,
    greetingTilt: .045,
    handSwing: .045,
    greetingNod: 16,
  );

  double headWeight(double x, double y) =>
      (1 - _smooth(headFadeStart, headFadeEnd, y)) *
      (kind == _CompanionKind.eli ? 1 - _smooth(640, 735, x) : 1);

  double handWeight(double x, double y) => switch (kind) {
        _CompanionKind.eli => _smooth(660, 840, x) * (1 - _smooth(630, 790, y)),
        _CompanionKind.drago => _smooth(985, 1100, x) *
            _smooth(735, 825, y) *
            (1 - _smooth(1030, 1190, y)),
        _CompanionKind.halo =>
          _ovalWeight(x, y, const Rect.fromLTWH(380, 1110, 310, 330)),
      };

  double otherHandWeight(double x, double y) => kind == _CompanionKind.halo
      ? _ovalWeight(x, y, const Rect.fromLTWH(880, 1080, 260, 330))
      : 0;

  double tailWeight(double x, double y) => switch (kind) {
        _CompanionKind.eli => _smooth(660, 920, x) * _smooth(1110, 1270, y),
        _CompanionKind.drago => (1 - _smooth(230, 555, x)) *
            _smooth(1200, 1320, y) *
            (1 - _smooth(1690, 1770, y)),
        _CompanionKind.halo => (1 - _smooth(215, 390, x)) *
            _smooth(1510, 1600, y) *
            (1 - _smooth(1880, 1970, y)),
      };
}

double _ovalWeight(double x, double y, Rect oval) {
  final dx = (x - oval.center.dx) / (oval.width / 2);
  final dy = (y - oval.center.dy) / (oval.height / 2);
  return 1 - _smooth(.78, 1.12, math.sqrt(dx * dx + dy * dy));
}

/// Skinning weights are calculated once, not on every repaint.
class _CompanionMesh {
  static const columns = 48;
  static const rows = 72;
  static const count = (columns + 1) * (rows + 1);
  final positions = Float32List(count * 2);
  final texture = Float32List(count * 2);
  final blinkTexture = Float32List(count * 2);
  final indices = Uint16List(columns * rows * 6);
  final head = Float32List(count);
  final hand = Float32List(count);
  final otherHand = Float32List(count);
  final tail = Float32List(count);
  final breath = Float32List(count);
  final eyeMask = Float32List(count);
  final colors = Int32List(count);
  final _CompanionRig rig;

  _CompanionMesh(ui.Image image, this.rig) {
    for (var row = 0; row <= rows; row++) {
      for (var col = 0; col <= columns; col++) {
        final i = row * (columns + 1) + col;
        final x = col / columns * rig.reference.width;
        final y = row / rows * rig.reference.height;
        texture[i * 2] = col / columns * image.width;
        texture[i * 2 + 1] = row / rows * image.height;
        head[i] = rig.headWeight(x, y);
        hand[i] = rig.handWeight(x, y);
        otherHand[i] = rig.otherHandWeight(x, y);
        tail[i] = rig.tailWeight(x, y);
        breath[i] = 1 - _smooth(rig.breathFadeStart, rig.breathFadeEnd, y);
        final left = _ovalWeight(x, y, rig.leftEye);
        final right = _ovalWeight(x, y, rig.rightEye);
        eyeMask[i] = math.max(left, right);
      }
    }
    var index = 0;
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < columns; col++) {
        final a = row * (columns + 1) + col;
        final b = a + columns + 1;
        for (final v in [a, b, a + 1, a + 1, b, b + 1]) {
          indices[index++] = v;
        }
      }
    }
  }

  void update(double headAngle, double handAngle, double breathing, double nod,
      double tailAngle) {
    final hc = math.cos(headAngle), hs = math.sin(headAngle);
    final ac = math.cos(handAngle), ass = math.sin(handAngle);
    final bc = math.cos(-handAngle * .7), bs = math.sin(-handAngle * .7);
    final secondPivot = rig.otherHandPivot ?? Offset.zero;
    for (var row = 0; row <= rows; row++) {
      for (var col = 0; col <= columns; col++) {
        final i = row * (columns + 1) + col;
        final x = col / columns * rig.reference.width;
        final y = row / rows * rig.reference.height;
        final hx = x - rig.headPivot.dx, hy = y - rig.headPivot.dy;
        final ax = x - rig.handPivot.dx, ay = y - rig.handPivot.dy;
        final bx = x - secondPivot.dx, by = y - secondPivot.dy;
        positions[i * 2] = x +
            head[i] * (hx * hc - hy * hs - hx) +
            hand[i] * (ax * ac - ay * ass - ax) +
            otherHand[i] * (bx * bc - by * bs - bx) +
            tail[i] * tailAngle * (rig.tailBaseY - y);
        positions[i * 2 + 1] = y +
            head[i] * (hx * hs + hy * hc - hy + nod) +
            hand[i] * (ax * ass + ay * ac - ay) -
            breathing * breath[i] +
            otherHand[i] * (bx * bs + by * bc - by);
      }
    }
  }
}

class _CompanionPainter extends CustomPainter {
  final ui.Image image;
  final ui.Image? blink;
  final _CompanionMesh mesh;
  final AnimationController idle;
  final AnimationController gesture;
  final CompanionMotion motion;
  final bool portrait;
  final bool enabled;

  _CompanionPainter({
    required this.image,
    required this.blink,
    required this.mesh,
    required this.idle,
    required this.gesture,
    required Listenable repaint,
    required this.motion,
    required this.portrait,
    required this.enabled,
  }) : super(repaint: repaint);

  static final _identity = Float64List.fromList([
    1,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1,
  ]);

  double _blinkPulse(double seconds, double at) {
    final t = seconds - at;
    if (t < 0 || t > .24) return 0;
    return t < .085 ? _smooth(0, .085, t) : 1 - _smooth(.12, .24, t);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rig = mesh.rig;
    final unit = rig.reference.height / 1536;
    final t = enabled ? idle.value * 13 : 0.0;
    final p = enabled ? gesture.value : 0.0;
    final envelope = math.sin(math.pi * p);
    final isGreeting = motion == CompanionMotion.greet;
    final celebrating = motion == CompanionMotion.celebrate;
    final thinking = motion == CompanionMotion.thinking;
    final nodding = motion == CompanionMotion.nod;
    final headAngle = enabled
        ? .014 * math.sin(t * math.pi * 2 / 6.5) +
            (isGreeting ? rig.greetingTilt * envelope : 0) +
            (thinking ? .05 * (.5 - .5 * math.cos(t * math.pi * 2 / 6.5)) : 0)
        : 0.0;
    final handCycles = switch (rig.kind) {
      _CompanionKind.eli => 6,
      _CompanionKind.drago => 4,
      _CompanionKind.halo => 2,
    };
    final handAngle = (isGreeting || celebrating)
        ? rig.handSwing * math.sin(p * math.pi * handCycles) * envelope
        : 0.0;
    final nod = nodding || celebrating
        ? 13 * unit * math.sin(p * math.pi * 4) * envelope
        : isGreeting
            ? rig.greetingNod * math.sin(p * math.pi * 2) * envelope
            : 0.0;
    mesh.update(
        headAngle,
        handAngle,
        enabled ? 2.5 * unit * math.sin(t * math.pi * 6 / 13) : 0,
        nod,
        enabled ? .025 * math.sin(t * math.pi * 4 / 13) : 0);

    // Portraits show the face rather than shrinking a whole body into 32px.
    final source = portrait ? rig.portrait : rig.fullBody;
    final scale =
        math.min(size.width / source.width, size.height / source.height);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate((size.width - source.width * scale) / 2,
        (size.height - source.height * scale) / 2);
    canvas.scale(scale);
    canvas.translate(-source.left, -source.top);
    final vertices = ui.Vertices.raw(ui.VertexMode.triangles, mesh.positions,
        textureCoordinates: mesh.texture, indices: mesh.indices);
    final bodyShader =
        ui.ImageShader(image, ui.TileMode.clamp, ui.TileMode.clamp, _identity);
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..shader = bodyShader;
    canvas.drawVertices(vertices, BlendMode.srcOver, paint);
    vertices.dispose();
    bodyShader.dispose();

    final eyelids = blink;
    final amount = enabled
        ? math.max(_blinkPulse(t, 2.5),
            math.max(_blinkPulse(t, 6.9), _blinkPulse(t, 11.6)))
        : 0.0;
    if (eyelids != null && amount > 0) {
      for (var i = 0; i < _CompanionMesh.count; i++) {
        mesh.colors[i] =
            ((255 * amount * mesh.eyeMask[i]).round() << 24) | 0x00ffffff;
        mesh.blinkTexture[i * 2] =
            mesh.texture[i * 2] * eyelids.width / image.width;
        mesh.blinkTexture[i * 2 + 1] =
            mesh.texture[i * 2 + 1] * eyelids.height / image.height;
      }
      final lids = ui.Vertices.raw(ui.VertexMode.triangles, mesh.positions,
          textureCoordinates: mesh.blinkTexture,
          colors: mesh.colors,
          indices: mesh.indices);
      final lidShader = ui.ImageShader(
          eyelids, ui.TileMode.clamp, ui.TileMode.clamp, _identity);
      paint.shader = lidShader;
      canvas.drawVertices(lids, BlendMode.modulate, paint);
      lids.dispose();
      lidShader.dispose();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CompanionPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.blink != blink ||
      oldDelegate.mesh != mesh ||
      oldDelegate.motion != motion ||
      oldDelegate.portrait != portrait ||
      oldDelegate.enabled != enabled;
}

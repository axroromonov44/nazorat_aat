import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import 'camera_input_image.dart';
import 'face_readiness.dart';
import 'face_scan_animation.dart';
import 'frame_luminance.dart';
import 'karantin_face_remote_datasource.dart';
import 'raw_camera_frame.dart';

/// Native face scanner, a faithful port of the web client's `FaceDetection`
/// component + `useFaceDetection` hook.
///
/// It drives the front camera, runs on-device ML Kit face detection to decide
/// when the face is centered/at distance/still, counts down, captures a primary
/// cropped frame plus a few additional frames, and hands them to [onCapture].
/// All actual identity verification happens server-side; this widget only
/// detects a face locally to gate the capture.
class KarantinFaceScanner extends StatefulWidget {
  const KarantinFaceScanner({
    super.key,
    required this.onCapture,
    required this.isUploading,
    required this.isUploaded,
    this.onError,
    this.onPermissionDenied,
    this.onLowLightChanged,
    this.torchOn = false,
  });

  /// Called once a payload has been captured. The parent performs the upload;
  /// while it is in flight [isUploading] should be true.
  final Future<void> Function(KarantinFacePayload payload) onCapture;
  final bool isUploading;
  final bool isUploaded;
  final void Function(String message)? onError;

  /// Called when the OS reports the camera permission was denied, so the parent
  /// can show a platform-native "open settings" dialog.
  final VoidCallback? onPermissionDenied;

  /// Reports whether the camera is seeing a dark room. The page decides what
  /// to do about it: the screen light it would switch on is the page's own
  /// backdrop and the button for it lives in the app bar, so the decision
  /// cannot sensibly live down here.
  final ValueChanged<bool>? onLowLightChanged;

  /// Whether that light is currently on, which warms the halo around the
  /// preview and is the reason the room looks brighter than it is.
  final bool torchOn;

  @override
  State<KarantinFaceScanner> createState() => _KarantinFaceScannerState();
}

class _KarantinFaceScannerState extends State<KarantinFaceScanner>
    with WidgetsBindingObserver {
  // The scanner sits on a white page: a dark one would have the screen taking
  // light away from the very face it is trying to read. So the accents are the
  // deeper end of each hue rather than the glowing end.
  static const _readyColor = Color(0xFF1B74D8); // blue
  static const _verifiedColor = Color(0xFF0E9F4F); // green
  static const _holdColor = Color(0xFFB8761A); // amber
  static const _errorColor = Color(0xFFD03B3F); // red
  static const _idleColor = Color(0xFF8A94A6); // unlit checklist dot
  static const _lampColor = Color(0xFFFFF4E2); // the screen light's own warmth

  // How often the frame brightness is sampled. The scan itself needs every
  // frame it can get; the room's light level changes far more slowly.
  static const _lumaIntervalMs = 400;

  // Detection pacing: process at most one frame per interval.
  static const _detectionIntervalMs = 150;
  static const _countdownSeconds = 1;
  // Frames captured in a short burst; the best becomes the main image and the
  // rest (deduplicated) become the additional check images. They are pulled
  // straight from the live preview stream, never via `takePicture()`.
  static const _burstCount = 3;
  // Spacing between burst frames: far enough apart that the three shots differ
  // slightly, short enough that the whole burst is over in a blink.
  static const _burstSpacingMs = 90;
  static const _burstTimeoutMs = 1500;
  static const _mainMaxDim = 720;
  static const _additionalMaxDim = 640;

  // Passive liveness signals collected across frames (no user prompts).
  double _minEyeOpen = 1.0;
  double _maxEyeOpen = 0.0;
  double _headYMin = 999;
  double _headYMax = -999;
  double _headXMin = 999;
  double _headXMax = -999;

  CameraController? _controller;
  FaceDetector? _detector;

  bool _cameraReady = false;
  bool _streaming = false;
  bool _processing = false;
  int _lastProcessedMs = 0;

  int _step = 0;
  double _progress = 0;
  bool _isCentered = false;
  int _readyFrames = 0;
  final List<Rect> _positions = [];

  final LowLightDetector _lowLight = LowLightDetector();
  bool _isDarkRoom = false;
  int _lastLumaMs = 0;

  bool _isLive = false;
  FaceReadinessReason _reason = FaceReadinessReason.notCentered;

  int? _countdown;
  Timer? _countdownTimer;
  bool _isVerified = false;
  bool _isMutating = false;
  bool _hasCaptured = false;

  // Burst state. While `_burstCompleter` is non-null every incoming preview
  // frame is a capture candidate instead of a detection frame.
  final List<RawCameraFrame> _burst = [];
  Completer<List<RawCameraFrame>>? _burstCompleter;
  int _lastBurstMs = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableContours: false,
        enableLandmarks: false,
        // Classification gives eye-open probabilities for passive liveness
        // (a natural blink) without ever asking the user to do anything.
        enableClassification: true,
        enableTracking: true,
      ),
    );
    _initCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _stopStream();
    } else if (state == AppLifecycleState.resumed && !_hasCaptured) {
      _startStream();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _stopStream();
    _controller?.dispose();
    _detector?.close();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup:
            Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21,
      );

      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      // The scanner is portrait-only. Locking the capture orientation keeps the
      // preview's aspect ratio from flipping when the phone is tilted, which
      // would otherwise momentarily letterbox the circle.
      try {
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {
        // Not supported everywhere; the aspect is derived defensively anyway.
      }

      _controller = controller;
      setState(() => _cameraReady = true);
      await _startStream();
    } on CameraException catch (e) {
      if (_isPermissionDenied(e)) {
        widget.onPermissionDenied?.call();
      } else {
        widget.onError
            ?.call('Kamerani ochib boʻlmadi. Qaytadan urinib koʻring.');
      }
    } catch (_) {
      widget.onError?.call('Kamerani ochib boʻlmadi. Qaytadan urinib koʻring.');
    }
  }

  bool _isPermissionDenied(CameraException e) {
    final code = e.code.toLowerCase();
    return code.contains('denied') ||
        code.contains('permission') ||
        code.contains('restricted');
  }

  /// [force] keeps the stream alive for the capture burst, which runs while
  /// `_hasCaptured` is already true.
  Future<void> _startStream({bool force = false}) async {
    final controller = _controller;
    if (controller == null || _streaming) return;
    if (_hasCaptured && !force) return;
    try {
      await controller.startImageStream(_onFrame);
      _streaming = true;
    } catch (_) {
      // ignore: stream may already be running
    }
  }

  Future<void> _stopStream() async {
    final controller = _controller;
    if (controller == null || !_streaming) return;
    try {
      await controller.stopImageStream();
    } catch (_) {}
    _streaming = false;
  }

  void _onFrame(CameraImage image) {
    if (_burstCompleter != null) {
      _collectBurstFrame(image);
      return;
    }
    _sampleLight(image);
    if (_hasCaptured || _processing || _countdown != null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastProcessedMs < _detectionIntervalMs) return;
    _lastProcessedMs = now;

    _processing = true;
    _processFrame(image).whenComplete(() => _processing = false);
  }

  /// Watches how much light the camera is getting and, in a dark room, turns
  /// the screen into the flash the front camera does not have.
  void _sampleLight(CameraImage image) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastLumaMs < _lumaIntervalMs) return;
    _lastLumaMs = now;

    // With the light on the camera sees what we added, so calling the room lit
    // again takes a much brighter frame; otherwise the two states would fight.
    final flipped = _lowLight.add(
      estimateFrameLuma(image),
      brightAbove: widget.torchOn ? 150 : null,
    );
    if (!flipped || !mounted) return;

    final isDark = _lowLight.isDark;
    setState(() => _isDarkRoom = isDark);
    widget.onLowLightChanged?.call(isDark);
  }

  Future<void> _processFrame(CameraImage image) async {
    final controller = _controller;
    final detector = _detector;
    if (controller == null || detector == null) return;

    final inputImage = inputImageFromCameraImage(
      image: image,
      controller: controller,
      camera: controller.description,
    );
    if (inputImage == null) return;

    final List<Face> faces;
    try {
      faces = await detector.processImage(inputImage);
    } catch (_) {
      return;
    }
    if (!mounted || _hasCaptured || _countdown != null) return;

    if (faces.isEmpty) {
      _isLive = false;
      _reason = FaceReadinessReason.notCentered;
      _applyReadiness(step: 0, progress: 0, centered: false, resetReady: true);
      return;
    }

    // Largest face wins.
    faces.sort(
      (a, b) => (b.boundingBox.width * b.boundingBox.height).compareTo(
        a.boundingBox.width * a.boundingBox.height,
      ),
    );
    final face = faces.first;
    final box = face.boundingBox;

    final metadata = inputImage.metadata;
    var size =
        metadata?.size ?? Size(image.width.toDouble(), image.height.toDouble());
    final rotation = metadata?.rotation;
    if (rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg) {
      size = Size(size.height, size.width);
    }

    final centered = checkFaceCentered(box, size);
    final ratio = calculateFaceRatio(box, size);
    _updatePassiveLiveness(face);
    // Lenient liveness: any natural movement, a natural blink, or a small head
    // pose change counts — a real person passes effortlessly, a perfectly still
    // printed photo does not. We never prompt the user to move or blink.
    final isLive = updateLivenessPositions(_positions, box) ||
        _blinkDetected ||
        _headMoved;

    final readiness = getFaceReadinessStep(
      isCentered: centered,
      faceRatio: ratio,
      isLive: isLive,
      readyFrames: _readyFrames,
    );

    _readyFrames = readiness.readyFrames;
    if (!mounted) return;
    setState(() {
      _isCentered = centered;
      _progress = readiness.progress;
      _step = readiness.step;
      _isLive = isLive;
      _reason = readiness.reason;
    });

    if (readiness.shouldStartCountdown) {
      _readyFrames = 0;
      _startCountdown();
    }
  }

  void _updatePassiveLiveness(Face face) {
    final left = face.leftEyeOpenProbability;
    final right = face.rightEyeOpenProbability;
    if (left != null && right != null) {
      final open = (left + right) / 2;
      _minEyeOpen = math.min(_minEyeOpen, open);
      _maxEyeOpen = math.max(_maxEyeOpen, open);
    }
    final y = face.headEulerAngleY;
    if (y != null) {
      _headYMin = math.min(_headYMin, y);
      _headYMax = math.max(_headYMax, y);
    }
    final x = face.headEulerAngleX;
    if (x != null) {
      _headXMin = math.min(_headXMin, x);
      _headXMax = math.max(_headXMax, x);
    }
  }

  // A natural blink: eyes clearly open at some point and clearly closed at another.
  bool get _blinkDetected => _maxEyeOpen > 0.7 && _minEyeOpen < 0.35;

  // Small natural head-pose variation over the scan (degrees).
  bool get _headMoved =>
      (_headYMax - _headYMin) > 6 || (_headXMax - _headXMin) > 6;

  void _resetLiveness() {
    _positions.clear();
    _minEyeOpen = 1.0;
    _maxEyeOpen = 0.0;
    _headYMin = 999;
    _headYMax = -999;
    _headXMin = 999;
    _headXMax = -999;
  }

  void _applyReadiness({
    required int step,
    required double progress,
    required bool centered,
    bool resetReady = false,
  }) {
    if (resetReady) _readyFrames = 0;
    if (!mounted) return;
    setState(() {
      _step = step;
      _progress = progress;
      _isCentered = centered;
    });
  }

  void _startCountdown() {
    if (_countdownTimer != null || _hasCaptured) return;
    setState(() => _countdown = _countdownSeconds);
    _countdownTimer = Timer(const Duration(seconds: 1), () {
      _countdownTimer = null;
      setState(() => _countdown = null);
      _capture();
    });
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _hasCaptured) return;
    _hasCaptured = true;

    setState(() {
      _isVerified = true;
      _progress = 100;
      _isMutating = true;
    });

    try {
      // Grab the burst out of the running preview. Nothing on screen changes:
      // no shutter, no preview blank, no sound — the user only sees the scan
      // overlay while the frames are collected and uploaded.
      final frames = await _collectBurst();
      await _stopStream();

      if (frames.isEmpty) {
        _resetAfterFailure('Rasm olinmadi. Qaytadan urinib koʻring.');
        return;
      }

      // Decode, score, crop and compress off the UI thread: pick the
      // sharpest/brightest frame as the main image, resize + JPEG-compress
      // everything for upload.
      final result = await compute(
        processCapturedFrames,
        FrameJob(
          frames: frames,
          mainMaxDim: _mainMaxDim,
          additionalMaxDim: _additionalMaxDim,
          maxAdditional: 4,
        ),
      );
      if (result == null) {
        _resetAfterFailure('Rasm olinmadi. Qaytadan urinib koʻring.');
        return;
      }
      if (!mounted || !_hasCaptured) return;

      await widget.onCapture(
        KarantinFacePayload(
          faceImage: result.main,
          checkImages: result.additional,
        ),
      );
      // Success: the parent navigates away; keep showing the captured frame.
    } catch (_) {
      // Upload failed; the parent surfaces the message. Just reset to retry.
      restart();
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  /// Collects [_burstCount] preview frames (or whatever arrived before the
  /// timeout) without touching the capture session.
  Future<List<RawCameraFrame>> _collectBurst() async {
    _burst.clear();
    _lastBurstMs = 0;
    final completer = Completer<List<RawCameraFrame>>();
    _burstCompleter = completer;

    if (!_streaming) await _startStream(force: true);

    final frames = await completer.future
        .timeout(
          const Duration(milliseconds: _burstTimeoutMs),
          onTimeout: () => List<RawCameraFrame>.from(_burst),
        )
        .catchError((_) => <RawCameraFrame>[]);

    _burstCompleter = null;
    _burst.clear();
    return frames;
  }

  void _collectBurstFrame(CameraImage image) {
    final completer = _burstCompleter;
    if (completer == null || completer.isCompleted) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (_burst.isNotEmpty && now - _lastBurstMs < _burstSpacingMs) return;

    final controller = _controller;
    if (controller == null) return;
    final frame = rawFrameFromCameraImage(
      image: image,
      controller: controller,
      camera: controller.description,
    );
    if (frame == null) return;

    _lastBurstMs = now;
    _burst.add(frame);
    if (_burst.length >= _burstCount) {
      completer.complete(List<RawCameraFrame>.from(_burst));
    }
  }

  /// Called by the parent (via key/state) to reset the scanner after a failed
  /// verification so the user can retry.
  void restart() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _burstCompleter = null;
    _burst.clear();
    _resetLiveness();
    _readyFrames = 0;
    _hasCaptured = false;
    if (mounted) {
      setState(() {
        _step = 0;
        _progress = 0;
        _isCentered = false;
        _countdown = null;
        _isVerified = false;
        _isMutating = false;
      });
    }
    _startStream();
  }

  void _resetAfterFailure(String message) {
    widget.onError?.call(message);
    restart();
  }

  // ---------------------------------------------------------------- UI

  /// One colour drives the whole scanner: the ring, the glow, the status dot
  /// and its text. Keeping a single source avoids the old mix of borders that
  /// could disagree with each other.
  Color get _accentColor {
    if (!_cameraReady) return _readyColor;
    if (_isVerified || widget.isUploaded) return _verifiedColor;
    if (_countdown != null) return _readyColor;
    if (_step >= 2 && _isCentered) return _readyColor;
    if (_step >= 1) return _holdColor;
    return _errorColor;
  }

  bool get _torchOn => widget.torchOn;

  String get _statusText {
    if (widget.isUploaded) {
      return 'Yuz muvaffaqiyatli tasdiqlandi!';
    }
    if (_countdown != null) return 'Qimirlamay turing!';
    if (_isMutating && _isVerified) return 'Skanerlanmoqda...';
    if (_isVerified && !_isMutating) return 'Yuborilmoqda, iltimos kuting...';
    return kFaceInstructions[_step.clamp(0, kFaceInstructions.length - 1)];
  }

  /// The three gates the capture waits on, so the user can see *which* one is
  /// still open instead of only reading one line of advice at a time.
  bool get _distanceOk {
    if (_isVerified) return true;
    switch (_reason) {
      case FaceReadinessReason.waitingLiveness:
      case FaceReadinessReason.ready:
        return true;
      case FaceReadinessReason.notCentered:
      case FaceReadinessReason.tooFar:
      case FaceReadinessReason.moveCloser:
      case FaceReadinessReason.tooClose:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accentColor;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTopBar(),
        const SizedBox(height: 10),
        _buildPreview(accent),
        const SizedBox(height: 24),
        _buildStatusPill(accent),
        const SizedBox(height: 16),
        _buildChecklist(),
      ],
    );
  }

  /// The light is switched from the app bar; this only says why the button up
  /// there is worth pressing.
  Widget _buildTopBar() {
    final hint = _torchOn
        ? 'Ekran chirogʻi yoniq'
        : (_isDarkRoom ? 'Yorugʻlik kam — chiroqni yoqing' : '');

    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 240),
              opacity: hint.isEmpty ? 0 : 1,
              child: Row(
                children: [
                  Icon(
                    Icons.wb_incandescent_outlined,
                    size: 16,
                    color: _holdColor,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      hint.isEmpty ? ' ' : hint,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _holdColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill(Color accent) {
    final tone = accent;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.3),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: Container(
        key: ValueKey(_statusText),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: tone.withValues(alpha: 0.38)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PulsingDot(color: tone),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                _statusText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                  color: tone,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChecklist() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildCheck('Markazda', _isCentered || _isVerified),
        _buildCheck('Masofa', _distanceOk),
        _buildCheck('Jonli', _isLive || _isVerified),
      ],
    );
  }

  Widget _buildCheck(String label, bool active) {
    final color = active ? _verifiedColor : _idleColor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: active ? 1 : 0.45),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.5),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: color.withValues(alpha: active ? 1 : 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(Color accent) {
    const gap = 9.0;
    const stroke = 5.0;
    const ring = (gap + stroke) * 2;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Shrink on narrow phones instead of overflowing; the ring and the
        // preview always stay concentric because both derive from `box`.
        final available = constraints.hasBoundedWidth
            ? constraints.maxWidth - 16
            : double.infinity;
        final box = math.min(328.0, available.isFinite ? available : 328.0);
        final photo = box - ring;
        return _buildPreviewBox(accent, box, photo, stroke);
      },
    );
  }

  Widget _buildPreviewBox(
    Color accent,
    double box,
    double photo,
    double stroke,
  ) {
    return SizedBox(
      width: box,
      height: box,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The screen light's own halo. The pale page behind the scanner does
          // most of the lighting; this is the part of it that hugs the face.
          IgnorePointer(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 280),
              opacity: _torchOn ? 1 : 0,
              child: Container(
                width: box,
                height: box,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [_lampColor, Color(0x00FFF4E2)],
                    stops: [0.62, 1],
                  ),
                ),
              ),
            ),
          ),
          // Soft halo behind everything; it never draws an edge of its own, so
          // it cannot look like a second ring.
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            width: photo,
            height: photo,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: _cameraReady ? 0.3 : 0.0),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          // The live camera. Never a swapped still and never interrupted by a
          // photo capture, so nothing can flash white.
          SizedBox(
            width: photo,
            height: photo,
            child: ClipOval(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildCamera(photo),
                  if (_isVerified) _buildScanOverlay(),
                ],
              ),
            ),
          ),
          // Exactly one ring: a segmented track whose ticks light up with the
          // progress, painted on a single circle that is concentric with the
          // preview by construction.
          IgnorePointer(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: (_progress / 100).clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOut,
              builder: (context, value, _) => CustomPaint(
                size: Size.square(box),
                painter: _ScannerRingPainter(
                  progress: value,
                  color: accent,
                  stroke: stroke,
                  visible: _cameraReady,
                ),
              ),
            ),
          ),
          if (_countdown != null && !_isVerified) _buildCountdown(_countdown!),
        ],
      ),
    );
  }

  Widget _buildCamera(double diameter) {
    final controller = _controller;
    if (!_cameraReady || controller == null) {
      return const ColoredBox(
        color: Color(0xFF111111),
        child: Center(
          child: CircularProgressIndicator(
            color: _verifiedColor,
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    // Rebuild whenever the controller reports a new orientation, so the box we
    // hand the preview never goes stale.
    return ValueListenableBuilder<CameraValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        // `CameraPreview` wraps itself in an AspectRatio: `aspectRatio` in
        // landscape, `1 / aspectRatio` in portrait. Give it a box of any other
        // shape and it letterboxes itself inside that box — which is what left
        // the white gap between the preview and the ring. Build the box from
        // the very same ratio so the preview fills it edge to edge, then
        // cover-crop the result into the circle.
        final orientation =
            value.lockedCaptureOrientation ?? value.deviceOrientation;
        final previewAspect = previewBoxAspect(
          aspectRatio: value.aspectRatio,
          orientation: orientation,
        );

        return ColoredBox(
          // Anything the cover-crop cannot reach reads as camera black, never
          // as the page background.
          color: const Color(0xFF111111),
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: diameter * previewAspect,
              height: diameter,
              child: CameraPreview(controller),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCountdown(int countdown) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.84, end: 1.0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        width: 128,
        height: 128,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.24),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.38),
            width: 1.5,
          ),
        ),
        child: Text(
          '${countdown + 1}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 58,
            // A thin numeral reads as a clock, not as an alert.
            fontWeight: FontWeight.w300,
            height: 1,
            shadows: [Shadow(color: Color(0x66000000), blurRadius: 12)],
          ),
        ),
      ),
    );
  }

  Widget _buildScanOverlay() {
    // No border here: the ring above the preview is the only outline, so the
    // overlay just dims the frame and runs the scan line.
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.3),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const FaceScanAnimation(scanColor: _verifiedColor),
          if (widget.isUploaded)
            const Center(child: _SuccessCheck(color: _verifiedColor))
          else if (widget.isUploading)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Tekshirilmoqda...',
                  style: TextStyle(
                    color: _verifiedColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The status pill's dot, breathing so a long wait never looks frozen.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});

  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: 0.45 + 0.55 * t),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.4 * t),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The tick that lands on the face once the backend has accepted it.
class _SuccessCheck extends StatelessWidget {
  const _SuccessCheck({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        width: 86,
        height: 86,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.18),
          border: Border.all(color: color, width: 2),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 24),
          ],
        ),
        child: Icon(Icons.check_rounded, size: 48, color: color),
      ),
    );
  }
}

/// The aspect ratio of the box a [CameraPreview] has to be given so it fills it
/// exactly instead of letterboxing itself inside it.
///
/// `CameraPreview` wraps its texture in `AspectRatio(aspectRatio)` while the
/// device is landscape and `AspectRatio(1 / aspectRatio)` while it is portrait.
/// Any other box shape leaves a gap on two sides — which is what used to show
/// through as a pale crescent between the preview and the ring.
double previewBoxAspect({
  required double aspectRatio,
  required DeviceOrientation orientation,
}) {
  if (aspectRatio <= 0 || !aspectRatio.isFinite) return 1;
  final isLandscape = orientation == DeviceOrientation.landscapeLeft ||
      orientation == DeviceOrientation.landscapeRight;
  return isLandscape ? aspectRatio : 1 / aspectRatio;
}

/// Draws the scanner's single ring: a dial of short ticks that light up with
/// the progress, starting at 12 o'clock.
///
/// Ticks rather than one solid arc: a dial makes a half-finished scan legible
/// at a glance, and the gaps keep the ring from reading as a second border
/// around the preview.
class _ScannerRingPainter extends CustomPainter {
  const _ScannerRingPainter({
    required this.progress,
    required this.color,
    required this.stroke,
    required this.visible,
  });

  final double progress;
  final Color color;
  final double stroke;
  final bool visible;

  static const int _ticks = 72;

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible) return;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );

    const startAngle = -math.pi / 2;
    const segment = 2 * math.pi / _ticks;
    // The gap is what makes it a dial; the remainder is the tick itself.
    const gap = segment * 0.45;
    const tick = segment - gap;

    final dim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = Colors.black.withValues(alpha: 0.14);

    final lit = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);

    final litCount = (progress.clamp(0.0, 1.0) * _ticks).round();

    for (var i = 0; i < _ticks; i++) {
      final from = startAngle + i * segment + gap / 2;
      if (i < litCount) {
        canvas.drawArc(rect, from, tick, false, glow);
        canvas.drawArc(rect, from, tick, false, lit);
      } else {
        canvas.drawArc(rect, from, tick, false, dim);
      }
    }
  }

  @override
  bool shouldRepaint(_ScannerRingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.stroke != stroke ||
      old.visible != visible;
}

// ---------------------------------------------------------------------------
// Off-thread frame processing (best-frame selection + crop + resize + compress)
// ---------------------------------------------------------------------------

/// Input for [processCapturedFrames]. All fields are isolate-sendable.
class FrameJob {
  const FrameJob({
    required this.frames,
    required this.mainMaxDim,
    required this.additionalMaxDim,
    required this.maxAdditional,
  });

  final List<RawCameraFrame> frames;
  final int mainMaxDim;
  final int additionalMaxDim;
  final int maxAdditional;
}

class FrameResult {
  const FrameResult({required this.main, required this.additional});

  final Uint8List main;
  final List<Uint8List> additional;
}

/// Decodes the streamed burst, picks the sharpest, best-exposed frame as the
/// main image (centre-cropped to a square and down-scaled), and compresses the
/// remaining frames as additional check images. Runs in an isolate via
/// `compute` so YUV/BGRA conversion never janks the UI.
///
/// Returns null when not a single frame could be decoded.
FrameResult? processCapturedFrames(FrameJob job) {
  final decoded = <img.Image>[];
  for (final frame in job.frames) {
    final im = decodeRawFrame(frame);
    if (im != null) decoded.add(im);
  }

  if (decoded.isEmpty) return null;

  var bestIndex = 0;
  var bestScore = -1.0;
  for (var i = 0; i < decoded.length; i++) {
    final score = _frameScore(decoded[i]);
    if (score > bestScore) {
      bestScore = score;
      bestIndex = i;
    }
  }

  final main = _cropSquareResizeJpg(decoded[bestIndex], job.mainMaxDim, 85);

  final additional = <Uint8List>[];
  for (var i = 0;
      i < decoded.length && additional.length < job.maxAdditional;
      i++) {
    if (i == bestIndex) continue;
    additional.add(_resizeJpg(decoded[i], job.additionalMaxDim, 80));
  }
  // Ensure at least one additional frame when possible (backend expects >= 1).
  if (additional.isEmpty) {
    additional.add(_resizeJpg(decoded[bestIndex], job.additionalMaxDim, 80));
  }

  return FrameResult(main: main, additional: additional);
}

/// Sharpness (gradient energy) weighted by how well-exposed the frame is.
double _frameScore(img.Image image) {
  final small = img.grayscale(img.copyResize(image, width: 200));
  final w = small.width;
  final h = small.height;
  var energy = 0.0;
  var lumSum = 0.0;
  var count = 0;
  for (var y = 2; y < h; y += 2) {
    for (var x = 2; x < w; x += 2) {
      final cur = small.getPixel(x, y).r.toDouble();
      final left = small.getPixel(x - 2, y).r.toDouble();
      final up = small.getPixel(x, y - 2).r.toDouble();
      final gx = cur - left;
      final gy = cur - up;
      energy += gx * gx + gy * gy;
      lumSum += cur;
      count++;
    }
  }
  if (count == 0) return 0;
  final sharpness = energy / count;
  final brightness = lumSum / count;
  final exposure =
      1 - ((brightness - 128).abs() / 128); // 1 at mid, 0 at extremes
  return sharpness * (0.5 + 0.5 * exposure.clamp(0.0, 1.0));
}

Uint8List _cropSquareResizeJpg(img.Image image, int maxDim, int quality) {
  final side = math.min(image.width, image.height);
  final offX = ((image.width - side) / 2).round();
  final offY = ((image.height - side) / 2).round();
  var out = img.copyCrop(image, x: offX, y: offY, width: side, height: side);
  if (side > maxDim) {
    out = img.copyResize(out, width: maxDim, height: maxDim);
  }
  return Uint8List.fromList(img.encodeJpg(out, quality: quality));
}

Uint8List _resizeJpg(img.Image image, int maxDim, int quality) {
  var out = image;
  final longest = math.max(image.width, image.height);
  if (longest > maxDim) {
    out = image.width >= image.height
        ? img.copyResize(image, width: maxDim)
        : img.copyResize(image, height: maxDim);
  }
  return Uint8List.fromList(img.encodeJpg(out, quality: quality));
}

import 'package:camera/camera.dart';

/// Average brightness of a preview frame on the usual 0–255 luma scale, or
/// [kUnknownLuma] when the frame's format is not one we can read.
///
/// Sampled on a sparse grid rather than over every pixel: this runs beside ML
/// Kit on the preview stream, so it has to cost almost nothing. A few hundred
/// samples are plenty to tell a dark room from a lit one.
const double kUnknownLuma = -1;

double estimateFrameLuma(CameraImage image, {int samplesPerAxis = 16}) {
  if (image.planes.isEmpty || image.width <= 0 || image.height <= 0) {
    return kUnknownLuma;
  }

  final plane = image.planes.first;
  final bytes = plane.bytes;
  if (bytes.isEmpty) return kUnknownLuma;

  final rowStride = plane.bytesPerRow;
  final isBgra = image.format.group == ImageFormatGroup.bgra8888;
  // YUV keeps luma in its own plane, so the first byte of a pixel already is
  // the value we want; BGRA needs the three channels weighted.
  final pixelStride = isBgra ? (plane.bytesPerPixel ?? 4) : 1;
  if (rowStride <= 0 || pixelStride <= 0) return kUnknownLuma;

  final stepX = (image.width / samplesPerAxis).floor().clamp(1, image.width);
  final stepY = (image.height / samplesPerAxis).floor().clamp(1, image.height);

  var sum = 0.0;
  var count = 0;
  for (var y = 0; y < image.height; y += stepY) {
    final rowStart = y * rowStride;
    for (var x = 0; x < image.width; x += stepX) {
      final offset = rowStart + x * pixelStride;
      if (offset + (isBgra ? 2 : 0) >= bytes.length) break;
      if (isBgra) {
        final b = bytes[offset].toDouble();
        final g = bytes[offset + 1].toDouble();
        final r = bytes[offset + 2].toDouble();
        sum += 0.299 * r + 0.587 * g + 0.114 * b;
      } else {
        sum += bytes[offset].toDouble();
      }
      count++;
    }
  }

  if (count == 0) return kUnknownLuma;
  return sum / count;
}

/// Turns a stream of per-frame luma values into a stable "the room is dark"
/// verdict.
///
/// Two guards keep the verdict from flickering, because a verdict that flips
/// every other frame would strobe the screen light: the thresholds overlap
/// (hysteresis), and a flip has to hold for [framesToConfirm] samples before it
/// counts.
class LowLightDetector {
  LowLightDetector({
    this.darkBelow = 60,
    this.brightAbove = 95,
    this.framesToConfirm = 3,
  });

  /// Below this the frame counts as dark.
  final double darkBelow;

  /// Above this it counts as lit again. The gap to [darkBelow] is the
  /// hysteresis band, where the current verdict simply stands.
  final double brightAbove;

  /// How many consecutive samples a flip needs before it is accepted.
  final int framesToConfirm;

  bool _isDark = false;
  int _streak = 0;

  bool get isDark => _isDark;

  /// Feeds one sample. Returns true when the verdict just flipped, so the
  /// caller can act once per change instead of once per frame.
  /// [brightAbove] overrides the field of the same name for this sample. The
  /// scanner raises it while the screen light is on: the camera then sees the
  /// light we added ourselves, so the ordinary bar would read the room as lit,
  /// switch the light off, and the verdict would strobe at a frame or two per
  /// second.
  bool add(double luma, {double? brightAbove}) {
    if (luma == kUnknownLuma || luma.isNaN) return false;

    final litBar = brightAbove ?? this.brightAbove;
    final votesDark = luma < darkBelow;
    final votesBright = luma > litBar;
    if (votesDark == _isDark || (!votesDark && !votesBright)) {
      _streak = 0;
      return false;
    }

    _streak++;
    if (_streak < framesToConfirm) return false;

    _streak = 0;
    _isDark = votesDark;
    return true;
  }

  void reset() {
    _isDark = false;
    _streak = 0;
  }
}

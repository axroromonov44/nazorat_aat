import 'package:flutter_test/flutter_test.dart';
import 'package:karantin_face_sdk/src/frame_luminance.dart';

void main() {
  group('LowLightDetector', () {
    test('needs the flip to hold before it accepts it', () {
      final detector = LowLightDetector(framesToConfirm: 3);

      expect(detector.add(20), isFalse);
      expect(detector.add(20), isFalse);
      expect(detector.isDark, isFalse);
      expect(detector.add(20), isTrue);
      expect(detector.isDark, isTrue);
    });

    test('a single bright frame does not undo a dark verdict', () {
      final detector = LowLightDetector(framesToConfirm: 3);
      for (var i = 0; i < 3; i++) {
        detector.add(20);
      }

      expect(detector.add(200), isFalse);
      // The streak restarts, so the one stray frame is forgotten.
      expect(detector.add(20), isFalse);
      expect(detector.isDark, isTrue);
    });

    test('the band between the thresholds leaves the verdict alone', () {
      final detector = LowLightDetector(
        darkBelow: 60,
        brightAbove: 95,
        framesToConfirm: 1,
      );

      for (var i = 0; i < 5; i++) {
        expect(detector.add(80), isFalse);
      }
      expect(detector.isDark, isFalse);
    });

    test('with the light on, calling the room lit takes a brighter frame', () {
      final detector = LowLightDetector(framesToConfirm: 1);
      detector.add(20);
      expect(detector.isDark, isTrue);

      // What the screen light itself adds must not read as daylight.
      expect(detector.add(120, brightAbove: 150), isFalse);
      expect(detector.isDark, isTrue);

      expect(detector.add(180, brightAbove: 150), isTrue);
      expect(detector.isDark, isFalse);
    });

    test('an unreadable frame is ignored rather than counted as dark', () {
      final detector = LowLightDetector(framesToConfirm: 1);

      expect(detector.add(kUnknownLuma), isFalse);
      expect(detector.add(double.nan), isFalse);
      expect(detector.isDark, isFalse);
    });

    test('reset clears both the verdict and the streak', () {
      final detector = LowLightDetector(framesToConfirm: 1);
      detector.add(10);
      expect(detector.isDark, isTrue);

      detector.reset();
      expect(detector.isDark, isFalse);
    });
  });
}

import 'package:screen_brightness/screen_brightness.dart';

/// The front camera has no flash, so the only light the app can add in a dark
/// room is the screen itself: the brightness pinned to maximum while the page
/// around the preview turns into a pale lamp.
///
/// This class owns the brightness half of that. Every call swallows its
/// platform errors — a phone that refuses the brightness write still has to be
/// able to scan a face.
class ScreenTorch {
  bool _on = false;

  /// Whether the brightness is currently pinned by us.
  bool get isOn => _on;

  Future<void> turnOn() async {
    if (_on) return;
    _on = true;
    await _apply(true);
  }

  Future<void> turnOff() async {
    if (!_on) return;
    _on = false;
    await _apply(false);
  }

  Future<void> toggle() => _on ? turnOff() : turnOn();

  /// Drops the override while the app is backgrounded, and puts it back on
  /// resume. Without this the phone would sit at full brightness in the
  /// recents list, which reads as a bug and drains the battery.
  Future<void> suspend() => _on ? _apply(false) : Future.value();

  Future<void> resume() => _on ? _apply(true) : Future.value();

  /// Must be called from `dispose`: the override is application-scoped, but
  /// nothing restores it on its own while the app stays alive, so leaving the
  /// scanner would leave the phone pinned at full brightness.
  Future<void> dispose() async {
    _on = false;
    await _apply(false);
  }

  Future<void> _apply(bool on) async {
    try {
      final brightness = ScreenBrightness.instance;
      if (on) {
        await brightness.setApplicationScreenBrightness(1);
      } else {
        await brightness.resetApplicationScreenBrightness();
      }
    } catch (_) {
      // Unsupported or denied; the pale backdrop still adds some light.
    }
  }
}

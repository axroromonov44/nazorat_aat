import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Sends production crashes to Firebase Crashlytics.
///
/// When the app falls over in the field the inspector simply reopens it and
/// tells nobody, so this is the only thing that ever reports the problem.
///
/// Firebase is configured from the native files (`google-services.json`,
/// `GoogleService-Info.plist`). If they are missing, [init] returns quietly
/// and the app runs as usual — only crash reporting is absent. That is also
/// why `firebase_options.dart` is deliberately not used: the generated file
/// would have to exist for the code to compile at all.
class CrashReporting {
  CrashReporting._();

  static bool _active = false;

  /// Whether reporting is actually on. False when the config files are absent.
  static bool get isActive => _active;

  static Future<void> init() async {
    try {
      await Firebase.initializeApp();
    } catch (error) {
      // Missing or malformed configuration is no reason to stop the app:
      // crash reporting is a bonus, not a feature the inspector needs.
      if (kDebugMode) {
        debugPrint('CrashReporting: Firebase did not start ($error)');
      }
      return;
    }

    final crashlytics = FirebaseCrashlytics.instance;
    // Off in debug: every red screen a developer produces would otherwise
    // bury the real production crashes.
    await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);
    _active = true;

    FlutterError.onError = (details) {
      // Keep presentError, otherwise the red screen disappears in debug and
      // finding the error locally gets harder.
      FlutterError.presentError(details);
      crashlytics.recordFlutterFatalError(details);
    };

    // Asynchronous errors the framework does not catch (futures, isolates).
    PlatformDispatcher.instance.onError = (error, stack) {
      crashlytics.recordError(error, stack, fatal: true);
      return true;
    };
  }

  /// A note attached to the crash report. Roughly the last 64 KB is kept, so
  /// this is for short markers such as which step the sync died on.
  static void log(String message) {
    if (!_active) return;
    FirebaseCrashlytics.instance.log(message);
  }

  /// Something worth knowing that did not stop the app — a part of the
  /// reference images failing to download, for instance.
  static Future<void> recordNonFatal(
    Object error,
    StackTrace? stack, {
    String? reason,
  }) async {
    if (!_active) return;
    await FirebaseCrashlytics.instance.recordError(
      error,
      stack,
      reason: reason,
      fatal: false,
    );
  }

  /// A value attached to every later report, unlike [log], which is a
  /// one-off line.
  ///
  /// This is how a crash is told apart from the same crash on a different
  /// Shorebird patch: the stack traces are identical, the patch number is
  /// not.
  static Future<void> setCustomKey(String key, Object value) async {
    if (!_active) return;
    await FirebaseCrashlytics.instance.setCustomKey(key, value);
  }

  /// Ties reports to one inspector, so a "it does not work for me" call can
  /// be matched against the logs.
  ///
  /// Only the internal identifier — never a name, phone number or passport id.
  static Future<void> setUserId(String? id) async {
    if (!_active) return;
    await FirebaseCrashlytics.instance.setUserIdentifier(id ?? '');
  }
}

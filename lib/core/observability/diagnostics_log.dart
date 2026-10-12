import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'crash_reporting.dart';

enum DiagLevel { info, warn, error }

/// A diagnostics log kept on the device.
///
/// The problem it solves: the app works offline, so when something goes wrong
/// the evidence stays on the inspector's phone and the developer never sees
/// it. Crashlytics catches crashes, but not "it did not crash, it just did
/// not work": a rejected login, a sync that stopped, a request that timed out.
///
/// So this keeps a ring buffer where:
/// * the last [_maxLines] lines live on disk and survive a restart, which
///   means the lines leading *up to* a crash survive too;
/// * every line also becomes a Crashlytics breadcrumb, so the log travels
///   with any crash or non-fatal report;
/// * [exportToFile] lets the inspector send the whole log with one tap — the
///   file is ready even with no connection.
class DiagnosticsLog {
  DiagnosticsLog._();

  static const _boxName = 'diagnostics';
  static const _linesKey = 'lines';

  /// ~1000 lines ≈ 100 KB. Enough for a whole sync session without filling
  /// up the phone.
  static const _maxLines = 1000;

  /// Writing on every line is expensive (a sync produces dozens per second),
  /// so writes are debounced.
  static const _flushDelay = Duration(seconds: 3);

  static final Queue<String> _lines = Queue<String>();
  static Box<dynamic>? _box;
  static Timer? _flushTimer;
  static bool _dirty = false;

  /// Called once Hive is open. The previous session's log is read back, so
  /// "what happened yesterday" is still answerable.
  static Future<void> init() async {
    try {
      final box = await Hive.openBox<dynamic>(_boxName);
      _box = box;
      final stored = (box.get(_linesKey) as List<dynamic>?) ?? const [];
      // Stored lines come first; whatever was recorded since launch is newer.
      final carried = List<String>.from(_lines);
      _lines
        ..clear()
        ..addAll(stored.cast<String>())
        ..addAll(carried);
      _trim();
      record(DiagLevel.info, 'app', '--- new session ---');
    } catch (error) {
      if (kDebugMode) debugPrint('DiagnosticsLog: could not open ($error)');
    }
  }

  static void record(
    DiagLevel level,
    String tag,
    String message, {
    Object? error,
  }) {
    final time = DateTime.now().toIso8601String();
    final suffix = error == null ? '' : ' | $error';
    final line = '$time ${level.name.toUpperCase()} [$tag] $message$suffix';

    _lines.add(line);
    _trim();
    _dirty = true;
    _scheduleFlush();

    // Breadcrumb: these lines ride along with any crash report.
    CrashReporting.log('[$tag] $message$suffix');
    if (kDebugMode) debugPrint(line);
  }

  static void info(String tag, String message) =>
      record(DiagLevel.info, tag, message);

  static void warn(String tag, String message, {Object? error}) =>
      record(DiagLevel.warn, tag, message, error: error);

  static void error(String tag, String message, {Object? error}) =>
      record(DiagLevel.error, tag, message, error: error);

  static void _trim() {
    while (_lines.length > _maxLines) {
      _lines.removeFirst();
    }
  }

  static void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(_flushDelay, flush);
  }

  /// Also called when the app goes to the background, otherwise the last few
  /// seconds of lines are lost.
  static Future<void> flush() async {
    _flushTimer?.cancel();
    final box = _box;
    if (box == null || !_dirty) return;
    _dirty = false;
    try {
      await box.put(_linesKey, _lines.toList());
    } catch (error) {
      if (kDebugMode) debugPrint('DiagnosticsLog: could not save ($error)');
    }
  }

  /// The log as it stands, as text.
  static String dump() => _lines.join('\n');

  /// Writes the log to a file and returns it, so the inspector can send it
  /// over Telegram.
  static Future<File> exportToFile() async {
    await flush();
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = File('${dir.path}/diagnostics_$stamp.txt');
    return file.writeAsString(dump());
  }

  static Future<void> clear() async {
    _lines.clear();
    _dirty = true;
    await flush();
  }
}

/// Flushes the log to disk when the app leaves the foreground.
///
/// Without this the lines written in the last [DiagnosticsLog._flushDelay]
/// would be lost — precisely the ones just before the app was closed.
class DiagnosticsLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    DiagnosticsLog.flush();
  }
}

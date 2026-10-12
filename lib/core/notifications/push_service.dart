import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../observability/crash_reporting.dart';
import '../observability/diagnostics_log.dart';

/// Handles a message that arrives while the app is backgrounded or closed.
///
/// This runs in a **separate isolate**, so none of the app's state (getIt,
/// blocs, Hive) is reachable. Hence it does nothing: the system shows the
/// notification itself, and [PushService._handleOpened] runs once the app is
/// opened.
///
/// It must be a top-level function annotated with `@pragma('vm:entry-point')`
/// — otherwise tree shaking removes it from release builds and background
/// messages silently stop working.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kDebugMode) debugPrint('[push] background: ${message.messageId}');
}

/// Push notifications.
///
/// [init] returns quietly when Firebase is not configured, and the app runs
/// as usual.
class PushService {
  PushService({this.onMessageOpened});

  /// Called when the user taps a notification, for example to navigate.
  final void Function(Map<String, dynamic> data)? onMessageOpened;

  static const _channel = AndroidNotificationChannel(
    'nazorat_default',
    'General notifications',
    description: 'Messages from the Nazorat AAT system',
    importance: Importance.high,
  );

  final _local = FlutterLocalNotificationsPlugin();
  String? _token;

  /// The device's FCM token; the backend addresses messages to it.
  String? get token => _token;

  Future<void> init() async {
    if (!CrashReporting.isActive) return;

    try {
      await _setUpLocalNotifications();

      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      DiagnosticsLog.info(
        'push',
        'permission: ${settings.authorizationStatus.name}',
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // The system shows nothing while the app is in the foreground, so we
      // show it ourselves — otherwise the message goes entirely unnoticed.
      FirebaseMessaging.onMessage.listen(_showForeground);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleOpened);

      // A notification tapped while the app was closed comes back here;
      // onMessageOpenedApp does not catch it.
      final initial = await messaging.getInitialMessage();
      if (initial != null) _handleOpened(initial);

      await _refreshToken(messaging);
      messaging.onTokenRefresh.listen((value) {
        _token = value;
        DiagnosticsLog.info('push', 'token refreshed');
      });
    } catch (error, stack) {
      DiagnosticsLog.warn('push', 'did not start', error: error);
      await CrashReporting.recordNonFatal(
        error,
        stack,
        reason: 'Push service did not start',
      );
    }
  }

  Future<void> _setUpLocalNotifications() async {
    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // FirebaseMessaging already asks for the iOS permission, so do not
        // ask a second time here.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null) onMessageOpened?.call({'route': payload});
      },
    );

    if (Platform.isAndroid) {
      // On Android 8+ a notification never appears unless its channel was
      // created first.
      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_channel);
    }
  }

  Future<void> _refreshToken(FirebaseMessaging messaging) async {
    // On iOS getToken throws while the APNs token has not arrived yet. That
    // is normal; onTokenRefresh delivers it shortly after.
    _token = await messaging.getToken();
    DiagnosticsLog.info('push', 'token acquired: ${_token != null}');
    if (kDebugMode && _token != null) debugPrint('[push] FCM token: $_token');
  }

  Future<void> _showForeground(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    DiagnosticsLog.info('push', 'foreground: ${message.messageId}');
    await _local.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: message.data['route'] as String?,
    );
  }

  void _handleOpened(RemoteMessage message) {
    DiagnosticsLog.info('push', 'tapped: ${message.messageId}');
    onMessageOpened?.call(message.data);
  }
}

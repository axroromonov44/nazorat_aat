import 'package:flutter/painting.dart';

/// Configuration for a Karantin ID face-login flow.
///
/// Supply the OAuth client parameters issued for your app. Everything else has
/// sensible defaults; override [primaryColor] or the UI strings to match your
/// product.
class KarantinFaceConfig {
  const KarantinFaceConfig({
    required this.clientId,
    required this.redirectUri,
    this.baseUrl = 'https://id.karantin.uz',
    this.scope = 'openid profile',
    this.authType = 'login',
    this.primaryColor = const Color(0xFF2E7D32),
    this.debugLogging = false,
    this.userAgent = defaultUserAgent,
    this.strings = const KarantinFaceStrings(),
  });

  /// What a native client calls itself when it has nothing to hide.
  ///
  /// The backend's own client is a browser, so if it ever refuses this one on
  /// the agent alone, pass a browser's string here instead of changing the
  /// default: the honest value is the right one to try first.
  static const String defaultUserAgent = 'KarantinFaceSdk/0.1 (Flutter)';

  /// OAuth client id issued for your app.
  final String clientId;

  /// OAuth redirect URI registered for your client. The flow finishes when the
  /// backend redirects here with a `?code=` parameter.
  final String redirectUri;

  /// Karantin ID host (no trailing slash). The API lives under `$baseUrl/app`.
  final String baseUrl;

  final String scope;

  /// OAuth `auth_type` (e.g. `login`).
  final String authType;

  /// Accent colour for the form button and field focus.
  final Color primaryColor;

  /// When true, logs every request/response to the console (debug only).
  final bool debugLogging;

  /// Sent as `User-Agent` on every Karantin ID call.
  final String userAgent;

  /// UI strings (Uzbek defaults); override to localise.
  final KarantinFaceStrings strings;

  Uri get authorizeUri => Uri.parse(
        '$baseUrl/app/project/oauth/authorize'
        '?response_type=code'
        '&client_id=$clientId'
        '&redirect_uri=${Uri.encodeComponent(redirectUri)}'
        '&scope=${Uri.encodeComponent(scope)}'
        '&auth_type=$authType',
      );

  String get apiBaseUrl => '$baseUrl/app';
}

/// User-facing strings for the face-login UI.
class KarantinFaceStrings {
  const KarantinFaceStrings({
    this.appBarTitle = 'Karantin ID',
    this.formTitle = 'Yuz orqali tizimga kirish',
    this.continueButton = 'Davom etish',
    this.passportLabel = 'Passport seriya va raqamni kiriting',
    this.pnflLabel = 'PNFLingizni kiriting',
    this.passportTab = 'Passport',
    this.pnflTab = 'JSHSHR (PINFL)',
    this.cameraPermissionTitle = 'Kameraga ruxsat kerak',
    this.cameraPermissionBody =
        'Yuz skanerlash uchun kameradan foydalanish ruxsati talab qilinadi. '
            'Sozlamalar orqali ruxsat bering.',
    this.cancelAction = 'Bekor qilish',
    this.openSettings = "Sozlamalarga o'tish",
    this.retryAction = 'Qayta urinish',
  });

  final String appBarTitle;
  final String formTitle;
  final String continueButton;
  final String passportLabel;
  final String pnflLabel;
  final String passportTab;
  final String pnflTab;
  final String cameraPermissionTitle;
  final String cameraPermissionBody;
  final String cancelAction;
  final String openSettings;
  final String retryAction;
}

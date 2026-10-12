import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HapticFeedback, SystemUiOverlayStyle;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'karantin_device_data.dart';
import 'karantin_face_config.dart';
import 'karantin_face_exception.dart';
import 'karantin_face_remote_datasource.dart';
import 'karantin_face_scanner.dart';
import 'karantin_face_session.dart';
import 'karantin_passport_form.dart';

/// The Karantin ID native face-login screen.
///
/// Push it and await its result: it returns the OAuth `code` string (or `null`
/// if the user cancelled) via `Navigator.pop`. Exchange that code for tokens on
/// your own backend, exactly as you would after a webview redirect.
///
/// ```dart
/// final code = await Navigator.of(context).push<String?>(
///   MaterialPageRoute(
///     builder: (_) => KarantinFaceAuthPage(config: myConfig),
///   ),
/// );
/// ```
class KarantinFaceAuthPage extends StatefulWidget {
  const KarantinFaceAuthPage({
    super.key,
    required this.config,
    this.dataSource,
    this.collector,
  });

  final KarantinFaceConfig config;
  final KarantinFaceRemoteDataSource? dataSource;
  final KarantinDeviceDataCollector? collector;

  @override
  State<KarantinFaceAuthPage> createState() => _KarantinFaceAuthPageState();
}

enum _Phase { loading, form, face, success, error }

const _nonFaceTerms = [
  'passport',
  'pasport',
  'pinfl',
  'pnfl',
  'token',
  'havola',
  'link',
  'expired',
  'eskirgan',
  'one_code',
  'code',
];

const _errorColor = Color(0xFFD32F2F);

// The camera phase runs on its own near-black page: the preview is the only
// bright thing on screen, and a dark room no longer gets a white page shoved
// in the user's face.
const _cameraBackground = Color(0xFF07090C);

// ...unless the screen light is on, when that same page becomes the lamp.
const _lampBackground = Color(0xFFFFF4E2);

class _KarantinFaceAuthPageState extends State<KarantinFaceAuthPage> {
  late final KarantinFaceRemoteDataSource _dataSource =
      widget.dataSource ?? KarantinFaceRemoteDataSource(config: widget.config);
  late final KarantinDeviceDataCollector _collector =
      widget.collector ?? KarantinDeviceDataCollector();

  KarantinFaceConfig get _config => widget.config;
  KarantinFaceStrings get _strings => widget.config.strings;

  _Phase _phase = _Phase.loading;
  String _errorMessage = '';

  KarantinFaceSession? _session;
  String _identifier = '';
  bool _isPnfl = false;

  bool _isUploading = false;
  bool _isUploaded = false;
  bool _permissionDialogOpen = false;
  bool _torchOn = false;

  /// The scanner phases own the page's colours; the form and the error view
  /// stay on the ordinary light background.
  bool get _isCameraPhase => _phase == _Phase.face || _phase == _Phase.success;

  Color? get _pageColor {
    if (!_isCameraPhase) return null;
    return _torchOn ? _lampBackground : _cameraBackground;
  }

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    setState(() => _phase = _Phase.loading);
    try {
      final session = await _dataSource.startSession();
      if ((session.token == null || session.token!.isEmpty) &&
          session.flow != KarantinFaceFlow.register) {
        _fail('Karantin ID sessiyasini ochib boʻlmadi. Qayta urinib koʻring.');
        return;
      }
      if (!mounted) return;
      setState(() {
        _session = session;
        _phase = _Phase.form;
      });
    } on KarantinFaceException catch (e) {
      _fail(e.message);
    } catch (_) {
      _fail('Karantin ID bilan bogʻlanib boʻlmadi. Qayta urinib koʻring.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.error;
      _errorMessage = message;
    });
  }

  Future<void> _onFormSubmit(String identifier, bool isPnfl) async {
    _identifier = identifier;
    _isPnfl = isPnfl;

    final token = _session?.token;
    if (token != null && token.isNotEmpty) {
      unawaited(
        _dataSource.notifyLogin(token: token, passportNumber: identifier),
      );
    }

    await _ensureLocationPermission();
    if (!mounted) return;
    setState(() => _phase = _Phase.face);
  }

  Future<void> _ensureLocationPermission() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
    } catch (_) {
      // Non-fatal.
    }
  }

  Future<void> _onCameraPermissionDenied() async {
    if (!mounted || _permissionDialogOpen) return;
    _permissionDialogOpen = true;

    final goSettings = Platform.isIOS
        ? await showCupertinoDialog<bool>(
            context: context,
            builder: (ctx) => CupertinoAlertDialog(
              title: Text(_strings.cameraPermissionTitle),
              content: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_strings.cameraPermissionBody),
              ),
              actions: [
                CupertinoDialogAction(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    Navigator.of(ctx).pop(false);
                  },
                  child: Text(_strings.cancelAction),
                ),
                CupertinoDialogAction(
                  isDefaultAction: true,
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    Navigator.of(ctx).pop(true);
                  },
                  child: Text(_strings.openSettings),
                ),
              ],
            ),
          )
        : await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(_strings.cameraPermissionTitle),
              content: Text(_strings.cameraPermissionBody),
              actions: [
                TextButton(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    Navigator.of(ctx).pop(false);
                  },
                  child: Text(_strings.cancelAction),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _config.primaryColor,
                  ),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    Navigator.of(ctx).pop(true);
                  },
                  child: Text(_strings.openSettings),
                ),
              ],
            ),
          );

    _permissionDialogOpen = false;
    if (!mounted) return;
    if (goSettings == true) await openAppSettings();
    if (mounted) setState(() => _phase = _Phase.form);
  }

  Future<void> _onCapture(KarantinFacePayload payload) async {
    final session = _session;
    if (session == null) return;

    setState(() => _isUploading = true);
    try {
      final device = await _collector.collect();
      final deviceFields = device.toBackendFields();
      final includeScreens = !session.registerState.isNotDeepened;

      final String redirectTo;
      switch (session.flow) {
        case KarantinFaceFlow.register:
          redirectTo = await _dataSource.submitRegister(
            oneCode: session.code ?? '',
            token: session.registerState.token,
            includeScreens: includeScreens,
            payload: payload,
            deviceFields: deviceFields,
          );
        case KarantinFaceFlow.verifyDocument:
          redirectTo = await _dataSource.submitVerifyDocument(
            token: session.token ?? '',
            includeScreens: includeScreens,
            payload: payload,
            deviceFields: deviceFields,
          );
        case KarantinFaceFlow.login:
          redirectTo = await _dataSource.submitLogin(
            token: session.token ?? '',
            identifier: _identifier,
            isPnfl: _isPnfl,
            includeScreens: includeScreens,
            payload: payload,
            deviceFields: deviceFields,
          );
      }

      final code = await _dataSource.followToCode(redirectTo);
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _isUploaded = true;
        _phase = _Phase.success;
      });
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) Navigator.of(context).pop(code);
    } on KarantinFaceException catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      _showError(e.message);
      if (_shouldReturnToForm(e.message)) {
        setState(() => _phase = _Phase.form);
        return;
      }
      rethrow;
    } catch (_) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      _showError('Nomaʼlum xatolik. Qaytadan urinib koʻring.');
      rethrow;
    }
  }

  bool _shouldReturnToForm(String message) {
    final lower = message.toLowerCase();
    return _nonFaceTerms.any(lower.contains);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: _errorColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onLamp = _isCameraPhase && _torchOn;
    final foreground = _isCameraPhase
        ? (onLamp ? const Color(0xFF0E1116) : Colors.white)
        : Colors.white;

    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(
        title: Text(_strings.appBarTitle),
        // Over the camera the bar carries nothing but the close button, so it
        // has no reason to draw a green band across the dark page.
        backgroundColor:
            _isCameraPhase ? Colors.transparent : _config.primaryColor,
        foregroundColor: foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle:
            onLamp ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop();
          },
        ),
      ),
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
        color: _pageColor ?? Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.04),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  // face and success share one key so the live scanner (and its
                  // camera) is never torn down between those phases.
                  child: KeyedSubtree(
                    key: ValueKey(
                      _phase == _Phase.success ? _Phase.face : _phase,
                    ),
                    child: _buildBody(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _Phase.loading:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 80),
          child: Center(
            child: CircularProgressIndicator(color: _config.primaryColor),
          ),
        );
      case _Phase.error:
        return _ErrorView(
          message: _errorMessage,
          onRetry: _loadSession,
          color: _config.primaryColor,
          retryLabel: _strings.retryAction,
        );
      case _Phase.form:
        return KarantinPassportForm(
          systemName: _session?.name,
          primaryColor: _config.primaryColor,
          strings: _strings,
          onSubmit: _onFormSubmit,
        );
      case _Phase.face:
      case _Phase.success:
        return KarantinFaceScanner(
          onCapture: _onCapture,
          isUploading: _isUploading,
          isUploaded: _isUploaded,
          onError: _showError,
          onPermissionDenied: _onCameraPermissionDenied,
          onTorchChanged: (on) {
            if (mounted) setState(() => _torchOn = on);
          },
        );
    }
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.color,
    required this.retryLabel,
  });

  final String message;
  final VoidCallback onRetry;
  final Color color;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: _errorColor, size: 56),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              HapticFeedback.mediumImpact();
              onRetry();
            },
            style: FilledButton.styleFrom(backgroundColor: color),
            icon: const Icon(Icons.refresh),
            label: Text(retryLabel),
          ),
        ],
      ),
    );
  }
}

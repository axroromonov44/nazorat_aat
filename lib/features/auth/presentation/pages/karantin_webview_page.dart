import 'dart:io';
import 'dart:math';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/karantin_config.dart';

/// Debug-only tracing. `debugPrint` writes in release builds too, and these
/// lines carry URLs and authorization codes.
void _log(String message) {
  if (kDebugMode) debugPrint(message);
}

const List<String> _iosUserAgents = [
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 '
      'Safari/604.1',
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/125.0.6422.80 '
      'Mobile/15E148 Safari/604.1',
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
      'YaBrowser/24.4.0.750.10 Mobile/15E148 Safari/604.1',
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/126.0 Mobile/15E148 '
      'Safari/605.1.15',
];

const List<String> _androidUserAgents = [
  'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/125.0.0.0 Mobile Safari/537.36',
  'Mozilla/5.0 (Linux; Android 14; SM-G991B) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/125.0.0.0 YaBrowser/24.4.0.750.10 '
      'Mobile Safari/537.36',
  'Mozilla/5.0 (Linux; Android 14; SM-G991B) AppleWebKit/537.36 '
      '(KHTML, like Gecko) SamsungBrowser/25.0 Chrome/121.0.6167.164 '
      'Mobile Safari/537.36',
  'Mozilla/5.0 (Android 14; Mobile; rv:126.0) Gecko/126.0 Firefox/126.0',
  'Mozilla/5.0 (Linux; Android 14; SM-G991B) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36 '
      'OPR/79.0.4160.68080',
  'Mozilla/5.0 (Linux; Android 14; SM-G991B) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36 '
      'EdgA/125.0.2535.51',
];

String _pickUserAgent() {
  final agents = Platform.isIOS ? _iosUserAgents : _androidUserAgents;
  return agents[Random().nextInt(agents.length)];
}

class KarantinWebViewPage extends StatefulWidget {
  const KarantinWebViewPage({super.key});

  @override
  State<KarantinWebViewPage> createState() => _KarantinWebViewPageState();
}

class _KarantinWebViewPageState extends State<KarantinWebViewPage> {
  WebViewController? _controller;
  bool _isLoading = true;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  Future<void> _initController() async {
    if (!Platform.isIOS) {
      final statuses = await [
        Permission.camera,
        Permission.microphone,
      ].request();
      final cameraStatus = statuses[Permission.camera];
      if (cameraStatus == PermissionStatus.permanentlyDenied && mounted) {
        await _showPermissionDeniedDialog();
      }
    }

    PlatformWebViewControllerCreationParams params =
        const PlatformWebViewControllerCreationParams();
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params =
          WebKitWebViewControllerCreationParams.fromPlatformWebViewControllerCreationParams(
            params,
            allowsInlineMediaPlayback: true,
            mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
          );
    }

    final controller = WebViewController.fromPlatformCreationParams(
      params,
      onPermissionRequest: (request) {
        _log('[KarantinID] permission request: ${request.types}');
        request.grant();
      },
    );

    await controller.setUserAgent(_pickUserAgent());

    if (controller.platform is AndroidWebViewController) {
      await (controller.platform as AndroidWebViewController)
          .setOnShowFileSelector(_onShowFileSelector);
    }

    final authUrl = KarantinIdConfig.buildAuthorizationUrl();
    _log('[KarantinID] authorization url: $authUrl');
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (url) {
          _log('[KarantinID] page started: $url');
          if (mounted) setState(() => _isLoading = true);
        },
        onPageFinished: (url) {
          _log('[KarantinID] page finished: $url');
          if (mounted) setState(() => _isLoading = false);
        },
        onWebResourceError: (error) {
          _log(
            'code=${error.errorCode} desc=${error.description} '
            'url=${error.url} isMainFrame=${error.isForMainFrame}',
          );
        },
        onNavigationRequest: _onNavigationRequest,
      ),
    );
    await controller.loadRequest(Uri.parse(authUrl));

    if (mounted) {
      setState(() => _controller = controller);
    }
  }

  Future<List<String>> _onShowFileSelector(FileSelectorParams params) async {
    _log(
      '[KarantinID] file selector requested, capture=${params.isCaptureEnabled}',
    );
    final picker = ImagePicker();
    final wantsCamera =
        params.isCaptureEnabled ||
        params.acceptTypes.any((type) => type.startsWith('image/')) ||
        params.acceptTypes.any((type) => type.startsWith('video/'));
    final isVideo = params.acceptTypes.any((type) => type.startsWith('video/'));

    final XFile? file = isVideo
        ? await picker.pickVideo(
            source: wantsCamera ? ImageSource.camera : ImageSource.gallery,
          )
        : await picker.pickImage(
            source: wantsCamera ? ImageSource.camera : ImageSource.gallery,
          );

    if (file == null) return [];
    return [Uri.file(file.path).toString()];
  }

  Future<void> _showPermissionDeniedDialog() {
    return showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('cameraPermissionTitle'.tr()),
        content: Text('cameraPermissionBody'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('cancelAction'.tr()),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            child: Text('openSettings'.tr()),
          ),
        ],
      ),
    );
  }

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    _log('[KarantinID] navigation request: ${request.url}');
    if (_handled || !request.url.startsWith(KarantinIdConfig.redirectUri)) {
      return NavigationDecision.navigate;
    }
    _handled = true;
    final code = Uri.parse(request.url).queryParameters['code'];
    _log('[KarantinID] redirect caught, code=$code');
    Navigator.of(context).pop(code);
    return NavigationDecision.prevent;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('karantinIdPageTitle'.tr()),
        backgroundColor: kGreen,
        foregroundColor: kWhite,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          if (_controller != null) WebViewWidget(controller: _controller!),
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: kGreen)),
        ],
      ),
    );
  }
}

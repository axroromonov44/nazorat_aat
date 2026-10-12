import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacings.dart';
import '../../../home/presentation/widgets/notification_bell_button.dart';

const _forecastUrl = 'https://akk.karantin.uz/api/v2/common/url/predict/';

class WeatherPage extends StatefulWidget {
  const WeatherPage({super.key});

  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  late final WebViewController _controller;
  bool _isLoading = true;

  /// Pushing a route over the WebView and popping it again can leave the
  /// native view in the tree with nothing drawn in it — the web page is still
  /// alive, its rendering surface is not. A layout change is what makes a
  /// platform view redraw, so one pixel for one frame brings it back. The
  /// alternative, reloading the URL, throws away the forecast the inspector
  /// was reading and needs the network they may not have.
  double _redrawNudge = 0;

  Future<void> _redrawWebView() async {
    if (!mounted) return;
    setState(() => _redrawNudge = 1);
    await Future<void>.delayed(const Duration(milliseconds: 32));
    if (mounted) setState(() => _redrawNudge = 0);
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (url) {
            if (!mounted) return;
            setState(() => _isLoading = false);
            unawaited(_injectBottomSpacer());
          },
          onNavigationRequest: _onNavigationRequest,
        ),
      );
    unawaited(_initWebView());
  }

  Future<void> _initWebView() async {
    // The forecast page calls navigator.geolocation on load. On Android the
    // WebView re-prompts every time unless we answer the geolocation request
    // ourselves — grant it once and retain it for the origin so it stops asking.
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      await platform.setGeolocationPermissionsPromptCallbacks(
        onShowPrompt: (request) async =>
            const GeolocationPermissionsResponse(allow: true, retain: true),
      );
    }
    await _controller.loadRequest(Uri.parse(_forecastUrl));
  }

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    if (request.url.toLowerCase().endsWith('.pdf')) {
      launchUrl(Uri.parse(request.url), mode: LaunchMode.externalApplication);
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  // The WebView fills the whole screen and sits behind the floating bottom
  // nav bar (`MainPage` uses `extendBody: true`), so the page's own last
  // ~76dp of content would otherwise be permanently covered by that opaque
  // bar. Rather than shrinking the WebView (which leaves a dead gap above
  // the bar), we pad the page's own scroll area so every bit of real
  // content can be scrolled clear of the covered strip.
  Future<void> _injectBottomSpacer() async {
    if (!mounted) return;
    final clearance =
        kFloatingNavBarClearance + MediaQuery.of(context).padding.bottom;
    await _controller.runJavaScript('''
      (function() {
        var s = document.getElementById('__nav_bar_spacer__');
        if (!s) {
          s = document.createElement('div');
          s.id = '__nav_bar_spacer__';
          s.style.width = '100%';
          s.style.pointerEvents = 'none';
          document.body.appendChild(s);
        }
        s.style.height = '${clearance}px';
      })();
    ''');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('weatherTitle'.tr()),
        centerTitle: true,
        actions: [NotificationBellButton(onReturn: _redrawWebView)],
      ),
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: _redrawNudge),
            child: WebViewWidget(controller: _controller),
          ),
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: kGreen)),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'dart:math' as math;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/haptic.dart';
import '../bloc/auth_bloc.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:karantin_face_sdk/karantin_face_sdk.dart';
import '../../../../core/constants/karantin_config.dart';
import '../../../../core/network/diagnostics_interceptor.dart';
import '../../../../core/network/dio_debug_logger.dart';
import '../pages/oneid_webview_page.dart';
import 'login_metrics.dart';

class LoginForm extends StatefulWidget {
  const LoginForm({super.key, required this.metrics});

  /// Sizes derived from the height the login screen has to work with.
  final LoginMetrics metrics;

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      context.read<AuthBloc>().add(
        AuthLoginRequested(
          username: _usernameController.text.trim(),
          password: _passwordController.text,
        ),
      );
    }
  }

  void _startKarantinLogin() {
    hapticMedium();
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _RedirectDialog(
        messageKey: 'karantinRedirectMsg',
        descKey: 'karantinRedirectDesc',
        badgeText: 'id.karantin.uz',
        accentColor: kGreen,
        accentLight: kGreenLight,
        badgeIcon: Icons.eco_rounded,
        onComplete: _openKarantinWebView,
      ),
    );
  }

  Future<void> _openKarantinWebView() async {
    final authBloc = context.read<AuthBloc>();
    final code = await KarantinFace.authenticate(
      context,
      config: KarantinFaceConfig(
        clientId: KarantinIdConfig.clientId,
        redirectUri: KarantinIdConfig.redirectUri,
        primaryColor: kGreen,
        // Every step of the login lands in the diagnostics log, like the rest
        // of the app's traffic. Without this a refused login left nothing
        // behind: the one failure an inspector cannot work around was also the
        // one the exported log said nothing about.
        interceptors: [
          DiagnosticsInterceptor(),
          // The package carries no logger of its own, so the console gets the
          // same compact lines as the rest of the app's traffic — and only in
          // debug builds.
          if (kDebugMode) CompactDioLogger(),
        ],
      ),
    );
    if (kDebugMode) debugPrint('[KarantinID] face auth returned a code');
    if (code != null && code.isNotEmpty) {
      authBloc.add(AuthKarantinLoginRequested(code: code));
    } else {
      if (kDebugMode) debugPrint('[KarantinID] no code, login aborted');
    }
  }

  void _startOneIdLogin() {
    hapticMedium();
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _RedirectDialog(
        messageKey: 'oneIdRedirectMsg',
        descKey: 'oneIdRedirectDesc',
        badgeText: 'id.egov.uz',
        accentColor: const Color(0xFF2D159A),
        accentLight: const Color(0xFF4B30C5),
        badgeIcon: Icons.fingerprint_rounded,
        onComplete: _openOneIdWebView,
      ),
    );
  }

  Future<void> _openOneIdWebView() async {
    final authBloc = context.read<AuthBloc>();
    final code = await Navigator.of(context, rootNavigator: true).push<String?>(
      MaterialPageRoute(builder: (_) => const OneIdWebViewPage()),
    );
    if (code != null && code.isNotEmpty) {
      authBloc.add(AuthGovLoginRequested(code: code));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<AuthBloc>().state is AuthLoading;
    final metrics = widget.metrics;
    // Trim the field's own padding on short screens; the theme's roomier value
    // is kept everywhere else.
    final fieldPadding = EdgeInsets.symmetric(
      horizontal: 16,
      vertical: metrics.fieldPaddingV,
    );

    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            controller: _usernameController,
            keyboardType: TextInputType.text,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'phoneLabel'.tr(),
              prefixIcon: const Icon(Icons.person_outline_rounded),
              contentPadding: fieldPadding,
            ),
            validator: (v) =>
                (v == null || v.isEmpty) ? 'phoneRequired'.tr() : null,
          ),
          SizedBox(height: metrics.fieldGap),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'passwordLabel'.tr(),
              prefixIcon: const Icon(Icons.lock_outline),
              contentPadding: fieldPadding,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: kGreen,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: (v) =>
                (v == null || v.length < 6) ? 'passwordMinLength'.tr() : null,
          ),
          SizedBox(height: metrics.submitGap),
          ElevatedButton(
            onPressed: hTapMedium(isLoading ? null : _submit),
            style: ElevatedButton.styleFrom(
              minimumSize: Size.fromHeight(metrics.buttonHeight),
            ),
            child: isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: kWhite,
                    ),
                  )
                : Text('loginButton'.tr()),
          ),
          SizedBox(height: metrics.dividerGap),
          const _OrDivider(),
          SizedBox(height: metrics.dividerGap),
          _OneIdButton(
            onTap: _startOneIdLogin,
            paddingV: metrics.providerPaddingV,
          ),
          SizedBox(height: metrics.providerGap),
          _KarantinButton(
            onTap: _startKarantinLogin,
            paddingV: metrics.providerPaddingV,
          ),
        ],
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    return Row(
      children: [
        Expanded(child: Divider(color: color)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'or'.tr(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Divider(color: color)),
      ],
    );
  }
}

class _OneIdButton extends StatelessWidget {
  const _OneIdButton({required this.onTap, required this.paddingV});

  final VoidCallback onTap;
  final double paddingV;

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF2D159A);
    const lightColor = Color(0xFF4B30C5);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [color, lightColor],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(70),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: hTap(onTap),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: paddingV),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/one-id.png',
                  height: 24,
                  filterQuality: FilterQuality.high,
                ),
                const SizedBox(width: 10),
                // Keep the label on one line whatever the language: wrapping
                // used to make the button grow and push the page below the
                // fold on narrow phones.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'oneIdLoginSuffix'.tr(),
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KarantinButton extends StatelessWidget {
  const _KarantinButton({required this.onTap, required this.paddingV});

  final VoidCallback onTap;
  final double paddingV;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kGreen, kGreenLight],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: kGreen.withAlpha(70),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: hTap(onTap),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: paddingV),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Both labels stay on one line (the Russian and Uzbek strings
                // are long enough to wrap on a narrow phone, which made this
                // button nearly twice as tall as intended).
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'karantinIdLogin'.tr(),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'faceIdLogin'.tr(),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color: Colors.white.withAlpha(200),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RedirectDialog extends StatefulWidget {
  const _RedirectDialog({
    required this.messageKey,
    required this.descKey,
    required this.badgeText,
    required this.accentColor,
    required this.accentLight,
    required this.badgeIcon,
    required this.onComplete,
  });

  final String messageKey;
  final String descKey;
  final String badgeText;
  final Color accentColor;
  final Color accentLight;
  final IconData badgeIcon;
  final VoidCallback onComplete;

  @override
  State<_RedirectDialog> createState() => _RedirectDialogState();
}

class _RedirectDialogState extends State<_RedirectDialog>
    with SingleTickerProviderStateMixin {
  static const _totalSeconds = 3;
  late final AnimationController _ctrl;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: _totalSeconds * 1000),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) _complete();
        });
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _complete() {
    if (_completed) return;
    _completed = true;
    if (mounted) Navigator.pop(context);
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = widget.accentColor;
    final accentLight = widget.accentLight;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      backgroundColor: isDark ? const Color(0xFF1A1A1C) : Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RedirectDialogHeader(
              accentColor: accentColor,
              accentLight: accentLight,
              badgeText: widget.badgeText,
              badgeIcon: widget.badgeIcon,
            ),
            const SizedBox(height: 20),
            Text(
              widget.messageKey.tr(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
                letterSpacing: -0.3,
                height: 1.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              widget.descKey.tr(),
              style: TextStyle(
                fontSize: 12.5,
                color: colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                final remaining = (_totalSeconds * (1 - _ctrl.value))
                    .ceil()
                    .clamp(0, _totalSeconds);
                return Column(
                  children: [
                    _CircleCountdown(
                      progress: 1 - _ctrl.value,
                      remaining: remaining,
                      color: accentColor,
                      colorLight: accentLight,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'redirectInSec'.tr(namedArgs: {'count': '$remaining'}),
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RedirectDialogHeader extends StatelessWidget {
  const _RedirectDialogHeader({
    required this.accentColor,
    required this.accentLight,
    required this.badgeText,
    required this.badgeIcon,
  });

  final Color accentColor;
  final Color accentLight;
  final String badgeText;
  final IconData badgeIcon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accentColor.withAlpha(isDark ? 35 : 18),
            accentLight.withAlpha(isDark ? 25 : 12),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accentColor.withAlpha(50)),
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [accentColor, accentLight],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withAlpha(100),
                      blurRadius: 18,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.verified_user_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(25),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Icon(badgeIcon, color: accentColor, size: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(isDark ? 15 : 200),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accentColor.withAlpha(60)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, size: 11, color: accentColor),
                const SizedBox(width: 5),
                Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleCountdown extends StatelessWidget {
  const _CircleCountdown({
    required this.progress,
    required this.remaining,
    required this.color,
    required this.colorLight,
  });

  /// 1.0 = full (just started), 0.0 = empty (about to continue).
  final double progress;
  final int remaining;
  final Color color;
  final Color colorLight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(96, 96),
            painter: _RingPainter(
              progress: progress.clamp(0.0, 1.0),
              color: color,
              colorLight: colorLight,
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: ScaleTransition(
                scale: Tween(begin: 0.7, end: 1.0).animate(anim),
                child: child,
              ),
            ),
            child: Text(
              '$remaining',
              key: ValueKey(remaining),
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w800,
                color: color,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.color,
    required this.colorLight,
  });

  final double progress;
  final Color color;
  final Color colorLight;

  static const _stroke = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - _stroke / 2 - 1;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withAlpha(28)
        ..strokeWidth = _stroke
        ..style = PaintingStyle.stroke,
    );

    if (progress > 0.001) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        progress * 2 * math.pi,
        false,
        Paint()
          ..shader = SweepGradient(
            colors: [color, colorLight],
            startAngle: 0,
            endAngle: 2 * math.pi,
            transform: const GradientRotation(-math.pi / 2),
          ).createShader(rect)
          ..strokeWidth = _stroke
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

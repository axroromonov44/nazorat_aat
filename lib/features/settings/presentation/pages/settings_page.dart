import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/map/tile_cache_service.dart';
import '../../../../core/notifications/app_notification.dart';
import '../../../../core/notifications/notification_center.dart';
import '../../../../core/observability/crash_reporting.dart';
import '../../../../core/observability/diagnostics_log.dart';
import '../../../../core/theme/theme_cubit.dart';
import '../../../../core/utils/haptic.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/bordered_tile.dart';

/// Where an inspector is asked to send the diagnostics log. The app cannot
/// deliver it to a Telegram account by itself — the Bot API can only write to
/// a chat that has already started the bot, and a bot token has no business in
/// a public repository — so the share sheet hands the file to Telegram and the
/// inspector picks this account.
const kDiagnosticsTelegram = '@iamakhrror';

/// Everything that changes how the app behaves rather than what it shows about
/// the inspector: the language, the theme, the offline map cache and the
/// diagnostics log. It used to be a bottom sheet reached from the profile,
/// which left no room for anything that needs explaining.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final hPad = context.spaceLg;

    return Scaffold(
      appBar: AppBar(title: Text('appSettingsLabel'.tr()), centerTitle: false),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          hPad,
          context.spaceMd,
          hPad,
          context.spaceXl + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          const BorderedTile(child: _LanguageTile()),
          SizedBox(height: context.spaceSm),
          BorderedTile(
            child: BlocBuilder<ThemeCubit, ThemeMode>(
              builder: (context, mode) =>
                  _ThemeTile(isDark: mode == ThemeMode.dark),
            ),
          ),
          SizedBox(height: context.spaceSm),
          const BorderedTile(child: _ClearMapCacheTile()),
          SizedBox(height: context.spaceSm),
          const BorderedTile(child: _SendDiagnosticsTile()),
        ],
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile();

  static const _langs = [
    (code: 'uz', label: "O'zbek tili", flag: '🇺🇿'),
    (code: 'ru', label: 'Русский язык', flag: '🇷🇺'),
    (code: 'en', label: 'English', flag: '🇬🇧'),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final current = context.locale.languageCode;
    final currentLang = _langs.firstWhere(
      (l) => l.code == current,
      orElse: () => _langs.first,
    );

    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: const Icon(Icons.language_rounded, color: kGreen),
      title: Text('languageLabel'.tr()),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(currentLang.flag, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text(
            currentLang.label,
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.chevron_right_rounded,
            color: colorScheme.onSurfaceVariant,
          ),
        ],
      ),
      onTap: () => _showLanguagePicker(context),
    );
  }
}

void _showLanguagePicker(BuildContext context) {
  final current = context.locale.languageCode;
  final langs = _LanguageTile._langs;
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(sheetContext).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            for (int i = 0; i < langs.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              BorderedTile(
                child: ListTile(
                  leading: Text(
                    langs[i].flag,
                    style: const TextStyle(fontSize: 20),
                  ),
                  title: Text(langs[i].label),
                  trailing: langs[i].code == current
                      ? const Icon(Icons.check_rounded, color: kGreen)
                      : null,
                  onTap: () {
                    hapticSelect();
                    context.setLocale(Locale(langs[i].code));
                    Navigator.of(sheetContext).pop();
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({required this.isDark});
  final bool isDark;

  void _toggle(BuildContext context) {
    hapticSelect();
    context.read<ThemeCubit>().toggle();
  }

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    visualDensity: VisualDensity.compact,
    leading: Icon(
      isDark ? Icons.nightlight_round : Icons.wb_sunny_rounded,
      color: kGreen,
    ),
    title: Text(isDark ? 'darkMode'.tr() : 'lightMode'.tr()),
    trailing: Switch.adaptive(
      value: isDark,
      activeThumbColor: kGreen,
      onChanged: (_) => _toggle(context),
    ),
    onTap: () => _toggle(context),
  );
}

class _SendDiagnosticsTile extends StatefulWidget {
  const _SendDiagnosticsTile();

  @override
  State<_SendDiagnosticsTile> createState() => _SendDiagnosticsTileState();
}

/// Lets an inspector who reports "it does not work" send the log off their
/// phone with one tap. Because the app runs offline, errors never reach the
/// developer on their own, and this is the most direct route.
class _SendDiagnosticsTileState extends State<_SendDiagnosticsTile> {
  bool _busy = false;

  Future<void> _send() async {
    hapticSelect();
    setState(() => _busy = true);
    try {
      final file = await DiagnosticsLog.exportToFile();
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Nazorat AAT — diagnostika jurnali',
          text: 'Nazorat AAT diagnostika jurnali — $kDiagnosticsTelegram',
        ),
      );
    } catch (error, stack) {
      await CrashReporting.recordNonFatal(
        error,
        stack,
        reason: 'Diagnostics log could not be shared',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('diagnosticsFailed'.tr())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: const Icon(Icons.bug_report_outlined, color: kGreen),
      title: Text('sendDiagnostics'.tr()),
      subtitle: Text(
        'sendDiagnosticsHint'.tr(namedArgs: {'handle': kDiagnosticsTelegram}),
        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
      ),
      trailing: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: kGreen),
            )
          : Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
      onTap: _busy ? null : _send,
    );
  }
}

class _ClearMapCacheTile extends StatefulWidget {
  const _ClearMapCacheTile();

  @override
  State<_ClearMapCacheTile> createState() => _ClearMapCacheTileState();
}

class _ClearMapCacheTileState extends State<_ClearMapCacheTile> {
  late Future<int> _sizeFuture = TileCacheService.cacheSizeBytes();
  bool _clearing = false;

  Future<void> _clear() async {
    hapticSelect();
    final confirmed = await _showClearCacheConfirmDialog(context);
    if (!confirmed || !mounted) return;

    setState(() => _clearing = true);
    await TileCacheService.clearCache();
    NotificationCenter.items.value = NotificationCenter.items.value
        .where((n) => n is! OfflineDownloadNotification)
        .toList();
    if (!mounted) return;
    setState(() {
      _clearing = false;
      _sizeFuture = TileCacheService.cacheSizeBytes();
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('clearMapCacheSuccess'.tr())));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: const Icon(Icons.delete_outline_rounded, color: kGreen),
      title: Text('clearMapCache'.tr()),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FutureBuilder<int>(
            future: _sizeFuture,
            builder: (context, snapshot) => Text(
              snapshot.hasData ? formatMapCacheSize(snapshot.data!) : '…',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 4),
          if (_clearing)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: kGreen),
            )
          else
            Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
        ],
      ),
      onTap: _clearing ? null : _clear,
    );
  }
}

Future<bool> _showClearCacheConfirmDialog(BuildContext context) {
  if (Platform.isIOS) {
    return showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('clearMapCacheConfirmTitle'.tr()),
        content: Text('clearMapCacheConfirmBody'.tr()),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('cancelAction'.tr()),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('clearMapCache'.tr()),
          ),
        ],
      ),
    ).then((value) => value ?? false);
  }

  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('clearMapCacheConfirmTitle'.tr()),
      content: Text('clearMapCacheConfirmBody'.tr()),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('cancelAction'.tr()),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(
            'clearMapCache'.tr(),
            style: const TextStyle(color: kError, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  ).then((value) => value ?? false);
}

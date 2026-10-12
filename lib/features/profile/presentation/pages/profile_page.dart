import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacings.dart';
import '../../../../core/widgets/bordered_tile.dart';
import '../../../../core/storage/session_cleaner.dart';
import '../../../../core/utils/haptic.dart';
import '../../../../core/utils/responsive.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/bloc/profile_cubit.dart';
import '../../../auth/presentation/widgets/role_badge.dart';
import '../widgets/profile_avatar.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<ProfileCubit>().state;
    final hPad = context.spaceLg;
    final displayName = (user?.fullName.isNotEmpty ?? false)
        ? user!.fullName
        : (user?.username ?? '');

    return Scaffold(
      appBar: AppBar(
        title: Text('profileTitle'.tr()),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            tooltip: 'appSettingsLabel'.tr(),
            onPressed: () {
              hapticSelect();
              context.push('/settings');
            },
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          hPad,
          context.spaceMd,
          hPad,
          kFloatingNavBarClearance + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          _IdentityCard(user: user, displayName: displayName),
          SizedBox(height: context.spaceMd),
          const BorderedTile(child: _PublicOfferTile()),
          SizedBox(height: context.spaceSm),
          const BorderedTile(child: _SupportTile()),
          SizedBox(height: context.spaceXl),
          const BorderedTile(child: _LogoutTile()),
          SizedBox(height: context.spaceMd),
          const _AppVersionLabel(),
        ],
      ),
    );
  }
}

const _telegramSupportUrl = 'https://t.me/dalanazorat';

Future<void> _openExternalLink(BuildContext context, String url) async {
  hapticSelect();
  final launched = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  );
  if (!launched && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('linkOpenFailed'.tr())));
  }
}

class _PublicOfferTile extends StatelessWidget {
  const _PublicOfferTile();

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    visualDensity: VisualDensity.compact,
    leading: const Icon(Icons.description_rounded, color: kGreen),
    title: Text('publicOfferLabel'.tr()),
    trailing: Icon(
      Icons.chevron_right_rounded,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
    onTap: () => _openExternalLink(context, _telegramSupportUrl),
  );
}

class _SupportTile extends StatelessWidget {
  const _SupportTile();

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    visualDensity: VisualDensity.compact,
    leading: const Icon(Icons.support_agent_rounded, color: kGreen),
    title: Text('supportLabel'.tr()),
    trailing: Icon(
      Icons.chevron_right_rounded,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
    onTap: () => _openExternalLink(context, _telegramSupportUrl),
  );
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.user, required this.displayName});

  final User? user;
  final String displayName;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final user = this.user;
    final imageUrl = user?.imageUrl;
    final hasPhoto = imageUrl != null && imageUrl.isNotEmpty;
    final subtitle = [
      if (user?.position?.isNotEmpty ?? false) user!.position!,
      if (user?.phone?.isNotEmpty ?? false) user!.phone!,
    ].join(' • ');
    final accent = roleColor(user?.inspectorRole);

    return GestureDetector(
      onTap: user == null
          ? null
          : () {
              hapticSelect();
              _showProfileDetailsSheet(context, user);
            },
      child: Container(
        padding: EdgeInsets.all(context.spaceLg),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colorScheme.outlineVariant),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: hasPhoto
                  ? () {
                      hapticSelect();
                      _showPhotoPreview(context, imageUrl);
                    }
                  : null,
              child: ProfileAvatar(
                imageUrl: imageUrl,
                size: context.rs(72.0, 88.0),
              ),
            ),
            SizedBox(width: context.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (displayName.isNotEmpty)
                    Text(
                      displayName,
                      style: TextStyle(
                        fontSize: context.rs(19.0, 22.0),
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (user != null) ...[
                    const SizedBox(height: 8),
                    RoleBadge(role: user.inspectorRole),
                    const SizedBox(height: 6),
                    Text(
                      'tapForDetails'.tr(),
                      style: TextStyle(
                        fontSize: 12,
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (user != null)
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}

void _showProfileDetailsSheet(BuildContext context, User user) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    constraints: context.isTablet
        ? BoxConstraints(maxWidth: context.sheetMaxWidth)
        : null,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ProfileDetailsSheet(user: user),
  );
}

void _showPhotoPreview(BuildContext context, String imageUrl) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (context, animation, secondaryAnimation) => FadeTransition(
        opacity: animation,
        child: _PhotoPreviewPage(imageUrl: imageUrl),
      ),
    ),
  );
}

class _PhotoPreviewPage extends StatelessWidget {
  const _PhotoPreviewPage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.broken_image_rounded,
                    color: Colors.white54,
                    size: 64,
                  ),
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 12,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileDetailsSheet extends StatelessWidget {
  const _ProfileDetailsSheet({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).padding.bottom;
    final birthDate = _formattedBirthDate(user.birthDate);
    final gender = _localizedGender(user.gender);

    final rows = <Widget>[
      _DetailRow(label: 'detailFullName'.tr(), value: user.fullName),
      if (user.fullNameCyrillic?.isNotEmpty ?? false)
        _DetailRow(
          label: 'detailFullNameCyrillic'.tr(),
          value: user.fullNameCyrillic!,
        ),
      _DetailRow(label: 'detailUsername'.tr(), value: user.username),
      _DetailRow(
        label: 'roleSectionLabel'.tr(),
        value: roleLabel(user.inspectorRole),
      ),
      if (user.position?.isNotEmpty ?? false)
        _DetailRow(label: 'detailPosition'.tr(), value: user.position!),
      if (user.phone?.isNotEmpty ?? false)
        _DetailRow(label: 'detailPhone'.tr(), value: user.phone!),
      if (user.email?.isNotEmpty ?? false)
        _DetailRow(label: 'detailEmail'.tr(), value: user.email!),
      if (user.pinfl?.isNotEmpty ?? false)
        _DetailRow(
          label: 'detailPinfl'.tr(),
          value: user.pinfl!,
          copyable: true,
        ),
      if (user.passportNumber?.isNotEmpty ?? false)
        _DetailRow(
          label: 'detailPassport'.tr(),
          value: user.passportNumber!,
          copyable: true,
        ),
      if (birthDate != null)
        _DetailRow(label: 'detailBirthDate'.tr(), value: birthDate),
      if (gender != null) _DetailRow(label: 'detailGender'.tr(), value: gender),
      if (user.regionName?.isNotEmpty ?? false)
        _DetailRow(label: 'detailRegion'.tr(), value: user.regionName!),
      if (user.districtName?.isNotEmpty ?? false)
        _DetailRow(label: 'detailDistrict'.tr(), value: user.districtName!),
      if (user.address?.isNotEmpty ?? false)
        _DetailRow(label: 'detailAddress'.tr(), value: user.address!),
    ];

    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(20, 14, 20, bottom + 20),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'profileDetailsTitle'.tr(),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      if (i > 0)
                        Divider(height: 1, color: colorScheme.outlineVariant),
                      rows[i],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.copyable = false,
  });

  final String label;
  final String value;
  final bool copyable;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: value));
    hapticSelect();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('copiedToClipboard'.tr(namedArgs: {'label': label})),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          if (copyable)
            IconButton(
              onPressed: () => _copy(context),
              icon: const Icon(Icons.copy_rounded, size: 18),
              color: kGreen,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }
}

String? _formattedBirthDate(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  return DateFormat('dd.MM.yyyy').format(parsed);
}

String? _localizedGender(String? raw) {
  switch (raw) {
    case 'male':
      return 'genderMale'.tr();
    case 'female':
      return 'genderFemale'.tr();
    default:
      return null;
  }
}

Future<bool> _showLogoutConfirmDialog(BuildContext context) {
  if (Platform.isIOS) {
    return showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('logoutConfirmTitle'.tr()),
        content: Text('logoutConfirmBody'.tr()),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('cancelAction'.tr()),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('logout'.tr()),
          ),
        ],
      ),
    ).then((value) => value ?? false);
  }

  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('logoutConfirmTitle'.tr()),
      content: Text('logoutConfirmBody'.tr()),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('cancelAction'.tr()),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(
            'logout'.tr(),
            style: const TextStyle(color: kError, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  ).then((value) => value ?? false);
}

class _LogoutTile extends StatefulWidget {
  const _LogoutTile();

  @override
  State<_LogoutTile> createState() => _LogoutTileState();
}

class _LogoutTileState extends State<_LogoutTile> {
  bool _loggingOut = false;

  Future<void> _logout() async {
    hapticSelect();
    final confirmed = await _showLogoutConfirmDialog(context);
    if (!confirmed || !mounted) return;

    setState(() => _loggingOut = true);
    await SessionCleaner.wipe();

    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: _loggingOut
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: kError),
            )
          : const Icon(Icons.logout_rounded, color: kError),
      title: Text(
        'logout'.tr(),
        style: const TextStyle(color: kError, fontWeight: FontWeight.w600),
      ),
      onTap: _loggingOut ? null : _logout,
    );
  }
}

class _AppVersionLabel extends StatelessWidget {
  const _AppVersionLabel();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        final text = info == null ? '' : 'v${info.version}+${info.buildNumber}';
        return Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: context.rs(11.0, 13.0),
            color: colorScheme.onSurfaceVariant,
          ),
        );
      },
    );
  }
}

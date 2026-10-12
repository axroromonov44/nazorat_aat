import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/notifications/app_notification.dart';
import '../../../../core/notifications/notification_center.dart';
import '../../../../core/utils/haptic.dart';
import 'notifications_panel.dart';

class NotificationBellButton extends StatelessWidget {
  const NotificationBellButton({super.key, this.onReturn});

  /// Called once the notifications page has been popped. The weather tab uses
  /// it to bring its WebView back: a platform view covered by a route can
  /// return with nothing drawn in it.
  final VoidCallback? onReturn;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<AppNotification>>(
      valueListenable: NotificationCenter.items,
      builder: (context, items, child) => Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            onPressed: hTap(() async {
              await showNotificationsPanel(context);
              onReturn?.call();
            }),
            icon: const Icon(Icons.notifications_active_outlined),
          ),
          if (items.isNotEmpty)
            Positioned(
              top: 6,
              right: 6,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.all(3),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  decoration: BoxDecoration(
                    color: kError,
                    shape: BoxShape.circle,
                    border: Border.all(color: kWhite, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${items.length}',
                    style: const TextStyle(
                      color: kWhite,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

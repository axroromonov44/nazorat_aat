import 'package:flutter/material.dart';

/// The rounded, outlined container every settings-style row sits in.
///
class BorderedTile extends StatelessWidget {
  const BorderedTile({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Material rather than a decorated Container: a ListTile paints its own
    // background and ink splash onto the nearest Material ancestor, so a
    // coloured box in between would swallow the tap ripple (and Flutter
    // asserts about it in debug).
    return Material(
      clipBehavior: Clip.antiAlias,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}

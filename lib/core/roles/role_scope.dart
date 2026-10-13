import 'package:flutter/widgets.dart';

import '../../features/auth/domain/entities/inspector_role.dart';
import 'role_controller.dart';
import 'role_module.dart';
import 'role_registry.dart';

/// Hands the tree the signed-in inspector's module, synchronously.
///
/// Sits above the router, so every route can ask. Rebuilds its dependents when
/// the role changes, which happens at most once per session — on a login, or
/// when `/users/me` corrects what the token said.
class RoleScope extends InheritedNotifier<RoleController> {
  const RoleScope({
    super.key,
    required RoleController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Module the shell builds itself from.
  static RoleModule of(BuildContext context) => moduleFor(roleOf(context));

  static InspectorRole? roleOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RoleScope>();
    assert(scope != null, 'No RoleScope above this widget');
    return scope?.notifier?.value;
  }
}

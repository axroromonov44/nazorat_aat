import 'package:flutter/foundation.dart';

import '../../features/auth/domain/entities/inspector_role.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';

/// The signed-in inspector's role, readable synchronously.
///
/// The shell composes its navigation from the role, and a widget cannot await:
/// resolving it inside `MainPage` meant the shared tab set was built first and
/// replaced a frame later — invisible while every module declares the same
/// tabs, a flicker the moment they differ. So the role is settled before the
/// first route is built, by whoever already knows it: the splash redirect
/// reads it from the stored token, and a login hands it over directly.
///
/// It stays a [ValueNotifier] rather than a bloc because nothing here has
/// states or events — one value, written from three places, read by the tree.
class RoleController extends ValueNotifier<InspectorRole?> {
  RoleController() : super(null);

  /// Reads the role out of the stored access token.
  ///
  /// Takes the repository as an argument instead of holding it so the
  /// controller has no dependencies and tests can drive it directly.
  ///
  /// A failure here is not worth a crash on the splash screen: an unresolved
  /// role means the shared shell, which is also what an unrecognised role code
  /// gets, and `/users/me` will correct it a moment later.
  Future<void> resolveFrom(AuthRepository repository) async {
    try {
      final user = await repository.getCurrentUser();
      value = user?.inspectorRole;
    } catch (_) {
      value = null;
    }
  }

  /// The role as another source now reports it — a fresh login, or `/users/me`
  /// disagreeing with the token because the role was reassigned while the app
  /// was closed. [ValueNotifier] ignores a write that changes nothing, so the
  /// common case costs no rebuild.
  void update(InspectorRole? role) => value = role;
}

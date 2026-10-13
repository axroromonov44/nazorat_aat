import 'role_module.dart';
import 'shared_tabs.dart';

/// What a user sees when the token carries no role code we recognise.
///
/// This is a real case rather than a placeholder: `resolveInspectorRole`
/// returns null instead of guessing an inspectorate, and an inspector in the
/// field cannot wait for the backend to be fixed — so they get the shared
/// screens and nothing inspectorate-specific.
class SharedOnlyModule extends RoleModule {
  const SharedOnlyModule();

  @override
  List<RoleTab> get tabs => const [weatherTab, mapTab, settingsTab];
}

import '../../core/roles/role_module.dart';
import '../../core/roles/shared_tabs.dart';

/// Plant quarantine inspector.
///
/// The tab list is the shared one for now — the inspectorate's own screens
/// (quarantine acts, phytosanitary certificates) land in this folder and are
/// added here, which is the only edit the navigation needs.
class KarantinModule extends RoleModule {
  const KarantinModule();

  @override
  List<RoleTab> get tabs => const [weatherTab, mapTab, settingsTab];
}

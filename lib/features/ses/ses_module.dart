import '../../core/roles/role_module.dart';
import '../../core/roles/shared_tabs.dart';

/// Sanitary-epidemiological service inspector.
///
/// The tab list is the shared one for now — the inspectorate's own screens
/// (lab samples, sanitary inspections) land in this folder and are added here.
class SesModule extends RoleModule {
  const SesModule();

  @override
  List<RoleTab> get tabs => const [weatherTab, mapTab, settingsTab];
}

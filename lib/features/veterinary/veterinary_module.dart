import '../../core/roles/role_module.dart';
import '../../core/roles/shared_tabs.dart';

/// Veterinary inspector.
///
/// The tab list is the shared one for now — the inspectorate's own screens
/// (herds, vaccination records) land in this folder and are added here.
class VeterinaryModule extends RoleModule {
  const VeterinaryModule();

  @override
  List<RoleTab> get tabs => const [weatherTab, mapTab, settingsTab];
}

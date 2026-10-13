import '../../features/auth/domain/entities/inspector_role.dart';
import '../../features/karantin/karantin_module.dart';
import '../../features/ses/ses_module.dart';
import '../../features/veterinary/veterinary_module.dart';
import 'role_module.dart';
import 'shared_only_module.dart';

/// The module the signed-in user's shell is built from.
///
/// Written as an exhaustive switch rather than a lookup map on purpose: adding
/// a fourth inspectorate to [InspectorRole] stops compiling here until its
/// module exists, instead of silently dropping that inspector into the shared
/// shell at runtime, where nobody would notice for weeks.
RoleModule moduleFor(InspectorRole? role) => switch (role) {
  InspectorRole.karantin => const KarantinModule(),
  InspectorRole.veterinary => const VeterinaryModule(),
  InspectorRole.ses => const SesModule(),
  null => const SharedOnlyModule(),
};

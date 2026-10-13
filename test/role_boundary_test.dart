import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nazorat_aat/features/auth/domain/entities/inspector_role.dart';
import 'package:path/path.dart' as p;

/// Keeps the inspectorates from bleeding into each other.
///
/// `docs/ROLES.md` states the two rules; this test is what makes them hold.
/// Without it the architecture is a document somebody read once, and the first
/// `if (role == karantin)` inside a shared screen goes unnoticed.
void main() {
  /// Directory each inspectorate owns, keyed by the enum value's name.
  final roleDirs = {
    for (final role in InspectorRole.values)
      role.name: p.join('lib', 'features', _folderFor(role)),
  };

  /// The only files allowed to name an individual inspectorate.
  const roleAwareFiles = {
    // Defines the inspectorates and maps backend codes onto them.
    'lib/features/auth/domain/entities/inspector_role.dart',
    // Picks the module for the signed-in user; deliberately exhaustive.
    'lib/core/roles/role_registry.dart',
    // The chip in the app bar: one colour, icon and label per inspectorate.
    'lib/features/auth/presentation/widgets/role_badge.dart',
  };

  final dartFiles =
      Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => p.normalize(f.path))
          .toList()
        ..sort();

  test('lib is readable and the role folders exist', () {
    expect(dartFiles, isNotEmpty);
    for (final dir in roleDirs.values) {
      expect(
        Directory(dir).existsSync(),
        isTrue,
        reason: '$dir is missing — every inspectorate owns a folder',
      );
    }
  });

  test('no inspectorate reaches into another one', () {
    for (final file in dartFiles) {
      final owner = roleDirs.entries
          .where((e) => p.isWithin(e.value, file))
          .map((e) => e.key)
          .singleOrNull;

      for (final target in _importsOf(file)) {
        for (final other in roleDirs.entries) {
          if (other.key == owner) continue;
          if (!p.isWithin(other.value, target)) continue;

          // Only the registry composes the inspectorates; anything else
          // importing one is a shared screen quietly growing a role branch.
          expect(
            file,
            'lib/core/roles/role_registry.dart',
            reason:
                '$file imports ${other.key} code (${p.relative(target)}) — '
                'role-specific code stays inside its own folder',
          );
        }
      }
    }
  });

  test('shared code never names a single inspectorate', () {
    final members = RegExp(
      'InspectorRole\\.(${InspectorRole.values.map((r) => r.name).join('|')})',
    );

    for (final file in dartFiles) {
      if (roleAwareFiles.contains(p.toUri(file).path)) continue;
      if (roleDirs.values.any((dir) => p.isWithin(dir, file))) continue;

      final hit = members.firstMatch(File(file).readAsStringSync());
      expect(
        hit,
        isNull,
        reason:
            '$file branches on ${hit?.group(0)} — shared code asks what the '
            'user may do (a module or a capability), not who they are',
      );
    }
  });
}

/// Folder name for an inspectorate. Kept explicit rather than derived from
/// [InspectorRole.name] so renaming the enum value cannot silently move the
/// boundary this test guards.
String _folderFor(InspectorRole role) => switch (role) {
  InspectorRole.karantin => 'karantin',
  InspectorRole.veterinary => 'veterinary',
  InspectorRole.ses => 'ses',
};

/// Project-relative targets of the `import` lines in [file].
Iterable<String> _importsOf(String file) {
  final pattern = RegExp('''^import\\s+['"]([^'"]+)['"]''', multiLine: true);
  return pattern.allMatches(File(file).readAsStringSync()).map((m) {
    final uri = m.group(1)!;
    if (uri.startsWith('package:nazorat_aat/')) {
      return p.normalize(
        p.join('lib', uri.substring('package:nazorat_aat/'.length)),
      );
    }
    if (uri.contains(':')) return uri; // dart: or another package
    return p.normalize(p.join(p.dirname(file), uri));
  });
}

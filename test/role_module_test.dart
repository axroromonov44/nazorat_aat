import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nazorat_aat/core/roles/role_module.dart';
import 'package:nazorat_aat/core/roles/role_registry.dart';
import 'package:nazorat_aat/core/roles/shared_only_module.dart';
import 'package:nazorat_aat/features/auth/domain/entities/inspector_role.dart';

void main() {
  // Every inspectorate, plus the user whose role code we could not place.
  const roles = <InspectorRole?>[null, ...InspectorRole.values];

  String nameOf(InspectorRole? role) => role?.name ?? 'unresolved';

  group('role modules', () {
    for (final role in roles) {
      test('${nameOf(role)} declares tabs the shell can lay out', () {
        final tabs = moduleFor(role).tabs;

        expect(tabs, isNotEmpty);
        // The shell opens on tab 0, which therefore has to be a bar item.
        expect(tabs.first.docked, isFalse);
        // One notch in the bar means at most one docked tab fits.
        expect(tabs.where((tab) => tab.docked).length, lessThanOrEqualTo(1));
      });
    }
  });

  group('shell layout', () {
    test('the bar skips the docked tab', () {
      // Reproduces what the shell used to hard-code: weather is bar item 0,
      // the map sits behind the notch, settings is bar item 1.
      final layout = ShellLayout(const SharedOnlyModule().tabs);

      expect(layout.dockedIndex, 1);
      expect(layout.barIndices, [0, 2]);
      expect(layout.barItemFor(0), 0);
      expect(layout.barItemFor(2), 1);
      // Nothing in the bar is highlighted while the map is open.
      expect(layout.barItemFor(1), -1);
    });

    test('a module with nothing docked still fills the bar', () {
      final layout = ShellLayout(const [_plainTab, _plainTab]);

      expect(layout.dockedIndex, -1);
      expect(layout.dockedTab, isNull);
      expect(layout.barIndices, [0, 1]);
    });

    test(
      'an index left over from a longer module falls back to the first tab',
      () {
        final layout = ShellLayout(const [_plainTab]);

        expect(layout.clamp(0), 0);
        expect(layout.clamp(2), 0);
      },
    );
  });

  group('tab labels', () {
    final translations = {
      for (final lang in ['uz', 'ru', 'en'])
        lang:
            jsonDecode(
                  File('assets/translations/$lang.json').readAsStringSync(),
                )
                as Map<String, dynamic>,
    };

    for (final role in roles) {
      test('${nameOf(role)} tab labels are translated everywhere', () {
        for (final tab in moduleFor(role).tabs) {
          for (final entry in translations.entries) {
            expect(
              entry.value[tab.labelKey],
              isA<String>().having(
                (s) => s.trim().isNotEmpty,
                'filled',
                isTrue,
              ),
              reason: '${tab.labelKey} missing from ${entry.key}.json',
            );
          }
        }
      });
    }
  });
}

Widget _buildNothing(RoleShell shell) => const SizedBox.shrink();

const _plainTab = RoleTab(
  labelKey: 'bottomNavSettings',
  icon: Icons.settings_outlined,
  build: _buildNothing,
);

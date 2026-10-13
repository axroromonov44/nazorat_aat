import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nazorat_aat/core/roles/role_controller.dart';
import 'package:nazorat_aat/core/roles/role_scope.dart';
import 'package:nazorat_aat/features/auth/domain/entities/inspector_role.dart';
import 'package:nazorat_aat/features/auth/domain/entities/user.dart';
import 'package:nazorat_aat/features/auth/domain/repositories/auth_repository.dart';
import 'package:nazorat_aat/features/veterinary/veterinary_module.dart';

void main() {
  group('RoleController.resolveFrom', () {
    test('takes the role out of the stored token', () async {
      final controller = RoleController();

      await controller.resolveFrom(
        _FakeAuthRepository(
          const User(
            id: '1',
            username: 'u',
            fullName: 'Test',
            roles: ['vet_inspector'],
          ),
        ),
      );

      expect(controller.value, InspectorRole.veterinary);
    });

    test(
      'a storage failure leaves the shared shell rather than crashing',
      () async {
        final controller = RoleController()..update(InspectorRole.ses);

        await controller.resolveFrom(_FakeAuthRepository.throwing());

        // The splash screen is the worst place to throw: a role nobody could
        // read means the shared shell, and /users/me corrects it a moment later.
        expect(controller.value, isNull);
      },
    );

    test('an unrecognised role code is not guessed at', () async {
      final controller = RoleController();

      await controller.resolveFrom(
        _FakeAuthRepository(
          const User(id: '1', username: 'u', fullName: 'T', roles: ['OBS']),
        ),
      );

      expect(controller.value, isNull);
    });
  });

  group('RoleScope', () {
    testWidgets('hands the module down on the first build', (tester) async {
      final controller = RoleController()..update(InspectorRole.veterinary);
      final modules = <Object>[];

      await tester.pumpWidget(
        RoleScope(
          controller: controller,
          child: Builder(
            builder: (context) {
              modules.add(RoleScope.of(context));
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // No frame with the wrong tabs: the role was there to be read.
      expect(modules.single, isA<VeterinaryModule>());
    });

    testWidgets('a role corrected mid-session rebuilds the shell', (
      tester,
    ) async {
      final controller = RoleController();
      final roles = <InspectorRole?>[];

      await tester.pumpWidget(
        RoleScope(
          controller: controller,
          child: Builder(
            builder: (context) {
              roles.add(RoleScope.roleOf(context));
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      controller.update(InspectorRole.karantin);
      await tester.pump();
      // Writing the same role again changes nothing, so nothing rebuilds.
      controller.update(InspectorRole.karantin);
      await tester.pump();

      expect(roles, [null, InspectorRole.karantin]);
    });
  });
}

/// Only `getCurrentUser` is reached from here; the rest of the contract would
/// never be called while resolving a role.
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this._user) : _throws = false;
  _FakeAuthRepository.throwing() : _user = null, _throws = true;

  final User? _user;
  final bool _throws;

  @override
  Future<User?> getCurrentUser() async {
    if (_throws) throw Exception('secure storage unavailable');
    return _user;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

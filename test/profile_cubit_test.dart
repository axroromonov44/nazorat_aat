import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nazorat_aat/core/storage/hive_service.dart';
import 'package:nazorat_aat/features/auth/domain/entities/user.dart';
import 'package:nazorat_aat/features/auth/domain/repositories/auth_repository.dart';
import 'package:nazorat_aat/features/auth/presentation/bloc/profile_cubit.dart';

const _fromToken = User(
  id: '2178',
  username: 'axroro',
  fullName: 'Omonov Axrorbek',
  roles: ['OBS'],
);

const _fromServer = User(
  id: '2178',
  username: 'axroro',
  fullName: 'Omonov Axrorbek',
  roles: ['OBS'],
  imageUrl: 'https://example.invalid/axroro.jpg',
  position: 'Inspektor',
);

/// Only the two methods the cubit touches are real; the rest of the contract
/// would never be called from here.
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.currentUser});

  final User? currentUser;
  final profileCompleter = Completer<User>();
  int profileCalls = 0;

  @override
  Future<User?> getCurrentUser() async => currentUser;

  @override
  Future<User> fetchProfile() {
    profileCalls++;
    return profileCompleter.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  late Directory tempDir;
  late HiveService hive;
  var boxCount = 0;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('profile_cubit_test');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    hive = HiveService()..userBox = await Hive.openBox('user_${boxCount++}');
    await hive.userBox.clear();
  });

  tearDown(() async => hive.userBox.deleteFromDisk());

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('ProfileCubit.refresh', () {
    test('shows the token user while /users/me is still in flight', () async {
      final repository = _FakeAuthRepository(currentUser: _fromToken);
      final cubit = ProfileCubit(repository, hive);

      final pending = cubit.refresh();
      await pumpEventQueue();

      // The field is exactly where a request can hang: the name and the role
      // are known from the token, so nothing waits for the network to show it.
      expect(cubit.state, _fromToken);

      repository.profileCompleter.complete(_fromServer);
      await pending;

      expect(cubit.state, _fromServer);
      await cubit.close();
    });

    test('a failed fetch leaves the token user on screen', () async {
      final repository = _FakeAuthRepository(currentUser: _fromToken);
      final cubit = ProfileCubit(repository, hive);

      final pending = cubit.refresh();
      await pumpEventQueue();
      repository.profileCompleter.completeError(Exception('offline'));
      await pending;

      expect(cubit.state, _fromToken);
      await cubit.close();
    });

    test('logged out, it emits nothing at all', () async {
      final repository = _FakeAuthRepository();
      final cubit = ProfileCubit(repository, hive);

      final pending = cubit.refresh();
      await pumpEventQueue();
      expect(cubit.state, isNull);

      repository.profileCompleter.completeError(Exception('no session'));
      await pending;
      await cubit.close();
    });
  });
}

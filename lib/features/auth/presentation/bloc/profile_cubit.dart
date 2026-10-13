import 'dart:async';
import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/storage_keys.dart';
import '../../../../core/roles/role_controller.dart';
import '../../../../core/storage/hive_service.dart';
import '../../data/models/user_model.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';

class ProfileCubit extends Cubit<User?> {
  ProfileCubit(this._authRepository, this._hiveService, this._roleController)
    : super(null) {
    unawaited(_loadCached());
  }

  final AuthRepository _authRepository;
  final HiveService _hiveService;
  final RoleController _roleController;
  bool _refreshed = false;

  /// The splash settles the role from the token before the first frame, but
  /// `/users/me` is the authority: a role reassigned while the app was closed
  /// arrives here, and the shell has to follow it without a restart. A logout
  /// emits null through the same path, which clears it.
  @override
  void onChange(Change<User?> change) {
    super.onChange(change);
    _roleController.update(change.nextState?.inspectorRole);
  }

  Future<void> _loadCached() async {
    final raw = _hiveService.userBox.get(StorageKeys.userData) as String?;
    if (raw == null) return;
    final previous = await _authRepository.getCurrentUser();
    if (previous == null || isClosed) return;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    emit(UserModel.fromMeResponse(json, previous: previous));
  }

  Future<void> refresh({bool force = false}) async {
    if (_refreshed && !force) return;
    _refreshed = true;

    // Show what is already known before the request goes out. The access token
    // carries the name, the roles and the region, and on a fresh login nothing
    // is cached yet — without this the role chip and the greeting stay blank
    // until `/users/me` answers, which in the field can be a long time.
    if (state == null) {
      final fromToken = await _authRepository.getCurrentUser();
      if (fromToken != null && state == null && !isClosed) emit(fromToken);
    }

    try {
      final user = await _authRepository.fetchProfile();
      if (!isClosed) emit(user);
    } catch (_) {
      _refreshed = false;
    }
  }

  void reset() {
    _refreshed = false;
    emit(null);
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/storage_keys.dart';
import '../../../../core/storage/hive_service.dart';
import '../../data/models/user_model.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';

class ProfileCubit extends Cubit<User?> {
  ProfileCubit(this._authRepository, this._hiveService) : super(null) {
    unawaited(_loadCached());
  }

  final AuthRepository _authRepository;
  final HiveService _hiveService;
  bool _refreshed = false;

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

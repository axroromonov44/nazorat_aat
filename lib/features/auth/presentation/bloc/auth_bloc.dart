import 'package:easy_localization/easy_localization.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/entities/user.dart';
import '../../domain/usecases/gov_login_usecase.dart';
import '../../domain/usecases/karantin_login_usecase.dart';
import '../../domain/usecases/login_usecase.dart';

part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc(
    this._loginUseCase,
    this._govLoginUseCase,
    this._karantinLoginUseCase,
  ) : super(const AuthInitial()) {
    on<AuthLoginRequested>(_onLoginRequested);
    on<AuthGovLoginRequested>(_onGovLoginRequested);
    on<AuthKarantinLoginRequested>(_onKarantinLoginRequested);
    on<AuthLogoutRequested>(_onLogoutRequested);
  }

  final LoginUseCase _loginUseCase;
  final GovLoginUseCase _govLoginUseCase;
  final KarantinLoginUseCase _karantinLoginUseCase;

  Future<void> _onLoginRequested(
    AuthLoginRequested event,
    Emitter<AuthState> emit,
  ) => _login(
    emit,
    () => _loginUseCase(username: event.username, password: event.password),
  );

  Future<void> _onGovLoginRequested(
    AuthGovLoginRequested event,
    Emitter<AuthState> emit,
  ) => _login(emit, () => _govLoginUseCase(code: event.code));

  Future<void> _onKarantinLoginRequested(
    AuthKarantinLoginRequested event,
    Emitter<AuthState> emit,
  ) => _login(emit, () => _karantinLoginUseCase(code: event.code));

  Future<void> _login(
    Emitter<AuthState> emit,
    Future<({User user, String accessToken, String refreshToken})> Function()
    action,
  ) async {
    emit(const AuthLoading());
    try {
      final result = await action();
      emit(AuthAuthenticated(result.user));
    } on ApiException catch (e, st) {
      _log(
        '[Auth] ApiException: statusCode=${e.statusCode} message=${e.message}',
      );
      if (kDebugMode) debugPrintStack(stackTrace: st);
      emit(AuthError(e.message));
    } catch (e, st) {
      _log('[Auth] unexpected error: $e');
      if (kDebugMode) debugPrintStack(stackTrace: st);
      emit(AuthError('errorUnexpected'.tr()));
    }
  }

  Future<void> _onLogoutRequested(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthUnauthenticated());
  }
}

/// Debug-only tracing. `debugPrint` writes in release builds too, and these
/// lines carry URLs and authorization codes.
void _log(String message) {
  if (kDebugMode) debugPrint(message);
}

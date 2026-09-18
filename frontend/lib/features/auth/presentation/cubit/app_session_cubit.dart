import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/auth/google_auth_service.dart';
import '../../../../core/location/location_service.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/network/customer_realtime_service.dart';
import '../../../../core/network/worker_realtime_service.dart';
import '../../../../core/preferences/app_preferences.dart';
import '../../../../core/notifications/notification_service.dart';
import '../../../../services/webrtc_call_service.dart';
import '../../../../shared/data/mock/mock_repository.dart';
import '../../../../shared/models/models.dart';
import '../../data/auth_api_repository.dart';

part 'app_session_state.dart';

class AppSessionCubit extends Cubit<AppSessionState> {
  AppSessionCubit({
    MockRepository? repository,
    AppPreferences? preferences,
    AuthApiRepository? authRepository,
  }) : _repo = repository ?? MockRepository.instance,
       _prefs = preferences ?? AppPreferences.instance,
       _auth = authRepository ?? AuthApiRepository(),
       super(
         AppSessionState(
           locale: (preferences ?? AppPreferences.instance).locale,
           themeMode: (preferences ?? AppPreferences.instance).themeMode,
           languageSelected:
               (preferences ?? AppPreferences.instance).languageSelected,
           notificationsEnabled: (preferences ?? AppPreferences.instance)
               .transactionalNotificationsEnabled,
           systemNotificationsEnabled: (preferences ?? AppPreferences.instance)
               .systemNotificationsEnabled,
           marketingNotificationsEnabled:
               (preferences ?? AppPreferences.instance)
                   .marketingNotificationsEnabled,
         ),
       ) {
    _repo.locale = state.locale;
  }

  final MockRepository _repo;
  final AppPreferences _prefs;
  final AuthApiRepository _auth;

  AppUser? get currentUser => _repo.currentUser;

  Future<void>? _restoreInFlight;
  bool _restoreCompleted = false;

  /// Idempotent. App bootstrap starts restore; splash only awaits it.
  /// After the first run finishes, later calls no-op (do not refresh again).
  Future<void> restoreSession() {
    if (_restoreCompleted) return Future.value();
    final inflight = _restoreInFlight;
    if (inflight != null) return inflight;
    final next = _restoreSessionBody().whenComplete(() {
      _restoreCompleted = true;
      _restoreInFlight = null;
    });
    _restoreInFlight = next;
    return next;
  }

  Future<void> _restoreSessionBody() async {
    emit(state.copyWith(status: AppSessionStatus.loading, clearError: true));
    final session = await _auth.restoreSession();
    if (session == null) {
      emit(state.copyWith(status: AppSessionStatus.initial));
      return;
    }
    _repo.currentUser = session.user;
    _repo.selectedRole = session.user.role;
    if (session.user.role == UserRole.worker) {
      try {
        await _auth.saveCurrentWorkerLocation();
      } catch (_) {
        // Location sync must not prevent a worker from opening the app.
      }
    }
    _syncNotificationPreferencesFromUser(session.user);
    final marketingEnabled = session.user.marketingNotifications ?? state.marketingNotificationsEnabled;
    final systemEnabled = session.user.systemNotifications ?? state.systemNotificationsEnabled;
    final pushEnabled = session.user.pushNotifications ?? state.notificationsEnabled;
    emit(
      state.copyWith(
        role: session.user.role == UserRole.worker ? 'worker' : 'customer',
        email: session.user.email,
        phone: session.user.phone,
        status: AppSessionStatus.authenticated,
        marketingNotificationsEnabled: marketingEnabled,
        systemNotificationsEnabled: systemEnabled,
        notificationsEnabled: pushEnabled,
        clearError: true,
      ),
    );
    unawaited(
      NotificationService.instance.onAuthenticated(
        role: session.user.role == UserRole.worker ? 'worker' : 'customer',
        locale: state.locale,
        marketingEnabled: marketingEnabled,
      ),
    );
    if (session.user.role == UserRole.worker) {
      WorkerRealtimeService.instance.initForWorker(session.user.id);
    } else {
      CustomerRealtimeService.instance.initForCustomer(session.user.id);
    }
    // Keep WebRTC signaling connected so incoming calls reach this device.
    unawaited(
      WebRTCCallService.instance.initializeSocket(userId: session.user.id),
    );
  }

  Future<void> setLocale(String locale) async {
    await _prefs.setLocale(locale);
    _repo.locale = locale;
    try {
      ApiServices.client.clearCache();
    } catch (_) {}
    emit(state.copyWith(locale: locale));
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setThemeMode(mode);
    emit(state.copyWith(themeMode: mode));
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    await _prefs.setTransactionalNotificationsEnabled(enabled);
    emit(state.copyWith(notificationsEnabled: enabled));
    if (enabled) {
      unawaited(NotificationService.instance.enablePushFromSettings());
    }
    unawaited(_auth.updateNotificationPreferences(push: enabled));
  }

  Future<void> setSystemNotificationsEnabled(bool enabled) async {
    await _prefs.setSystemNotificationsEnabled(enabled);
    emit(state.copyWith(systemNotificationsEnabled: enabled));
    unawaited(_auth.updateNotificationPreferences(system: enabled));
  }

  Future<void> setMarketingNotificationsEnabled(bool enabled) async {
    await _prefs.setMarketingNotificationsEnabled(enabled);
    emit(state.copyWith(marketingNotificationsEnabled: enabled));
    unawaited(
      NotificationService.instance.setMarketingEnabled(
        enabled,
        role: state.role,
      ),
    );
    unawaited(_auth.updateNotificationPreferences(marketing: enabled));
  }

  Future<void> completeLanguageSelection() async {
    await _prefs.setLanguageSelected(true);
    emit(state.copyWith(languageSelected: true));
  }

  void setRole(String role) {
    final userRole = role == 'worker' ? UserRole.worker : UserRole.customer;
    _repo.selectedRole = userRole;
    emit(state.copyWith(role: role));
  }

  void setAuthFlow(AuthFlow flow) {
    emit(state.copyWith(authFlow: flow));
  }

  void setFederationId(String? federationId) {
    emit(state.copyWith(federationId: federationId));
  }

  Future<bool> signInWithGoogle() async {
    emit(state.copyWith(status: AppSessionStatus.loading, clearError: true));
    try {
      await GoogleAuthService.instance.ensureReady();

      try {
        await LocationService.instance.refreshCurrentPosition();
      } catch (_) {}

      final profile = await GoogleAuthService.instance.signIn();
      final session = await _auth.googleLogin(
        email: profile.email,
        name: profile.name,
        phone: profile.phone,
        avatar: profile.avatar,
        role: state.role,
      );
      _applySession(session);
      return true;
    } on ApiException catch (e) {
      emit(
        state.copyWith(
          status: AppSessionStatus.initial,
          errorMessage: e.message,
        ),
      );
      return false;
    } on GoogleSignInException catch (e) {
      final canceled = e.code == GoogleSignInExceptionCode.canceled;
      final configError =
          e.code == GoogleSignInExceptionCode.clientConfigurationError;
      final message = configError
          ? 'Google Sign-In not configured. Add Firebase config files — '
                'see assets/config/README in project.'
          : ApiException.fromError(e);
      emit(
        state.copyWith(
          status: AppSessionStatus.initial,
          errorMessage: canceled ? null : message,
          clearError: canceled,
        ),
      );
      return false;
    } catch (e) {
      emit(
        state.copyWith(
          status: AppSessionStatus.initial,
          errorMessage: ApiException.fromError(e),
        ),
      );
      return false;
    }
  }

  Future<bool> signInWithEmail({
    required String email,
    required String password,
  }) async {
    emit(
      state.copyWith(
        email: email,
        status: AppSessionStatus.loading,
        clearError: true,
      ),
    );
    try {
      final session = await _auth.login(email: email, password: password);
      _applySession(session);
      return true;
    } on ApiException catch (e) {
      emit(
        state.copyWith(
          status: AppSessionStatus.initial,
          errorMessage: e.message,
        ),
      );
      return false;
    } catch (e) {
      emit(
        state.copyWith(
          status: AppSessionStatus.initial,
          errorMessage: ApiException.fromError(e),
        ),
      );
      return false;
    }
  }

  Future<void> requestPasswordReset(String email) async {
    await _auth.forgotPassword(email);
  }

  /// Register then expect OTP verify (email).
  Future<bool> signUpWithEmail({
    required String name,
    required String email,
    required String password,
    required String phone,
  }) async {
    emit(
      state.copyWith(
        email: email,
        phone: phone,
        pendingSignupName: name,
        pendingSignupPassword: password,
        status: AppSessionStatus.loading,
        clearError: true,
      ),
    );
    try {
      await _auth.register(
        name: name,
        email: email,
        password: password,
        role: state.role,
        phone: phone,
        federationId: state.federationId,
      );
      emit(
        state.copyWith(
          email: email,
          phone: phone,
          pendingSignupName: name,
          pendingSignupPassword: password,
          status: AppSessionStatus.otpSent,
          clearError: true,
        ),
      );
      return true;
    } on ApiException catch (e) {
      emit(
        state.copyWith(
          status: AppSessionStatus.initial,
          errorMessage: e.message,
        ),
      );
      return false;
    } catch (e) {
      emit(
        state.copyWith(
          status: AppSessionStatus.initial,
          errorMessage: ApiException.fromError(e),
        ),
      );
      return false;
    }
  }

  /// Re-hit register to trigger a fresh email OTP.
  Future<bool> resendSignupOtp() async {
    final name = state.pendingSignupName;
    final email = state.email;
    final password = state.pendingSignupPassword;
    final phone = state.phone;
    if (name == null ||
        email == null ||
        email.isEmpty ||
        password == null ||
        phone == null) {
      emit(
        state.copyWith(
          errorMessage: 'Missing signup details — go back and sign up again',
        ),
      );
      return false;
    }

    try {
      await _auth.register(
        name: name,
        email: email,
        password: password,
        role: state.role,
        phone: phone,
        federationId: state.federationId,
      );
      emit(state.copyWith(status: AppSessionStatus.otpSent, clearError: true));
      return true;
    } on ApiException catch (e) {
      emit(state.copyWith(errorMessage: e.message));
      return false;
    } catch (e) {
      emit(state.copyWith(errorMessage: ApiException.fromError(e)));
      return false;
    }
  }

  Future<bool> verifyOtp(String otp) async {
    final email = state.email;
    if (email == null || email.isEmpty) {
      emit(
        state.copyWith(
          status: AppSessionStatus.otpFailed,
          errorMessage: 'Missing email for OTP',
        ),
      );
      return false;
    }
    emit(state.copyWith(status: AppSessionStatus.loading, clearError: true));
    try {
      final session = await _auth.verifyOtp(email: email, otp: otp);
      _applySession(session);
      return true;
    } on ApiException catch (e) {
      emit(
        state.copyWith(
          status: AppSessionStatus.otpFailed,
          errorMessage: e.message,
        ),
      );
      return false;
    } catch (e) {
      emit(
        state.copyWith(
          status: AppSessionStatus.otpFailed,
          errorMessage: ApiException.fromError(e),
        ),
      );
      return false;
    }
  }

  void resetOtpStatus() {
    emit(state.copyWith(status: AppSessionStatus.otpSent, clearError: true));
  }

  String postAuthRoute() {
    if (state.role != 'worker') {
      return RouteNames.customerHome;
    }
    final user = _repo.currentUser;
    // isVerified = KYC approved (not email OTP). Needs profile + approval → dashboard.
    if (user?.isVerified == true && user?.hasWorkerProfile == true) {
      return RouteNames.workerDashboard;
    }
    if (user?.hasWorkerProfile == true) {
      return RouteNames.workerOnboardingStatus;
    }
    return RouteNames.workerOnboardingIdentity;
  }

  Future<void> signOut() async {
    CustomerRealtimeService.instance.dispose();
    WorkerRealtimeService.instance.dispose();
    await NotificationService.instance.onSignedOut();
    await _auth.logout();
    _repo.currentUser = null;
    _restoreCompleted = false;
    _restoreInFlight = null;
    emit(
      state.copyWith(
        status: AppSessionStatus.initial,
        email: '',
        phone: '',
        pendingSignupName: '',
        pendingSignupPassword: '',
        clearError: true,
      ),
    );
  }

  void _syncNotificationPreferencesFromUser(AppUser user) {
    final marketing = user.marketingNotifications;
    final system = user.systemNotifications;
    final push = user.pushNotifications;
    if (marketing != null) {
      unawaited(_prefs.setMarketingNotificationsEnabled(marketing));
    }
    if (system != null) {
      unawaited(_prefs.setSystemNotificationsEnabled(system));
    }
    if (push != null) {
      unawaited(_prefs.setTransactionalNotificationsEnabled(push));
    }
  }

  void _applySession(AuthSession session) {
    _repo.currentUser = session.user;
    _repo.selectedRole = session.user.role;
    _syncNotificationPreferencesFromUser(session.user);
    final marketingEnabled = session.user.marketingNotifications ?? state.marketingNotificationsEnabled;
    final systemEnabled = session.user.systemNotifications ?? state.systemNotificationsEnabled;
    final pushEnabled = session.user.pushNotifications ?? state.notificationsEnabled;
    emit(
      state.copyWith(
        email: session.user.email,
        phone: session.user.phone,
        pendingSignupName: '',
        pendingSignupPassword: '',
        role: session.user.role == UserRole.worker ? 'worker' : 'customer',
        status: AppSessionStatus.authenticated,
        marketingNotificationsEnabled: marketingEnabled,
        systemNotificationsEnabled: systemEnabled,
        notificationsEnabled: pushEnabled,
        clearError: true,
      ),
    );
    unawaited(
      NotificationService.instance.onAuthenticated(
        role: session.user.role == UserRole.worker ? 'worker' : 'customer',
        locale: state.locale,
        marketingEnabled: marketingEnabled,
      ),
    );
    if (session.user.role == UserRole.worker) {
      WorkerRealtimeService.instance.initForWorker(session.user.id);
    } else {
      CustomerRealtimeService.instance.initForCustomer(session.user.id);
    }
    unawaited(
      WebRTCCallService.instance.initializeSocket(userId: session.user.id),
    );
  }
}

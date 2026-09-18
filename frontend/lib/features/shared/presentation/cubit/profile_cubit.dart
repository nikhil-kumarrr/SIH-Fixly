import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/location/app_location.dart';
import '../../../../core/location/location_service.dart';
import '../../../../shared/data/mock/mock_repository.dart';
import '../../../../shared/models/models.dart';
import '../../../auth/data/auth_api_repository.dart';

part 'profile_state.dart';

class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit({MockRepository? repository, AuthApiRepository? authRepository})
    : _repo = repository ?? MockRepository.instance,
      _auth = authRepository ?? AuthApiRepository(),
      super(const ProfileState());

  final MockRepository _repo;
  final AuthApiRepository _auth;

  String _resolvedHomeState(AppUser? user) {
    final fromUser = user?.homeState?.trim();
    if (fromUser != null && fromUser.isNotEmpty) return fromUser;
    return _repo.onboardingData.state;
  }

  String _resolvedHomeCity(AppUser? user) {
    final fromUser = user?.homeCity?.trim();
    if (fromUser != null && fromUser.isNotEmpty) return fromUser;
    return _repo.onboardingData.district;
  }

  Future<bool> refreshCurrentLocation() async {
    final refreshed = await LocationService.instance.refreshCurrentPosition();
    if (!refreshed || !AppLocation.instance.hasFix) return false;

    await _auth.saveCurrentWorkerLocation();
    final address = AppLocation.instance.addressLabel;
    if (address != null && address.isNotEmpty) {
      emit(state.copyWith(workAddress: address));
    }
    return true;
  }

  Future<void> load() async {
    emit(state.copyWith(status: ProfileStatus.loading, clearError: true));
    try {
      final user = await _auth.fetchMe();
      _repo.currentUser = user;
      final effSkills = user.skills.isNotEmpty
          ? user.skills
          : _repo.onboardingData.skills;
      emit(
        ProfileState(
          status: ProfileStatus.loaded,
          name: user.name,
          phone: user.phone,
          email: user.email,
          role: user.role,
          eshramUan: user.eshramUan ?? _repo.onboardingData.eshramUan,
          insured: user.insured,
          skills: effSkills,
          categories: user.categories,
          category: user.category ?? '',
          bio: user.bio ?? '',
          workAddress: user.workAddress ?? '',
          hourlyRate: user.hourlyRate,
          experienceYears: user.experienceYears,
          gender: user.gender ?? '',
          upiId: user.upiId ?? '',
          emergencyContactName: user.emergencyName ?? '',
          emergencyContactPhone: user.emergencyPhone ?? '',
          emergencyContactRelation: user.emergencyRelation ?? '',
          homeState: _resolvedHomeState(user),
          homeCity: _resolvedHomeCity(user),
          homePincode: user.homePincode ?? '',
        ),
      );
    } on ApiException catch (e) {
      final user = _repo.currentUser;
      emit(
        ProfileState(
          status: ProfileStatus.loaded,
          name: user?.name ?? '',
          phone: user?.phone ?? '',
          email: user?.email ?? '',
          role: user?.role ?? UserRole.customer,
          eshramUan: user?.eshramUan ?? _repo.onboardingData.eshramUan,
          insured: user?.insured ?? false,
          skills: user?.skills.isNotEmpty == true
              ? user!.skills
              : _repo.onboardingData.skills,
          categories: user?.categories ?? const [],
          category: user?.category ?? '',
          bio: user?.bio ?? '',
          workAddress: user?.workAddress ?? '',
          hourlyRate: user?.hourlyRate ?? 0,
          experienceYears: user?.experienceYears ?? 0,
          gender: user?.gender ?? '',
          upiId: user?.upiId ?? '',
          emergencyContactName: user?.emergencyName ?? '',
          emergencyContactPhone: user?.emergencyPhone ?? '',
          emergencyContactRelation: user?.emergencyRelation ?? '',
          homeState: _resolvedHomeState(user),
          homeCity: _resolvedHomeCity(user),
          homePincode: user?.homePincode ?? '',
          errorMessage: e.message,
        ),
      );
    } catch (_) {
      final user = _repo.currentUser;
      emit(
        ProfileState(
          status: ProfileStatus.loaded,
          name: user?.name ?? '',
          phone: user?.phone ?? '',
          email: user?.email ?? '',
          role: user?.role ?? UserRole.customer,
          eshramUan: user?.eshramUan ?? _repo.onboardingData.eshramUan,
          insured: user?.insured ?? false,
          skills: user?.skills.isNotEmpty == true
              ? user!.skills
              : _repo.onboardingData.skills,
          categories: user?.categories ?? const [],
          category: user?.category ?? '',
          bio: user?.bio ?? '',
          workAddress: user?.workAddress ?? '',
          hourlyRate: user?.hourlyRate ?? 0,
          experienceYears: user?.experienceYears ?? 0,
          gender: user?.gender ?? '',
          upiId: user?.upiId ?? '',
          emergencyContactName: user?.emergencyName ?? '',
          emergencyContactPhone: user?.emergencyPhone ?? '',
          emergencyContactRelation: user?.emergencyRelation ?? '',
          homeState: _resolvedHomeState(user),
          homeCity: _resolvedHomeCity(user),
          homePincode: user?.homePincode ?? '',
        ),
      );
    }
  }

  Future<void> updateProfile({
    required String name,
    required String phone,
    String? avatar,
    String? preferredLanguage,
    String? emergencyContactName,
    String? emergencyContactPhone,
    String? emergencyContactRelation,
    String? bio,
    String? category,
    List<String>? categories,
    List<String>? skills,
    double? hourlyRate,
    int? experienceYears,
    String? workAddress,
    String? gender,
    String? upiId,
    String? homeState,
    String? homeCity,
    String? homePincode,
  }) async {
    emit(state.copyWith(status: ProfileStatus.loading, clearError: true));
    try {
      final user = await _auth.updateProfile(
        name: name,
        phone: phone,
        avatar: avatar,
        preferredLanguage: preferredLanguage,
        emergencyContactName: emergencyContactName,
        emergencyContactPhone: emergencyContactPhone,
        emergencyContactRelation: emergencyContactRelation,
        bio: bio,
        category: category,
        categories: categories,
        skills: skills,
        hourlyRate: hourlyRate,
        experienceYears: experienceYears,
        workAddress: workAddress,
        gender: gender,
        upiId: upiId,
        homeState: homeState,
        homeCity: homeCity,
        homePincode: homePincode,
        isWorker: state.isWorker,
      );
      _repo.currentUser = user;
      emit(
        state.copyWith(
          status: ProfileStatus.updated,
          name: user.name,
          phone: user.phone,
          email: user.email,
          role: user.role,
          bio: user.bio,
          workAddress: user.workAddress,
          category: user.category,
          categories: user.categories,
          skills: user.skills,
          hourlyRate: user.hourlyRate,
          experienceYears: user.experienceYears,
          gender: user.gender,
          upiId: user.upiId,
          emergencyContactName: user.emergencyName ?? '',
          emergencyContactPhone: user.emergencyPhone ?? '',
          emergencyContactRelation: user.emergencyRelation ?? '',
          homeState: _resolvedHomeState(user),
          homeCity: _resolvedHomeCity(user),
          homePincode: user.homePincode ?? '',
        ),
      );
    } on ApiException catch (e) {
      emit(
        state.copyWith(status: ProfileStatus.error, errorMessage: e.message),
      );
      rethrow;
    }
  }
}

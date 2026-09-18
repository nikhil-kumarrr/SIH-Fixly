import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/data/mock/mock_repository.dart';
import '../../../../shared/models/models.dart';
import '../../../auth/data/auth_api_repository.dart';
import '../../../workers/data/workers_api_repository.dart';

part 'worker_onboarding_state.dart';

class WorkerOnboardingCubit extends Cubit<WorkerOnboardingState> {
  WorkerOnboardingCubit({
    MockRepository? repository,
    WorkersApiRepository? workersApi,
    AuthApiRepository? authApi,
  })  : _repo = repository ?? MockRepository.instance,
        _workersApi = workersApi ?? WorkersApiRepository(),
        _authApi = authApi ?? AuthApiRepository(),
        super(
          WorkerOnboardingState(
            formData: (repository ?? MockRepository.instance).onboardingData,
          ),
        );

  final MockRepository _repo;
  final WorkersApiRepository _workersApi;
  final AuthApiRepository _authApi;

  static const totalSteps = AppConstants.onboardingTotalSteps;

  /// Prefill once from signup/session. Keeps edits if user already typed.
  void seedFromSession({
    String? name,
    String? phone,
    String? email,
  }) {
    final data = state.formData;
    final nextName =
        data.fullName.trim().isNotEmpty ? data.fullName : (name ?? '').trim();
    final nextPhone =
        data.phone.trim().isNotEmpty ? data.phone : (phone ?? '').trim();
    final nextEmail = (email ?? data.email).trim();
    if (nextName == data.fullName &&
        nextPhone == data.phone &&
        nextEmail == data.email) {
      return;
    }
    _emitForm(
      data.copyWith(
        fullName: nextName,
        phone: nextPhone,
        email: nextEmail,
      ),
    );
  }

  void updateFullName(String value) {
    _emitForm(state.formData.copyWith(fullName: value));
  }

  void updatePhone(String value) {
    _emitForm(state.formData.copyWith(phone: value));
  }

  void updateDateOfBirth(DateTime value) {
    _emitForm(state.formData.copyWith(dateOfBirth: value));
  }

  void updateGender(WorkerGender value) {
    _emitForm(state.formData.copyWith(gender: value));
  }

  void updateState(String value) {
    _emitForm(state.formData.copyWith(state: value));
  }

  void updateDistrict(String value) {
    _emitForm(state.formData.copyWith(district: value));
  }

  void updateAadhaar(String value) {
    _emitForm(state.formData.copyWith(aadhaar: value));
  }

  void updatePan(String value) {
    _emitForm(state.formData.copyWith(pan: value.toUpperCase()));
  }

  void updateAadhaarFrontPath(String path) {
    _emitForm(state.formData.copyWith(aadhaarFrontPath: path));
  }

  void updateAadhaarBackPath(String path) {
    _emitForm(state.formData.copyWith(aadhaarBackPath: path));
  }

  void updatePanFrontPath(String path) {
    _emitForm(state.formData.copyWith(panFrontPath: path));
  }

  void updatePanBackPath(String path) {
    _emitForm(state.formData.copyWith(panBackPath: path));
  }

  void captureSelfie({required String imageUrl}) {
    _emitForm(
      state.formData.copyWith(
        selfieVerified: true,
        selfieImageUrl: imageUrl,
      ),
    );
  }

  void clearSelfie() {
    _emitForm(
      state.formData.copyWith(
        selfieVerified: false,
        selfieImageUrl: null,
      ),
    );
  }

  void updateCertificateUploaded(bool uploaded) {
    _emitForm(state.formData.copyWith(certificateUploaded: uploaded));
  }

  void updateCertificate({required String path, required String fileName}) {
    _emitForm(
      state.formData.copyWith(
        certificateUploaded: true,
        certificatePath: path,
        certificateFileName: fileName,
      ),
    );
  }

  void clearCertificate() {
    _emitForm(
      state.formData.copyWith(
        certificateUploaded: false,
        certificatePath: null,
        certificateFileName: null,
      ),
    );
  }

  void toggleSkill(String skillId) {
    final skills = List<String>.from(state.formData.skills);
    final rates = Map<String, int>.from(state.formData.categoryRates);
    if (skills.contains(skillId)) {
      skills.remove(skillId);
      rates.remove(skillId);
    } else {
      skills.add(skillId);
    }
    _emitForm(
      state.formData.copyWith(skills: skills, categoryRates: rates),
    );
  }

  void addCustomSkill(String raw) {
    final skill = raw.trim();
    if (skill.isEmpty) return;
    final skills = List<String>.from(state.formData.skills);
    final exists = skills.any((s) => s.toLowerCase() == skill.toLowerCase());
    if (exists) return;
    skills.add(skill);
    _emitForm(state.formData.copyWith(skills: skills));
  }

  void removeSkill(String skill) {
    final skills = List<String>.from(state.formData.skills)..remove(skill);
    final rates = Map<String, int>.from(state.formData.categoryRates)
      ..remove(skill);
    _emitForm(
      state.formData.copyWith(skills: skills, categoryRates: rates),
    );
  }

  void updateCategoryRate(String categoryId, int rate) {
    final rates = Map<String, int>.from(state.formData.categoryRates);
    rates[categoryId] = rate;
    _emitForm(state.formData.copyWith(categoryRates: rates));
  }

  void updateExperienceYears(int years) {
    if (years == state.formData.experienceYears) return;
    _emitForm(state.formData.copyWith(experienceYears: years));
  }

  void updateBio(String value) {
    if (value == state.formData.bio) return;
    _emitForm(state.formData.copyWith(bio: value));
  }

  void updateFederation({required String id, required String name}) {
    _emitForm(
      state.formData.copyWith(
        federationId: id,
        federationName: name,
      ),
    );
  }

  void updateSociety({required String id, String? memberId}) {
    _emitForm(
      state.formData.copyWith(societyId: id, societyMemberId: memberId),
    );
  }

  void updateRecentWorkPhotos(List<String> paths) {
    _emitForm(state.formData.copyWith(recentWorkPhotoPaths: paths));
  }

  void toggleIncludedTask(String category, String task) {
    final currentMap = Map<String, List<String>>.from(state.formData.includedTasks);
    final list = List<String>.from(currentMap[category] ?? []);
    if (list.contains(task)) {
      list.remove(task);
    } else {
      list.add(task);
    }
    currentMap[category] = list;
    _emitForm(state.formData.copyWith(includedTasks: currentMap));
  }

  void toggleExcludedTask(String category, String task) {
    final currentMap = Map<String, List<String>>.from(state.formData.excludedTasks);
    final list = List<String>.from(currentMap[category] ?? []);
    if (list.contains(task)) {
      list.remove(task);
    } else {
      list.add(task);
    }
    currentMap[category] = list;
    _emitForm(state.formData.copyWith(excludedTasks: currentMap));
  }

  void setScopeTasksForCategory(String category, {required List<String> included, required List<String> excluded}) {
    final incMap = Map<String, List<String>>.from(state.formData.includedTasks);
    final excMap = Map<String, List<String>>.from(state.formData.excludedTasks);
    incMap[category] = List<String>.from(included);
    excMap[category] = List<String>.from(excluded);
    _emitForm(state.formData.copyWith(includedTasks: incMap, excludedTasks: excMap));
  }

  void updateServiceRadius(double km) {
    _emitForm(state.formData.copyWith(serviceRadiusKm: km));
  }

  void updateHasEshram(bool value) {
    _emitForm(state.formData.copyWith(hasEshram: value));
  }

  void updateEshramUan(String value) {
    _emitForm(state.formData.copyWith(eshramUan: value));
  }

  void setPayoutMethod(PayoutMethod method) {
    if (method == state.formData.payoutMethod) return;
    _emitForm(state.formData.copyWith(payoutMethod: method));
  }

  void updateAccountHolderName(String value) {
    final next = value.trimLeft();
    if (next == state.formData.accountHolderName) return;
    _emitForm(
      state.formData.copyWith(
        accountHolderName: next,
        bankVerified: false,
      ),
    );
  }

  void updateBankAccount(String value) {
    if (value == state.formData.bankAccount) return;
    _emitForm(
      state.formData.copyWith(
        bankAccount: value,
        bankVerified: false,
      ),
    );
  }

  void updateIfscCode(String value) {
    final next = value.toUpperCase();
    if (next == state.formData.ifscCode) return;
    _emitForm(
      state.formData.copyWith(
        ifscCode: next,
        bankVerified: false,
      ),
    );
  }

  void updateUpiId(String value) {
    final next = value.trim();
    if (next == state.formData.upiId) return;
    _emitForm(
      state.formData.copyWith(
        upiId: next,
        upiVerified: false,
      ),
    );
  }

  Future<String?> verifyBankAccount() async {
    final data = state.formData;
    final error =
        Validators.requiredField(data.accountHolderName, label: 'Account holder name') ??
            Validators.bankAccount(data.bankAccount) ??
            Validators.ifsc(data.ifscCode);
    if (error != null) return error;

    // Client-side format check only — server validates on setup-profile submit.
    _emitForm(state.formData.copyWith(bankVerified: true));
    return null;
  }

  Future<String?> verifyUpiId() async {
    final error = Validators.upi(state.formData.upiId);
    if (error != null) return error;

    // Client-side format check only — server validates on setup-profile submit.
    _emitForm(state.formData.copyWith(upiVerified: true));
    return null;
  }

  void setStep(int step) {
    emit(state.copyWith(currentStep: step.clamp(1, totalSteps)));
  }

  String? validateStep(int step) {
    final data = state.formData;
    switch (step) {
      case 1:
        return Validators.requiredField(data.fullName, label: 'Full name') ??
            Validators.phone(data.phone) ??
            (data.dateOfBirth == null ? 'Date of birth is required' : null) ??
            (data.gender == null ? 'Please select gender' : null) ??
            Validators.requiredField(data.state, label: 'State') ??
            Validators.requiredField(data.district, label: 'District') ??
            Validators.aadhaar(data.aadhaar) ??
            (data.hasAadhaarPhotos
                ? null
                : 'Add Aadhaar front and back photos') ??
            Validators.pan(data.pan) ??
            (data.hasPanPhotos ? null : 'Add PAN front and back photos') ??
            (data.selfieVerified ? null : 'Please capture a selfie');
      case 2:
        if (!data.certificateUploaded ||
            (data.certificatePath == null || data.certificatePath!.isEmpty)) {
          return 'Please upload your certificate';
        }
        if (data.skills.isEmpty) return 'Select at least one skill';
        for (final skill in data.skills) {
          final rate = data.categoryRates[skill] ?? 0;
          if (rate <= 0) {
            return 'Enter a base price for each selected skill';
          }
        }
        if (data.experienceYears < 0 || data.experienceYears > 50) {
          return 'Enter valid years of experience';
        }
        return null;
      case 3:
        if (data.payoutMethod == PayoutMethod.bank) {
          return Validators.requiredField(
                data.accountHolderName,
                label: 'Account holder name',
              ) ??
              Validators.bankAccount(data.bankAccount) ??
              Validators.ifsc(data.ifscCode) ??
              (data.bankVerified ? null : 'Please verify your bank account');
        }
        return Validators.upi(data.upiId) ??
            (data.upiVerified ? null : 'Please verify your UPI ID');
      default:
        return null;
    }
  }

  bool canProceedFromStep(int step) => validateStep(step) == null;

  Future<bool> submitIdentity() async {
    emit(state.copyWith(status: WorkerOnboardingStatus.loading));
    try {
      // Simulate API verification
      await Future.delayed(const Duration(milliseconds: 300));
      emit(state.copyWith(
        status: WorkerOnboardingStatus.loaded,
        errorMessage: null,
      ));
      return true;
    } on ApiException catch (e) {
      if (e.message == 'DUPLICATE_DOCUMENT' || e.statusCode == 409) {
        emit(state.copyWith(
          status: WorkerOnboardingStatus.failure,
          errorMessage: 'DUPLICATE_DOCUMENT',
        ));
      } else {
        emit(state.copyWith(
          status: WorkerOnboardingStatus.failure,
          errorMessage: e.message,
        ));
      }
      return false;
    } catch (e) {
      emit(state.copyWith(
        status: WorkerOnboardingStatus.failure,
        errorMessage: ApiException.fromError(e),
      ));
      return false;
    }
  }

  Future<bool> submitWorkProfile() async {
    emit(state.copyWith(status: WorkerOnboardingStatus.loading));
    try {
      // Simulate API verification
      await Future.delayed(const Duration(milliseconds: 300));
      emit(state.copyWith(
        status: WorkerOnboardingStatus.loaded,
        errorMessage: null,
      ));
      return true;
    } on ApiException catch (e) {
      if (e.message == 'NAME_MISMATCH' || e.statusCode == 400) {
        emit(state.copyWith(
          status: WorkerOnboardingStatus.failure,
          errorMessage: 'NAME_MISMATCH',
        ));
      } else {
        emit(state.copyWith(
          status: WorkerOnboardingStatus.failure,
          errorMessage: e.message,
        ));
      }
      return false;
    } catch (e) {
      emit(state.copyWith(
        status: WorkerOnboardingStatus.failure,
        errorMessage: ApiException.fromError(e),
      ));
      return false;
    }
  }

  Future<bool> submitOnboarding() async {
    emit(state.copyWith(status: WorkerOnboardingStatus.loading));
    try {
      final res = await _workersApi.submitSetupProfile(state.formData);
      await _trySubmitVerification(res);
      _repo.onboardingData = state.formData;
      _repo.kycReviewStatus = KycReviewStatus.submitted;
      emit(
        state.copyWith(
          status: WorkerOnboardingStatus.submitted,
          kycStatus: KycReviewStatus.submitted,
          errorMessage: null,
        ),
      );
      return true;
    } on ApiException catch (e) {
      emit(
        state.copyWith(
          status: WorkerOnboardingStatus.failure,
          errorMessage: e.message,
        ),
      );
      return false;
    } catch (e) {
      emit(
        state.copyWith(
          status: WorkerOnboardingStatus.failure,
          errorMessage: ApiException.fromError(e),
        ),
      );
      return false;
    }
  }

  /// Best-effort AI verification path using URLs returned (or form data URIs).
  Future<void> _trySubmitVerification(Map<String, dynamic> setupRes) async {
    final data = state.formData;
    final user = setupRes['user'] is Map
        ? Map<String, dynamic>.from(setupRes['user'] as Map)
        : <String, dynamic>{};
    final kyc = user['kycDocuments'] is Map
        ? Map<String, dynamic>.from(user['kycDocuments'] as Map)
        : <String, dynamic>{};
    final profile = user['workerProfile'] is Map
        ? Map<String, dynamic>.from(user['workerProfile'] as Map)
        : <String, dynamic>{};

    final front = (kyc['aadhaarFrontPhoto'] ?? data.aadhaarFrontPath)?.toString();
    final selfie = (kyc['selfieImageUrl'] ??
            profile['selfieImageUrl'] ??
            data.selfieImageUrl)
        ?.toString();
    final aadhaar = data.aadhaar.replaceAll(' ', '');
    if (front == null ||
        front.isEmpty ||
        selfie == null ||
        selfie.isEmpty ||
        aadhaar.isEmpty) {
      return;
    }
    try {
      await _workersApi.submitVerification(
        governmentIdType: 'Aadhaar Card',
        governmentIdNumber: aadhaar,
        governmentIdFrontUrl: front,
        governmentIdBackUrl: kyc['aadhaarBackPhoto']?.toString(),
        selfieImageUrl: selfie,
      );
    } catch (_) {
      // setup-profile already stored KYC; verification AI is optional.
    }
  }

  Future<void> refreshKycStatus() async {
    emit(state.copyWith(status: WorkerOnboardingStatus.loading));
    try {
      final userJson = await _authApi.fetchMeUserJson();
      final next = AuthApiRepository.mapKycStatus(userJson);
      final decline = AuthApiRepository.mapDeclineReason(userJson);
      final mapped = AuthApiRepository.mapUser(userJson);
      _repo.kycReviewStatus = next;
      _repo.currentUser = mapped;
      emit(
        state.copyWith(
          status: WorkerOnboardingStatus.loaded,
          kycStatus: next,
          declineReason: decline,
          clearDeclineReason: decline == null,
          errorMessage: null,
        ),
      );
    } on ApiException catch (e) {
      emit(
        state.copyWith(
          status: WorkerOnboardingStatus.failure,
          errorMessage: e.message,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: WorkerOnboardingStatus.failure,
          errorMessage: ApiException.fromError(e),
        ),
      );
    }
  }

  void _emitForm(OnboardingFormData data) {
    _repo.onboardingData = data;
    emit(state.copyWith(formData: data, status: WorkerOnboardingStatus.loaded));
  }
}

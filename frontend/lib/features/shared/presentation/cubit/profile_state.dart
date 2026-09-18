part of 'profile_cubit.dart';

enum ProfileStatus { initial, loading, loaded, updated, error }

class ProfileState extends Equatable {
  const ProfileState({
    this.status = ProfileStatus.initial,
    this.name = '',
    this.phone = '',
    this.email = '',
    this.role = UserRole.customer,
    this.eshramUan = '',
    this.insured = false,
    this.skills = const [],
    this.categories = const [],
    this.category = '',
    this.bio = '',
    this.workAddress = '',
    this.hourlyRate = 0,
    this.experienceYears = 0,
    this.gender = '',
    this.upiId = '',
    this.emergencyContactName = '',
    this.emergencyContactPhone = '',
    this.emergencyContactRelation = '',
    this.homeState = '',
    this.homeCity = '',
    this.homePincode = '',
    this.errorMessage,
  });

  final ProfileStatus status;
  final String name;
  final String phone;
  final String email;
  final UserRole role;
  final String eshramUan;
  final bool insured;
  final List<String> skills;
  final List<String> categories;
  final String category;
  final String bio;
  final String workAddress;
  final double hourlyRate;
  final int experienceYears;
  final String gender;
  final String upiId;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final String emergencyContactRelation;
  final String homeState;
  final String homeCity;
  final String homePincode;
  final String? errorMessage;

  bool get isWorker => role == UserRole.worker;

  /// City/district · state for profile cards.
  String get locationSummary {
    final parts = <String>[
      if (homeCity.trim().isNotEmpty) homeCity.trim(),
      if (homeState.trim().isNotEmpty) homeState.trim(),
    ];
    if (parts.isNotEmpty) return parts.join(', ');
    if (workAddress.trim().isNotEmpty) return workAddress.trim();
    return '';
  }

  ProfileState copyWith({
    ProfileStatus? status,
    String? name,
    String? phone,
    String? email,
    UserRole? role,
    String? eshramUan,
    bool? insured,
    List<String>? skills,
    List<String>? categories,
    String? category,
    String? bio,
    String? workAddress,
    double? hourlyRate,
    int? experienceYears,
    String? gender,
    String? upiId,
    String? emergencyContactName,
    String? emergencyContactPhone,
    String? emergencyContactRelation,
    String? homeState,
    String? homeCity,
    String? homePincode,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ProfileState(
      status: status ?? this.status,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      role: role ?? this.role,
      eshramUan: eshramUan ?? this.eshramUan,
      insured: insured ?? this.insured,
      skills: skills ?? this.skills,
      categories: categories ?? this.categories,
      category: category ?? this.category,
      bio: bio ?? this.bio,
      workAddress: workAddress ?? this.workAddress,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      experienceYears: experienceYears ?? this.experienceYears,
      gender: gender ?? this.gender,
      upiId: upiId ?? this.upiId,
      emergencyContactName:
          emergencyContactName ?? this.emergencyContactName,
      emergencyContactPhone:
          emergencyContactPhone ?? this.emergencyContactPhone,
      emergencyContactRelation:
          emergencyContactRelation ?? this.emergencyContactRelation,
      homeState: homeState ?? this.homeState,
      homeCity: homeCity ?? this.homeCity,
      homePincode: homePincode ?? this.homePincode,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
        status,
        name,
        phone,
        email,
        role,
        eshramUan,
        insured,
        skills,
        categories,
        category,
        bio,
        workAddress,
        hourlyRate,
        experienceYears,
        gender,
        upiId,
        emergencyContactName,
        emergencyContactPhone,
        emergencyContactRelation,
        homeState,
        homeCity,
        homePincode,
        errorMessage,
      ];
}

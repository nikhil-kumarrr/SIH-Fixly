import '../../../core/location/app_location.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_enpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/models/models.dart';
import '../../worker/data/worker_setup_profile_mapper.dart';

class WorkersApiRepository {
  WorkersApiRepository({ApiClient? client})
    : _api = client ?? ApiServices.client;

  final ApiClient _api;

  Future<WorkersPage> fetchNearbyPage({
    double? lng,
    double? lat,
    String? category,
    String sortBy = 'nearest',
    int offset = 0,
    int limit = 5,
  }) async {
    final loc = AppLocation.instance;
    final useLng = lng ?? (loc.hasFix ? loc.requireLng : null);
    final useLat = lat ?? (loc.hasFix ? loc.requireLat : null);
    if (useLng == null || useLat == null) {
      throw ApiException('Location required to find nearby workers');
    }
    final res = await _api.get(
      ApiEndpoints.workers,
      query: {
        'lng': useLng,
        'lat': useLat,
        'sortBy': sortBy,
        'offset': offset,
        'limit': limit,
        if (category != null && category.isNotEmpty) 'category': category,
      },
    );
    final code = res['code']?.toString();
    final message = res['message']?.toString();
    final searchRadiusKm = (res['searchRadiusKm'] as num?)?.toInt();

    // Backend returns HTTP 200 + success:false for empty radius matches.
    if (res['success'] != true) {
      final emptyList = res['workers'] is! List || (res['workers'] as List).isEmpty;
      if (code == 'NO_WORKERS_FOUND' || emptyList) {
        return WorkersPage(
          workers: const [],
          hasMore: false,
          nextOffset: offset,
          code: code ?? 'NO_WORKERS_FOUND',
          message: message ??
              'No available professionals found nearby. Please try again shortly or select a different category.',
          searchRadiusKm: searchRadiusKm,
        );
      }
      throw ApiException(message ?? 'Workers failed');
    }
    final list = res['workers'];
    final workers = list is List
        ? list
              .whereType<Map>()
              .map(
                (e) => mapWorker(Map<String, dynamic>.from(e), useLat, useLng),
              )
              .toList()
        : <WorkerProfile>[];
    return WorkersPage(
      workers: workers,
      hasMore: res['hasMore'] == true,
      nextOffset:
          (res['nextOffset'] as num?)?.toInt() ?? offset + workers.length,
      code: code,
      message: message,
      searchRadiusKm: searchRadiusKm,
    );
  }

  Future<List<WorkerProfile>> fetchNearby({
    double? lng,
    double? lat,
    String? category,
    String sortBy = 'nearest',
  }) async {
    final loc = AppLocation.instance;
    final useLng = lng ?? (loc.hasFix ? loc.requireLng : null);
    final useLat = lat ?? (loc.hasFix ? loc.requireLat : null);
    if (useLng == null || useLat == null) {
      throw ApiException('Location required to find nearby workers');
    }
    return (await fetchNearbyPage(
      lng: useLng,
      lat: useLat,
      category: category,
      sortBy: sortBy,
    )).workers;
  }

  Future<WorkerProfile> fetchWorker(String workerId) async {
    final res = await _api.get(ApiEndpoints.workerById(workerId));
    final rawWorker = res['worker'] ?? res['data'] ?? res['user'];
    if (res['success'] != true || rawWorker is! Map) {
      throw ApiException(res['message']?.toString() ?? 'Worker not found');
    }
    return mapWorker(Map<String, dynamic>.from(rawWorker));
  }

  /// Last onboarding step: flat JSON + base64 media → setup-profile.
  Future<Map<String, dynamic>> submitSetupProfile(
    OnboardingFormData formData,
  ) async {
    final body = await WorkerSetupProfileMapper.toBody(formData);
    final res = await _api.put(ApiEndpoints.setupProfile, data: body);
    if (res['success'] != true) {
      throw ApiException(
        res['message']?.toString() ?? 'Worker profile update failed',
      );
    }
    return res;
  }

  Future<Map<String, dynamic>> fetchReliability(String workerId) async {
    final res = await _api.get(ApiEndpoints.workerReliability(workerId));
    if (res['success'] != true) {
      throw ApiException(res['message']?.toString() ?? 'Reliability failed');
    }
    return Map<String, dynamic>.from(
      (res['data'] ?? res['reliability'] ?? {}) as Map,
    );
  }

  Future<Map<String, dynamic>> fetchAvailability() async {
    final res = await _api.get(ApiEndpoints.workerAvailability);
    if (res['success'] != true) {
      throw ApiException(res['message']?.toString() ?? 'Availability failed');
    }
    return Map<String, dynamic>.from(res['data'] as Map? ?? res);
  }

  Future<bool> setOnline(bool isOnline) async {
    final res = await _api.patch(
      ApiEndpoints.workerAvailability,
      data: {'isOnline': isOnline},
    );
    if (res['success'] != true) {
      throw ApiException(
        res['message']?.toString() ?? 'Availability update failed',
      );
    }
    final data = res['data'];
    if (data is Map) return data['isOnline'] == true;
    return isOnline;
  }

  Future<Map<String, dynamic>> fetchWorkerRates() async {
    final res = await _api.get('/api/workers/me/rates');
    if (res['success'] != true) {
      throw ApiException(res['message']?.toString() ?? 'Failed to fetch rates');
    }
    return Map<String, dynamic>.from(res['data'] as Map? ?? res);
  }

  Future<void> updateWorkerRates(List<Map<String, dynamic>> rates) async {
    final res = await _api.put(
      '/api/workers/me/rates',
      data: {'categoryRates': rates},
    );
    if (res['success'] != true) {
      throw ApiException(res['message']?.toString() ?? 'Failed to update rates');
    }
  }

  Future<Map<String, dynamic>> fetchMyCooperativeMembership() async {
    final res = await _api.get(ApiEndpoints.cooperativeMySociety);
    if (res['success'] != true) {
      throw ApiException(res['message']?.toString() ?? 'Failed to fetch cooperative details');
    }
    return Map<String, dynamic>.from(res['data'] as Map? ?? res);
  }

  Future<List<Map<String, dynamic>>> fetchFederations() async {
    final res = await _api.get(ApiEndpoints.cooperativeFederations);
    if (res['success'] != true) {
      throw ApiException(
        res['message']?.toString() ?? 'Failed to list federations',
      );
    }
    final raw = res['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchSocieties({
    String? state,
    String? district,
  }) async {
    final res = await _api.get(
      ApiEndpoints.cooperativeSocieties,
      query: {
        if (state != null && state.isNotEmpty) 'state': state,
        if (district != null && district.isNotEmpty) 'district': district,
        'active': 'true',
      },
    );
    if (res['success'] != true) {
      throw ApiException(res['message']?.toString() ?? 'Failed to list societies');
    }
    final raw = res['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> joinSociety(String societyId) async {
    final res = await _api.post(
      ApiEndpoints.cooperativeJoin,
      data: {'societyId': societyId},
    );
    if (res['success'] != true) {
      throw ApiException(res['message']?.toString() ?? 'Join society failed');
    }
    return Map<String, dynamic>.from(res['data'] as Map? ?? res);
  }

  Future<Map<String, dynamic>> updateAvailabilitySchedule({
    required List<int> days,
    required String startTime,
    required String endTime,
  }) async {
    final res = await _api.put(
      ApiEndpoints.workerAvailabilitySchedule,
      data: {
        'days': days,
        'startTime': startTime,
        'endTime': endTime,
      },
    );
    if (res['success'] != true) {
      throw ApiException(res['message']?.toString() ?? 'Schedule update failed');
    }
    return Map<String, dynamic>.from(res['data'] as Map? ?? res);
  }

  Future<void> setServiceRadiusKm(double km) async {
    final res = await _api.patch(
      ApiEndpoints.workerAvailability,
      data: {'serviceRadiusKm': km},
    );
    if (res['success'] != true) {
      throw ApiException(res['message']?.toString() ?? 'Radius update failed');
    }
  }

  /// Trigger AI / admin verification path after setup-profile.
  Future<void> submitVerification({
    required String governmentIdType,
    required String governmentIdNumber,
    required String governmentIdFrontUrl,
    required String selfieImageUrl,
    String? governmentIdBackUrl,
  }) async {
    final res = await _api.post(
      ApiEndpoints.verificationSubmit,
      data: {
        'governmentIdType': governmentIdType,
        'governmentIdNumber': governmentIdNumber,
        'governmentIdFrontUrl': governmentIdFrontUrl,
        if (governmentIdBackUrl != null) 'governmentIdBackUrl': governmentIdBackUrl,
        'selfieImageUrl': selfieImageUrl,
      },
    );
    if (res['success'] != true) {
      throw ApiException(
        res['message']?.toString() ?? 'Verification submit failed',
      );
    }
  }

  Future<Map<String, dynamic>> fetchVerificationStatus() async {
    final res = await _api.get(ApiEndpoints.verificationMe);
    if (res['success'] != true) {
      throw ApiException(
        res['message']?.toString() ?? 'Verification status failed',
      );
    }
    return Map<String, dynamic>.from(res['data'] as Map? ?? res);
  }

  Future<void> resubmitVerification(Map<String, dynamic> body) async {
    final res = await _api.post(ApiEndpoints.verificationResubmit, data: body);
    if (res['success'] != true) {
      throw ApiException(
        res['message']?.toString() ?? 'Verification resubmit failed',
      );
    }
  }

  Future<List<Map<String, dynamic>>> fetchCertificates() async {
    final res = await _api.get(ApiEndpoints.workerCertificates);
    if (res['success'] != true) {
      throw ApiException(
        res['message']?.toString() ?? 'Certificates fetch failed',
      );
    }
    final raw = res['data'] ?? res['certificates'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> uploadCertificate({
    required String certificateType,
    required String fileUrl,
    String? serviceCategory,
  }) async {
    final res = await _api.post(
      ApiEndpoints.workerCertificates,
      data: {
        'certificateType': certificateType,
        'fileUrl': fileUrl,
        if (serviceCategory != null) 'serviceCategory': serviceCategory,
      },
    );
    if (res['success'] != true) {
      throw ApiException(
        res['message']?.toString() ?? 'Certificate upload failed',
      );
    }
  }

  Future<void> deleteCertificate(String id) async {
    final res = await _api.delete(ApiEndpoints.workerCertificate(id));
    if (res['success'] != true) {
      throw ApiException(
        res['message']?.toString() ?? 'Certificate delete failed',
      );
    }
  }

  static WorkerProfile mapWorker(
    Map<String, dynamic> json, [
    double? userLat,
    double? userLng,
  ]) {
    final profile = json['workerProfile'];
    final profileMap = profile is Map
        ? Map<String, dynamic>.from(profile)
        : <String, dynamic>{};
    final skillsRaw = profileMap['skills'] ?? json['skills'];
    final skills = skillsRaw is List
        ? skillsRaw.map((e) => e.toString()).toList()
        : <String>[];
    final rating =
        (profileMap['rating'] as num?)?.toDouble() ??
        (json['rating'] as num?)?.toDouble() ??
        0.0;
    final jobs =
        (profileMap['jobsCompleted'] as num?)?.toInt() ??
        (profileMap['totalJobs'] as num?)?.toInt() ??
        (json['jobsCompleted'] as num?)?.toInt() ??
        (json['totalJobs'] as num?)?.toInt() ??
        0;
    final hourlyRate =
        (profileMap['rate'] as num?)?.toDouble() ??
        (profileMap['hourlyRate'] as num?)?.toDouble() ??
        (json['rate'] as num?)?.toDouble() ??
        0.0;
    final category = (profileMap['category'] ?? json['category'])?.toString();
    final bio = (profileMap['bio'] ?? json['bio'])?.toString();
    final experienceYears = (profileMap['experienceYears'] as num?)?.toInt();
    final reviewsRaw =
        json['reviews'] ??
        json['recentReviews'] ??
        profileMap['reviews'] ??
        profileMap['recentReviews'];
    var reviews = reviewsRaw is List
        ? reviewsRaw.whereType<Map>().map(_mapReview).toList()
        : <WorkerReview>[];
    if (reviews.isEmpty) {
      final recent = json['recentReviews'] ?? profileMap['recentReviews'];
      if (recent is List) {
        reviews = recent.whereType<Map>().map(_mapReview).toList();
      }
    }
    final reviewCount =
        (json['reviewCount'] as num?)?.toInt() ??
        (json['totalReviews'] as num?)?.toInt() ??
        (profileMap['reviewCount'] as num?)?.toInt() ??
        (profileMap['totalReviews'] as num?)?.toInt() ??
        reviews.length;
    final reliabilityRaw = json['reliability'];
    final reliability = reliabilityRaw is Map
        ? Map<String, dynamic>.from(reliabilityRaw)
        : <String, dynamic>{};
    final kycRaw = json['kycDocuments'];
    final kyc = kycRaw is Map ? Map<String, dynamic>.from(kycRaw) : {};

    // Distance calculation if coordinates are present
    double? distanceKm = (json['distanceKm'] as num?)?.toDouble();
    final loc = json['location'];
    if (loc is Map && userLat != null && userLng != null) {
      final coords = loc['coordinates'];
      if (coords is List && coords.length >= 2) {
        final wLng = (coords[0] as num).toDouble();
        final wLat = (coords[1] as num).toDouble();
        final dy = (wLat - userLat) * 111.0;
        final dx = (wLng - userLng) * 111.0;
        distanceKm ??= (dx * dx + dy * dy) > 0 ? (dx.abs() + dy.abs()) : 0.4;
        if (distanceKm < 0.1) distanceKm = 0.4;
      }
    }

    final categoriesRaw = profileMap['categories'] ?? json['categories'] ?? profileMap['categoryRates'] ?? json['categoryRates'];
    final categories = <String>[];
    if (categoriesRaw is List) {
      for (final c in categoriesRaw) {
        if (c is String && c.trim().isNotEmpty) {
          categories.add(c.trim());
        } else if (c is Map && c['category'] != null) {
          categories.add(c['category'].toString().trim());
        }
      }
    }
    if (category != null && category.isNotEmpty && !categories.any((c) => c.toLowerCase() == category.toLowerCase())) {
      categories.insert(0, category);
    }

    final rawWorkPhotos = profileMap['recentWorkPhotos'] ?? json['recentWorkPhotos'] ?? profileMap['photos'] ?? json['photos'];
    final recentWorkPhotos = <String>[];
    if (rawWorkPhotos is List) {
      for (final p in rawWorkPhotos) {
        if (p is String && p.trim().isNotEmpty) recentWorkPhotos.add(p.trim());
      }
    }

    return WorkerProfile(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      name: (json['name'] as String?) ?? 'Worker',
      skills: skills,
      rating: rating,
      jobsCompleted: jobs,
      reliabilityScore:
          (reliability['score'] as num?)?.toInt() ??
          (rating * 20).round().clamp(0, 100),
      avatarUrl:
          (json['avatar'] ??
                  profileMap['selfieImageUrl'] ??
                  profileMap['identityProofPhoto'])
              ?.toString(),
      category: category,
      categories: categories,
      title: (json['title'] ?? profileMap['title'])?.toString(),
      hourlyRate: hourlyRate > 0 ? hourlyRate : null,
      minimumCharge: (json['minimumCharge'] as num?)?.toDouble(),
      rateFormatted: json['rateFormatted']
          ?.toString()
          .replaceAll(RegExp(r'\s*/\s*hr\b', caseSensitive: false), ' base price')
          .replaceAll(RegExp(r'\s*/\s*hour\b', caseSensitive: false), ' base price'),
      distanceKm: distanceKm != null
          ? double.parse(distanceKm.toStringAsFixed(1))
          : null,
      distanceFormatted: json['distanceFormatted']?.toString(),
      isOnline: json['isOnline'] == true || profileMap['isOnline'] == true,
      isAvailable:
          json['isAvailable'] == true ||
          profileMap['isAvailable'] == true ||
          profileMap['isOnline'] == true ||
          json['isOnline'] == true,
      reviewCount: reviewCount,
      reviews: reviews,
      onTimeArrival: (reliability['onTimeArrival'] as num?)?.toDouble(),
      completionRate: (reliability['completionRate'] as num?)?.toDouble(),
      customerFeedback: (reliability['customerFeedback'] as num?)?.toDouble(),
      cancellationRate: (reliability['cancellationRate'] as num?)?.toDouble(),
      serviceRadiusKm:
          (profileMap['serviceRadiusKm'] as num?)?.toDouble() ??
          (json['serviceRadiusKm'] as num?)?.toDouble(),
      kycStatus: kyc['status']?.toString(),
      isEmailVerified: json['isEmailVerified'] == true,
      bio: bio,
      experienceYears: experienceYears,
      isVerified: json['isVerified'] != false,
      insured: json['insured'] == true || profileMap['insured'] == true,
      federationId: (profileMap['federationId'] ?? json['federationId'])?.toString(),
      federationName: (profileMap['federationName'] ?? json['federationName'] ?? 'National Labour Cooperative Federation (NLCF)')?.toString(),
      includedTasks: (profileMap['includedTasks'] is List
          ? (profileMap['includedTasks'] as List).map((e) => e.toString()).toList()
          : (json['includedTasks'] is List
              ? (json['includedTasks'] as List).map((e) => e.toString()).toList()
              : const <String>[])),
      excludedTasks: (profileMap['excludedTasks'] is List
          ? (profileMap['excludedTasks'] as List).map((e) => e.toString()).toList()
          : (json['excludedTasks'] is List
              ? (json['excludedTasks'] as List).map((e) => e.toString()).toList()
              : const <String>[])),
      recentWorkPhotos: recentWorkPhotos,
    );
  }

  Future<ReviewsPage> fetchWorkerReviews(
    String workerId, {
    int page = 1,
    int limit = 5,
  }) async {
    final res = await _api.get(
      ApiEndpoints.workerReviews(workerId),
      query: {'page': page, 'limit': limit},
    );
    if (res['success'] != true) {
      throw ApiException(res['message']?.toString() ?? 'Failed to load reviews');
    }
    final list = res['reviews'] ?? res['data'];
    final reviews = list is List
        ? list.whereType<Map>().map(_mapReview).toList()
        : <WorkerReview>[];
    final total = (res['total'] as num?)?.toInt() ?? reviews.length;
    final hasMore = res['hasMore'] == true || (page * limit < total);
    return ReviewsPage(
      reviews: reviews,
      hasMore: hasMore,
      page: page,
      total: total,
    );
  }

  static WorkerReview _mapReview(Map review) {
    final reviewer = review['reviewer'] ?? review['customer'];
    final reviewerMap = reviewer is Map ? reviewer : const <String, dynamic>{};
    final rawPhotos = review['photos'] ?? review['workPhotos'] ?? review['images'];
    final photos = <String>[];
    if (rawPhotos is List) {
      for (final p in rawPhotos) {
        if (p is String && p.trim().isNotEmpty) photos.add(p.trim());
      }
    }
    final rawBadges =
        review['badgesGiven'] ?? review['badges'] ?? review['traits'];
    final badges = <String>[];
    if (rawBadges is List) {
      for (final b in rawBadges) {
        if (b is String && b.trim().isNotEmpty) badges.add(b.trim());
      }
    } else if (rawBadges is String && rawBadges.trim().isNotEmpty) {
      badges.addAll(
        rawBadges.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty),
      );
    }
    final avatar = (review['avatar'] ??
            review['avatarUrl'] ??
            review['reviewerAvatar'] ??
            reviewerMap['avatar'])
        ?.toString();

    return WorkerReview(
      id: (review['_id'] ?? review['id'])?.toString(),
      bookingId: (review['bookingId'] ?? review['booking'])?.toString(),
      reviewerName:
          (review['reviewerName'] ??
                  review['customerName'] ??
                  reviewerMap['name'] ??
                  'Customer')
              .toString(),
      rating: (review['rating'] as num?)?.toDouble() ?? 0,
      comment: (review['comment'] ??
              review['feedback'] ??
              review['description'] ??
              review['text'] ??
              review['review'] ??
              '')
          .toString(),
      createdAt: DateTime.tryParse(
        (review['createdAt'] ?? review['date'] ?? '').toString(),
      ),
      avatarUrl: avatar,
      photos: photos,
      badgesGiven: badges,
    );
  }
}

class ReviewsPage {
  const ReviewsPage({
    required this.reviews,
    required this.hasMore,
    required this.page,
    required this.total,
  });

  final List<WorkerReview> reviews;
  final bool hasMore;
  final int page;
  final int total;
}


class WorkersPage {
  const WorkersPage({
    required this.workers,
    required this.hasMore,
    required this.nextOffset,
    this.code,
    this.message,
    this.searchRadiusKm,
  });

  final List<WorkerProfile> workers;
  final bool hasMore;
  final int nextOffset;
  final String? code;
  final String? message;
  final int? searchRadiusKm;
}

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/location/app_location.dart';
import '../../../core/constants/map_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_enpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/media_upload_api.dart';
import '../../../shared/models/models.dart';

class PriceEstimate {
  const PriceEstimate({
    required this.laborMin,
    required this.laborMax,
    required this.materialsMin,
    required this.materialsMax,
    required this.serviceFee,
    required this.minTotal,
    required this.maxTotal,
    this.urgentFee = 0,
    this.isEmergency = false,
  });

  final double laborMin;
  final double laborMax;
  final double materialsMin;
  final double materialsMax;
  final double serviceFee;
  final double minTotal;
  final double maxTotal;
  final double urgentFee;
  final bool isEmergency;
}

class BookingsApiRepository {
  BookingsApiRepository({ApiClient? client})
    : _api = client ?? ApiServices.client;

  final ApiClient _api;
  late final MediaUploadApi _uploads = MediaUploadApi(client: _api);

  /// Plain Dio — never reuse [_api.dio] (JWT / lang headers break Mapbox).
  static final Dio _mapboxDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: const {'Accept': 'application/json'},
    ),
  );

  /// Road-snapped path via Mapbox Directions (road-network shortest path).
  /// Not a hand-rolled A* — Mapbox routes on the real road graph.
  Future<List<MapCoordinate>> fetchDrivingRoute({
    required MapCoordinate from,
    required MapCoordinate to,
  }) async {
    if (!MapConstants.hasToken) {
      debugPrint('fetchDrivingRoute: missing Mapbox token');
      return const [];
    }
    if ((from.lat - to.lat).abs() < 1e-7 && (from.lng - to.lng).abs() < 1e-7) {
      return const [];
    }
    try {
      final response = await _mapboxDio.get<Map<String, dynamic>>(
        'https://api.mapbox.com/directions/v5/mapbox/driving/'
        '${from.lng},${from.lat};${to.lng},${to.lat}',
        queryParameters: {
          'alternatives': 'false',
          'geometries': 'geojson',
          'overview': 'full',
          'steps': 'false',
          // Snap endpoints onto nearest routable roads.
          'radiuses': 'unlimited;unlimited',
          'access_token': MapConstants.accessToken,
        },
      );
      final body = response.data;
      if (body == null) return const [];
      if (body['code'] != null && body['code'] != 'Ok') {
        debugPrint('fetchDrivingRoute Mapbox code=${body['code']} msg=${body['message']}');
        return const [];
      }
      final routes = body['routes'];
      if (routes is! List || routes.isEmpty) return const [];
      final geometry = routes.first is Map ? routes.first['geometry'] : null;
      final coordinates = geometry is Map ? geometry['coordinates'] : null;
      if (coordinates is! List) return const [];
      final points = coordinates
          .whereType<List>()
          .where((point) => point.length >= 2)
          .map((point) {
            return MapCoordinate(
              lng: (point[0] as num).toDouble(),
              lat: (point[1] as num).toDouble(),
            );
          })
          .toList();
      return points.length >= 2 ? points : const [];
    } catch (e) {
      debugPrint('fetchDrivingRoute failed: $e');
      return const [];
    }
  }

  Future<MapCoordinate?> trackWorkerPosition(String bookingId) async {
    final res = await _api.get(ApiEndpoints.bookingTrack(bookingId));
    final raw =
        res['location'] ??
        res['workerLocation'] ??
        res['position'] ??
        res['data'];
    if (raw is! Map) return null;
    final coordinates = raw['coordinates'];
    if (coordinates is List && coordinates.length >= 2) {
      return MapCoordinate(
        lng: (coordinates[0] as num?)?.toDouble() ?? 0,
        lat: (coordinates[1] as num?)?.toDouble() ?? 0,
      );
    }
    final lat = (raw['lat'] ?? raw['latitude']) as num?;
    final lng = (raw['lng'] ?? raw['longitude']) as num?;
    if (lat == null || lng == null) return null;
    return MapCoordinate(lat: lat.toDouble(), lng: lng.toDouble());
  }

  Future<PriceEstimate> estimate({
    required String serviceId,
    double estimatedHours = 1,
    bool isEmergency = false,
  }) async {
    final res = await _api.post(
      ApiEndpoints.bookingEstimate,
      data: {
        'serviceId': serviceId,
        'estimatedHours': estimatedHours,
        if (isEmergency) 'isEmergency': true,
        if (isEmergency) 'bookingType': 'EMERGENCY_SOS',
      },
    );
    if (res['success'] != true) {
      throw ApiException(res['message']?.toString() ?? 'Estimate failed');
    }
    final est = res['estimate'] as Map<String, dynamic>? ?? {};
    final labor = est['laborEstimate'] as Map<String, dynamic>? ?? {};
    final materials = est['materialsParts'] as Map<String, dynamic>? ?? {};
    final total = est['totalEstimate'] as Map<String, dynamic>? ?? {};
    return PriceEstimate(
      laborMin: (labor['min'] as num?)?.toDouble() ?? 0,
      laborMax: (labor['max'] as num?)?.toDouble() ?? 0,
      materialsMin: (materials['min'] as num?)?.toDouble() ?? 0,
      materialsMax: (materials['max'] as num?)?.toDouble() ?? 0,
      serviceFee: (est['serviceFee'] as num?)?.toDouble() ?? 0,
      urgentFee: (est['urgentFee'] as num?)?.toDouble() ?? 0,
      isEmergency: est['isEmergency'] == true || isEmergency,
      minTotal: (total['min'] as num?)?.toDouble() ?? 0,
      maxTotal: (total['max'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Dedicated SOS create — surcharge from Settings, optional customer offeredPrice as base.
  Future<Booking> createEmergency({
    required String serviceId,
    required String issueDescription,
    required double latitude,
    required double longitude,
    double? offeredPrice,
    String serviceTitle = 'Emergency Service',
  }) async {
    final res = await _api.post(
      ApiEndpoints.createEmergencyBooking,
      data: {
        'serviceId': serviceId,
        'issueDescription': issueDescription,
        'latitude': latitude,
        'longitude': longitude,
        if (offeredPrice != null) 'offeredPrice': offeredPrice,
      },
    );
    if (res['success'] != true || res['booking'] == null) {
      throw ApiException(
        res['message']?.toString() ?? 'Emergency booking failed',
      );
    }
    return mapBooking(
      Map<String, dynamic>.from(res['booking'] as Map),
      serviceTitleFallback: serviceTitle,
    );
  }

  Future<void> triggerSos(String bookingId) async {
    final res = await _api.post(ApiEndpoints.bookingSos(bookingId));
    if (res['success'] != true) {
      throw ApiException(res['message']?.toString() ?? 'SOS alert failed');
    }
  }

  /// Validate coupon against an amount (checkout preview).
  Future<Map<String, dynamic>> validateCoupon({
    required String couponCode,
    required double amount,
    String? serviceId,
    String? category,
  }) async {
    final res = await _api.post(
      ApiEndpoints.validateCoupon,
      data: {
        'couponCode': couponCode.trim().toUpperCase(),
        'amount': amount,
        if (serviceId != null) 'serviceId': serviceId,
        if (category != null) 'category': category,
      },
    );
    if (res['success'] != true) {
      throw ApiException(res['message']?.toString() ?? 'Invalid coupon');
    }
    return Map<String, dynamic>.from(res['data'] as Map? ?? res);
  }

  /// Persist coupon onto booking invoice — backend recomputes totalAmount.
  Future<Booking> applyCoupon({
    required String bookingId,
    required String couponCode,
    String serviceTitle = 'Service',
  }) async {
    final res = await _api.post(
      ApiEndpoints.applyCoupon(bookingId),
      data: {'couponCode': couponCode.trim().toUpperCase()},
    );
    if (res['success'] != true || res['booking'] == null) {
      throw ApiException(res['message']?.toString() ?? 'Apply coupon failed');
    }
    return mapBooking(
      Map<String, dynamic>.from(res['booking'] as Map),
      serviceTitleFallback: serviceTitle,
    );
  }

  Future<Booking> removeCoupon({
    required String bookingId,
    String serviceTitle = 'Service',
  }) async {
    // Use apply-coupon {remove:true} — works after backend restart without a
    // dedicated /remove-coupon route on older tunnel processes.
    final res = await _api.post(
      ApiEndpoints.applyCoupon(bookingId),
      data: {'remove': true},
    );
    if (res['success'] != true || res['booking'] == null) {
      throw ApiException(res['message']?.toString() ?? 'Remove coupon failed');
    }
    return mapBooking(
      Map<String, dynamic>.from(res['booking'] as Map),
      serviceTitleFallback: serviceTitle,
    );
  }

  Future<Booking> create({
    required String serviceId,
    required String addressLine,
    String? problemDescription,
    String? workerId,
    DateTime? scheduledTime,
    double? lng,
    double? lat,
    String serviceTitle = 'Service',
    List<String> photoPaths = const [],
    List<String> videoPaths = const [],
    List<String> problemPhotoUrls = const [],
    List<String> problemVideoUrls = const [],
    Map<String, dynamic>? invoice,
    String? bookingType,
    bool isEmergency = false,
    String? timeSlot,
  }) async {
    final loc = AppLocation.instance;
    final useLng = lng ?? (loc.hasFix ? loc.requireLng : null);
    final useLat = lat ?? (loc.hasFix ? loc.requireLat : null);
    if (useLng == null || useLat == null) {
      throw ApiException('Location required to create booking');
    }

    final uploadedPhotos = [...problemPhotoUrls];
    for (final path in photoPaths) {
      final url = await _uploads.uploadIfLocal(path);
      if (url != null) uploadedPhotos.add(url);
    }
    final uploadedVideos = [...problemVideoUrls];
    for (final path in videoPaths) {
      final url = await _uploads.uploadIfLocal(path);
      if (url != null) uploadedVideos.add(url);
    }
    final data = <String, dynamic>{
      'serviceId': serviceId,
      if (workerId != null) 'workerId': workerId,
      if (problemDescription != null) 'problemDescription': problemDescription,
      if (uploadedPhotos.isNotEmpty) 'problemPhotos': uploadedPhotos,
      if (uploadedVideos.isNotEmpty) 'problemVideos': uploadedVideos,
      'addressLine': addressLine,
      'coordinates': [useLng, useLat],
      if (scheduledTime != null)
        'scheduledTime': scheduledTime.toUtc().toIso8601String(),
      if (invoice != null) 'invoice': invoice,
      if (bookingType != null) 'bookingType': bookingType,
      if (isEmergency) 'isEmergency': true,
      if (timeSlot != null) 'timeSlot': timeSlot,
    };

    final res = await _api.post(ApiEndpoints.createBooking, data: data);
    if (res['success'] != true || res['booking'] == null) {
      throw ApiException(res['message']?.toString() ?? 'Booking failed');
    }
    return mapBooking(
      Map<String, dynamic>.from(res['booking'] as Map),
      serviceTitleFallback: serviceTitle,
    );
  }

  Future<Booking> getById(
    String bookingId, {
    String serviceTitle = 'Service',
    bool forceNetwork = false,
  }) async {
    final id = bookingId.trim();
    if (id.isEmpty || id == '/' || id.startsWith('#')) {
      throw ApiException('Booking ID missing');
    }
    final res = await _api.get(
      ApiEndpoints.bookingById(id),
      forceNetwork: forceNetwork,
    );
    final rawBooking = res['booking'] ?? res['data'];
    if (res['success'] != true || rawBooking is! Map) {
      throw ApiException(res['message']?.toString() ?? 'Booking not found');
    }
    return mapBooking(
      Map<String, dynamic>.from(rawBooking),
      serviceTitleFallback: serviceTitle,
    );
  }

  /// Worker tapped / started turn-by-turn navigation — unlocks customer track.
  Future<void> startNavigation(String bookingId) async {
    final res = await _api.post(ApiEndpoints.startNavigation(bookingId));
    if (res['success'] != true) {
      throw ApiException(
        res['message']?.toString() ?? 'Could not start navigation',
      );
    }
  }

  Future<BookingInvoice> invoice(String bookingId) async {
    final res = await _api.get(ApiEndpoints.bookingInvoice(bookingId));
    if (res['success'] != true || res['invoice'] is! Map) {
      throw ApiException(res['message']?.toString() ?? 'Invoice not found');
    }
    final invoice = Map<String, dynamic>.from(res['invoice'] as Map);
    final details = res['bookingDetails'] is Map
        ? Map<String, dynamic>.from(res['bookingDetails'] as Map)
        : <String, dynamic>{};
    final service = details['service'] is Map
        ? Map<String, dynamic>.from(details['service'] as Map)
        : <String, dynamic>{};
    final customer = details['customer'] is Map
        ? Map<String, dynamic>.from(details['customer'] as Map)
        : <String, dynamic>{};
    final worker = details['worker'] is Map
        ? Map<String, dynamic>.from(details['worker'] as Map)
        : <String, dynamic>{};
    return BookingInvoice(
      bookingId: details['bookingId']?.toString() ?? '#$bookingId',
      serviceName: (service['name'] ?? service['title'] ?? 'Service')
          .toString(),
      status: details['status']?.toString() ?? 'PENDING',
      baseServiceFee: (invoice['baseServiceFee'] as num?)?.toDouble() ?? 0,
      extraPartsTotal: (invoice['extraPartsTotal'] as num?)?.toDouble() ?? 0,
      platformFee: (invoice['platformFee'] as num?)?.toDouble() ?? 0,
      totalAmount: (invoice['totalAmount'] as num?)?.toDouble() ?? 0,
      paymentStatus: invoice['paymentStatus']?.toString(),
      paymentMethod: invoice['paymentMethod']?.toString(),
      transactionId: invoice['transactionId']?.toString(),
      customerName: customer['name']?.toString(),
      customerPhone: customer['phone']?.toString(),
      workerName: worker['name']?.toString(),
      workerPhone: worker['phone']?.toString(),
      addOns: _mapAddOns(details['addOns']),
      jobStartedAt: _parseDate(details['jobStartedAt']),
      jobCompletedAt: _parseDate(details['jobCompletedAt']),
      couponCode: invoice['couponCode']?.toString(),
      couponDiscount: (invoice['couponDiscount'] as num?)?.toDouble() ?? 0,
      urgentFee: (invoice['urgentFee'] as num?)?.toDouble() ?? 0,
    );
  }

  Future<Booking> cancel(
    String bookingId, {
    String serviceTitle = 'Service',
  }) async {
    final res = await _api.patch(ApiEndpoints.cancelBooking(bookingId));
    if (res['success'] != true) {
      throw ApiException(res['message']?.toString() ?? 'Cancel failed');
    }
    final booking = res['booking'];
    if (booking is Map) {
      return mapBooking(
        Map<String, dynamic>.from(booking),
        serviceTitleFallback: serviceTitle,
      );
    }
    return getById(bookingId, serviceTitle: serviceTitle);
  }

  Future<void> workerCancel(String bookingId) async {
    final res = await _api.post(ApiEndpoints.workerCancelBooking(bookingId));
    if (res['success'] != true) {
      throw ApiException(res['message']?.toString() ?? 'Cancel failed');
    }
  }

  Future<Booking> updateBooking({
    required String bookingId,
    String? problemDescription,
    DateTime? scheduledTime,
    String? addressLine,
    double? lat,
    double? lng,
  }) async {
    final Map<String, dynamic> data = {};
    if (problemDescription != null) data['problemDescription'] = problemDescription;
    if (scheduledTime != null) data['scheduledTime'] = scheduledTime.toIso8601String();
    if (addressLine != null || (lat != null && lng != null)) {
      final Map<String, dynamic> serviceAddress = {};
      if (addressLine != null) serviceAddress['addressLine'] = addressLine;
      if (lat != null && lng != null) {
        serviceAddress['coordinates'] = [lng, lat];
      }
      data['serviceAddress'] = serviceAddress;
    }
    final res = await _api.patch(ApiEndpoints.bookingById(bookingId), data: data);
    if (res['success'] != true) {
      throw ApiException(res['message']?.toString() ?? 'Update failed');
    }
    final booking = res['booking'];
    if (booking is Map) {
      return mapBooking(Map<String, dynamic>.from(booking));
    }
    return getById(bookingId);
  }

  Future<Booking> submitPriceEstimation(
    String bookingId, {
    double? parts,
    double? serviceCharge,
    String? notes,
  }) async {
    final res = await _api.post(
      '/api/bookings/$bookingId/submit-estimation',
      data: {
        // Labor intentionally omitted — base price is locked server-side.
        'partsEstimate': parts ?? 0,
        'estimatedPartsCost': parts ?? 0,
        'serviceCharge': serviceCharge ?? 0,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    );
    if (res['success'] != true) {
      throw ApiException(res['message']?.toString() ?? 'Failed to submit estimation');
    }
    final booking = res['booking'];
    if (booking is Map) {
      return mapBooking(Map<String, dynamic>.from(booking));
    }
    return getById(bookingId);
  }

  Future<Booking> acceptEstimation(String bookingId) async {
    final res = await _api.post('/api/bookings/$bookingId/accept-estimation');
    if (res['success'] != true) {
      throw ApiException(res['message']?.toString() ?? 'Failed to accept estimation');
    }
    final booking = res['booking'];
    if (booking is Map) {
      return mapBooking(Map<String, dynamic>.from(booking));
    }
    return getById(bookingId);
  }

  Future<Booking> verifyArrivalOtp({
    required String bookingId,
    required String otp,
    String serviceTitle = 'Service',
  }) async {
    final res = await _api.post(
      ApiEndpoints.verifyArrivalOtp(bookingId),
      data: {'otp': otp},
    );
    if (res['success'] != true) {
      throw ApiException(res['message']?.toString() ?? 'OTP failed');
    }
    final booking = res['booking'];
    if (booking is Map) {
      return mapBooking(
        Map<String, dynamic>.from(booking),
        serviceTitleFallback: serviceTitle,
      );
    }
    return getById(bookingId, serviceTitle: serviceTitle);
  }

  Future<Map<String, dynamic>> complete(String bookingId) async {
    final res = await _api.post(ApiEndpoints.completeBooking(bookingId));
    if (res['success'] != true) {
      throw ApiException(res['message']?.toString() ?? 'Complete failed');
    }
    return Map<String, dynamic>.from(res);
  }

  Future<void> addParts({
    required String bookingId,
    required List<Map<String, dynamic>> extraItems,
    bool replace = false,
  }) async {
    final res = await _api.patch(
      ApiEndpoints.addParts(bookingId),
      data: {
        'extraItems': extraItems,
        'replace': replace,
      },
    );
    if (res['success'] != true) {
      throw ApiException(res['message']?.toString() ?? 'Add parts failed');
    }
  }

  Future<List<Booking>> history({bool forceNetwork = false}) async {
    final res = await _api.get(
      ApiEndpoints.bookingHistory,
      forceNetwork: forceNetwork,
    );
    final data = res['data'] ?? res['bookings'];
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => mapBooking(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<WorkerJob> workerJobById(String bookingId) async {
    final res = await _api.get(ApiEndpoints.bookingById(bookingId));
    if (res['success'] != true || res['booking'] == null) {
      throw ApiException(res['message']?.toString() ?? 'Job not found');
    }
    return mapWorkerJob(Map<String, dynamic>.from(res['booking'] as Map));
  }

  Future<List<WorkerJob>> workerIncoming() =>
      _workerJobs(ApiEndpoints.workerIncomingJobs, JobStatus.incoming);

  Future<List<WorkerJob>> workerActive() =>
      _workerJobs(ApiEndpoints.workerActiveJobs, JobStatus.active);

  Future<List<WorkerJob>> workerCompleted() =>
      _workerJobs(ApiEndpoints.workerCompletedJobs, JobStatus.completed);

  Future<List<WorkerJob>> _workerJobs(String path, JobStatus status) async {
    final res = await _api.get(path);
    if (res['success'] != true) {
      throw ApiException(res['message']?.toString() ?? 'Jobs failed');
    }
    final data = res['data'] ?? res['bookings'];
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .where((e) {
          if (status != JobStatus.incoming) return true;
          final reason = e['declineReason']?.toString().trim();
          final declinedBy = e['declinedBy'];
          if (reason != null && reason.isNotEmpty) return false;
          if (declinedBy != null && declinedBy.toString().trim().isNotEmpty) {
            return false;
          }
          final raw = (e['status'] ?? '').toString().toUpperCase();
          return raw != 'CANCELLED' && raw != 'CANCELED';
        })
        .map(
          (e) => mapWorkerJob(
            Map<String, dynamic>.from(e),
            fallbackStatus: status,
          ),
        )
        .toList();
  }

  Future<void> accept(String bookingId) async {
    final res = await _api.post(ApiEndpoints.acceptJob(bookingId));
    if (res['success'] != true) {
      throw ApiException(res['message']?.toString() ?? 'Accept failed');
    }
  }

  Future<void> decline(String bookingId, {String reason = 'OTHER'}) async {
    final res = await _api.post(
      ApiEndpoints.declineJob(bookingId),
      data: {'reason': reason},
    );
    if (res['success'] != true) {
      throw ApiException(res['message']?.toString() ?? 'Decline failed');
    }
  }

  Future<void> startJob(String bookingId) async {
    final res = await _api.post(ApiEndpoints.startJob(bookingId));
    if (res['success'] != true) {
      throw ApiException(res['message']?.toString() ?? 'Start failed');
    }
  }

  static WorkerJob mapWorkerJob(
    Map<String, dynamic> json, {
    JobStatus fallbackStatus = JobStatus.incoming,
  }) {
    final booking = mapBooking(json);
    double? customerLat;
    double? customerLng;
    final serviceAddress = json['serviceAddress'];
    if (serviceAddress is Map) {
      final location = serviceAddress['location'];
      final coordinates = location is Map ? location['coordinates'] : null;
      if (coordinates is List && coordinates.length >= 2) {
        customerLng = (coordinates[0] as num?)?.toDouble();
        customerLat = (coordinates[1] as num?)?.toDouble();
      }
    }
    final customer = json['customer'];
    var customerName = 'Customer';
    String? customerPhone;
    String? customerAvatar;
    if (customer is Map) {
      customerName = (customer['name'] as String?) ?? customerName;
      customerPhone = customer['phone']?.toString();
      customerAvatar = (customer['avatar'] ?? customer['profileImage'])?.toString();
    }
    final rawStatus = (json['status'] ?? '').toString().toUpperCase();
    final status = switch (rawStatus) {
      'PENDING' => JobStatus.incoming,
      'SEARCHING' => JobStatus.incoming,
      'APPROVED' => JobStatus.active,
      'ACCEPTED' => JobStatus.active,
      'ARRIVED' => JobStatus.active,
      'IN_PROGRESS' => JobStatus.active,
      'COMPLETED' => JobStatus.completed,
      'CANCELLED' => JobStatus.completed,
      _ => JobStatus.active,
    };

    List<String> strings(dynamic value) => value is List
        ? value.whereType<String>().where((s) => s.isNotEmpty).toList()
        : const [];

    DateTime? parseDate(dynamic v) => v is String ? DateTime.tryParse(v) : null;

    // Service metadata
    final service = json['service'];
    String? serviceCategory;
    String? serviceImage;
    if (service is Map) {
      serviceCategory = service['category']?.toString();
      serviceImage = (service['image'] ?? service['imageUrl'])?.toString();
    }

    // Invoice breakdown
    final invoice = json['invoice'];
    double? baseServiceFee;
    double? platformFee;
    double? extraPartsTotal;
    if (invoice is Map) {
      baseServiceFee = (invoice['baseServiceFee'] as num?)?.toDouble();
      platformFee = (invoice['platformFee'] as num?)?.toDouble();
      extraPartsTotal = (invoice['extraPartsTotal'] as num?)?.toDouble();
    }

    return WorkerJob(
      id: booking.id,
      title: booking.serviceTitle,
      customerName: customerName,
      address: booking.address ?? '',
      pay: booking.invoice?.workerPayout ??
          booking.workerPayout,
      status: status == JobStatus.incoming ? fallbackStatus : status,
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ??
          _parseDistanceKm(json['distanceFormatted'] ?? json['distanceDisplay']),
      customerLat: customerLat,
      customerLng: customerLng,
      customerPhone: customerPhone,
      customerAvatar: customerAvatar,
      problemDescription: json['problemDescription']?.toString(),
      problemPhotos: strings(json['problemPhotos']),
      problemVideos: strings(json['problemVideos'] ?? (json['problemVideoUrl'] != null ? [json['problemVideoUrl']] : null)),
      serviceCategory: serviceCategory,
      serviceImage: serviceImage,
      arrivalOtp: json['arrivalOtp']?.toString(),
      baseServiceFee: baseServiceFee,
      platformFee: platformFee,
      extraPartsTotal: extraPartsTotal,
      addOns: _mapAddOns(json['addOns']),
      jobStartedAt: parseDate(json['jobStartedAt']),
      jobCompletedAt: parseDate(json['jobCompletedAt']),
      rawStatus: rawStatus,
      invoice: invoice is Map ? BookingInvoice.fromJson(Map<String, dynamic>.from(invoice)) : null,
      scheduledAt: parseDate(json['scheduledTime'] ?? json['scheduledAt']),
      bookingType: json['bookingType']?.toString(),
      isEmergency: json['isEmergency'] == true || (json['bookingType']?.toString().toUpperCase() == 'EMERGENCY_SOS'),
    );
  }

  /// Prefer [distanceKm]; fall back to number inside formatted strings like "5.1 km".
  static double _parseDistanceKm(dynamic raw) {
    if (raw == null) return 0;
    if (raw is num) return raw.toDouble();
    final match = RegExp(r'([\d.]+)').firstMatch(raw.toString());
    if (match == null) return 0;
    return double.tryParse(match.group(1)!) ?? 0;
  }

  static Booking mapBooking(
    Map<String, dynamic> json, {
    String serviceTitleFallback = 'Service',
  }) {
    final service = json['service'];
    String serviceId;
    String serviceTitle = serviceTitleFallback;
    if (service is Map) {
      serviceId = (service['_id'] ?? service['id'] ?? '').toString();
      serviceTitle =
          (service['title'] ?? service['name'])?.toString() ??
          serviceTitleFallback;
    } else {
      serviceId = service?.toString() ?? '';
    }

    final worker = json['worker'];
    String? workerId;
    String? workerName;
    String? workerAvatar;
    double? workerRating;
    int? workerJobsCompleted;
    if (worker is Map) {
      workerId = (worker['_id'] ?? worker['id'])?.toString();
      workerName = worker['name'] as String?;
      workerAvatar = worker['avatar'] as String?;
      final profile = worker['workerProfile'];
      final profileMap = profile is Map ? profile : null;
      workerRating = (profileMap?['rating'] as num?)?.toDouble() ??
          (worker['rating'] as num?)?.toDouble() ??
          (worker['avgRating'] as num?)?.toDouble();
      workerJobsCompleted = (profileMap?['totalJobs'] as num?)?.toInt() ??
          (worker['totalJobs'] as num?)?.toInt() ??
          (worker['jobsCompleted'] as num?)?.toInt() ??
          (worker['ratingCount'] as num?)?.toInt();
    } else if (worker != null) {
      workerId = worker.toString();
    }

    final customer = json['customer'];
    final customerId = customer is Map
        ? (customer['_id'] ?? customer['id'])?.toString()
        : (customer != null ? customer.toString() : null);
    final customerName = customer is Map ? customer['name']?.toString() : null;
    final customerPhone = customer is Map
        ? customer['phone']?.toString()
        : null;
    final customerAvatar = customer is Map
        ? (customer['avatar'] ?? customer['profileImage'])?.toString()
        : null;

    final address = json['serviceAddress'];
    String? addressLine;
    double? customerLat;
    double? customerLng;
    if (address is Map) {
      addressLine = address['addressLine'] as String?;
      final location = address['location'];
      final coordinates = location is Map ? location['coordinates'] : null;
      if (coordinates is List && coordinates.length >= 2) {
        customerLng = (coordinates[0] as num?)?.toDouble();
        customerLat = (coordinates[1] as num?)?.toDouble();
      }
    } else if (address is String) {
      addressLine = address;
    }

    final invoice = json['invoice'];
    Map<String, dynamic>? invoiceMap;
    if (invoice is Map) {
      invoiceMap = Map<String, dynamic>.from(invoice);
    }

    final double? totalAmount = (invoiceMap?['totalAmount'] as num?)?.toDouble() ??
        (json['totalAmount'] as num?)?.toDouble() ??
        (json['totalPrice'] as num?)?.toDouble() ??
        (json['total'] as num?)?.toDouble() ??
        (json['amount'] as num?)?.toDouble();

    final double? extraPartsTotal = (invoiceMap?['extraPartsTotal'] as num?)?.toDouble() ??
        (json['extraPartsTotal'] as num?)?.toDouble();

    final double? platformFee = (invoiceMap?['platformFee'] as num?)?.toDouble() ??
        (json['platformFee'] as num?)?.toDouble();

    final double? urgentFee = (invoiceMap?['urgentFee'] as num?)?.toDouble() ??
        (json['urgentFee'] as num?)?.toDouble();

    final double? baseServiceFee = (invoiceMap?['baseServiceFee'] as num?)?.toDouble() ??
        (json['baseServiceFee'] as num?)?.toDouble();

    final BookingInvoice? parsedInvoice = invoiceMap != null
        ? BookingInvoice.fromJson(invoiceMap)
        : (totalAmount != null && totalAmount > 0
            ? BookingInvoice(
                bookingId: (json['bookingId'] ?? json['_id'] ?? json['id'] ?? '').toString(),
                serviceName: serviceTitle,
                status: json['status']?.toString() ?? 'PENDING',
                baseServiceFee: baseServiceFee ?? 0,
                extraPartsTotal: extraPartsTotal ?? 0,
                platformFee: platformFee ?? 0,
                totalAmount: totalAmount,
              )
            : null);

    final estimationRaw = json['workerEstimation'];
    final WorkerEstimation? workerEstimation = estimationRaw is Map
        ? WorkerEstimation.fromJson(Map<String, dynamic>.from(estimationRaw))
        : null;

    final addOns = _mapAddOns(json['addOns']);

    final scheduled = json['scheduledTime'];
    DateTime? scheduledAt;
    if (scheduled is String) {
      scheduledAt = DateTime.tryParse(scheduled);
    }

    DateTime? parseDate(dynamic value) =>
        value is String ? DateTime.tryParse(value) : null;

    List<String> strings(dynamic value) => value is List
        ? value.whereType<String>().where((item) => item.isNotEmpty).toList()
        : const [];

    final serviceMap = service is Map ? service : const <String, dynamic>{};
    final serviceBasePrice = (serviceMap['basePrice'] as num?)?.toDouble() ?? 0.0;
    final double estimatedPrice = (json['estimatedPrice'] as num?)?.toDouble() ??
        (baseServiceFee != null && baseServiceFee > 0
            ? baseServiceFee
            : (serviceBasePrice > 0 ? serviceBasePrice : (totalAmount ?? 0.0)));

    final bookingId = json['bookingId']?.toString();
    final displayId = bookingId != null && bookingId.isNotEmpty
        ? bookingId
        : null;

    return Booking(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      serviceId: serviceId,
      serviceTitle: serviceTitle,
      status: mapStatus(json['status']?.toString(), json: json),
      estimatedPrice: estimatedPrice,
      workerId: workerId,
      workerName: workerName,
      address: addressLine,
      scheduledAt: scheduledAt,
      addOns: addOns,
      baseServiceFee: baseServiceFee,
      platformFee: platformFee,
      extraPartsTotal: extraPartsTotal,
      displayId: displayId,
      serviceCategory: serviceMap['category']?.toString(),
      serviceImage: (serviceMap['image'] ?? serviceMap['imageUrl'])?.toString(),
      estimatedTime: serviceMap['estimatedTime']?.toString(),
      whatsIncluded: strings(serviceMap['whatsIncluded']),
      problemDescription: json['problemDescription']?.toString(),
      problemPhotos: strings(json['problemPhotos']),
      problemVideos: strings(json['problemVideos']),
      paymentMethod: invoice is Map
          ? invoice['paymentMethod']?.toString()
          : null,
      paymentStatus: invoice is Map
          ? invoice['paymentStatus']?.toString()
          : null,
      transactionId: invoice is Map
          ? invoice['transactionId']?.toString()
          : null,
      arrivalOtp: json['arrivalOtp']?.toString(),
      createdAt: parseDate(json['createdAt']),
      jobStartedAt: parseDate(json['jobStartedAt']),
      jobCompletedAt: parseDate(json['jobCompletedAt']),
      isReviewed: json['isReviewed'] == true,
      workerReviewed: json['workerReviewed'] == true,
      workerAvatar: workerAvatar,
      workerRating: workerRating,
      workerJobsCompleted: workerJobsCompleted,
      customerId: customerId,
      customerName: customerName,
      customerPhone: customerPhone,
      customerAvatar: customerAvatar,
      customerLat: customerLat,
      customerLng: customerLng,
      rawStatus: json['status']?.toString(),
      bookingType: json['bookingType']?.toString(),
      isEmergency: json['isEmergency'] == true || (json['bookingType']?.toString() == 'EMERGENCY_SOS'),
      urgentFee: urgentFee ??
          (invoice is Map ? (invoice['urgentFee'] as num?)?.toDouble() : null) ??
          (json['urgentFee'] as num?)?.toDouble(),
      timeSlot: json['timeSlot']?.toString(),
      totalAmount: totalAmount,
      invoice: parsedInvoice,
      workerEstimation: workerEstimation,
      workerNavigationStartedAt: parseDate(json['workerNavigationStartedAt']) ??
          (json['workerNavigationStarted'] == true
              ? DateTime.fromMillisecondsSinceEpoch(0)
              : null),
      declineReason: json['declineReason']?.toString(),
      declinedBy: () {
        final raw = json['declinedBy'];
        if (raw is Map) return (raw['_id'] ?? raw['id'])?.toString();
        return raw?.toString();
      }(),
      cancelReason: json['cancelReason']?.toString(),
      cancelledBy: () {
        final raw = json['cancelledBy'];
        if (raw is Map) return (raw['_id'] ?? raw['id'])?.toString();
        return raw?.toString();
      }(),
      cancelledAt: parseDate(json['cancelledAt']),
    );
  }

  static BookingStatus mapStatus(String? raw, {Map? json}) {
    final upper = (raw ?? '').toUpperCase();
    final declined = (json?['declineReason'] != null &&
            json!['declineReason'].toString().trim().isNotEmpty) ||
        (json?['declinedBy'] != null &&
            json!['declinedBy'].toString().trim().isNotEmpty);
    // Legacy bug: decline left status PENDING — treat as cancelled.
    if (declined && (upper == 'PENDING' || upper == 'SEARCHING' || upper.isEmpty)) {
      return BookingStatus.cancelled;
    }
    switch (upper) {
      case 'SEARCHING':
      case 'PENDING':
        return BookingStatus.searching;
      case 'ASSIGNED':
      case 'ACCEPTED':
      case 'APPROVED':
      case 'EN_ROUTE':
        return BookingStatus.accepted;
      case 'ARRIVED':
      case 'ESTIMATION_GIVEN':
      case 'ESTIMATION_SUBMITTED':
      case 'READY_TO_START':
        // Still pre-work — do not treat as inProgress or UI jumps to "work started".
        return BookingStatus.arrived;
      case 'IN_PROGRESS':
      case 'STARTED':
        return BookingStatus.inProgress;
      case 'PAYMENT_PENDING':
      case 'AWAITING_PAYMENT':
        return BookingStatus.completed;
      case 'COMPLETED':
        return BookingStatus.completed;
      case 'PAID':
        return BookingStatus.paid;
      case 'CANCELLED':
      case 'CANCELED':
      case 'DECLINED':
        return BookingStatus.cancelled;
      default:
        return BookingStatus.draft;
    }
  }

  static List<BookingAddOn> _mapAddOns(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (item) => BookingAddOn(
            title: (item['title'] ?? item['name'] ?? 'Part').toString(),
            price: ((item['price'] ?? item['amount']) as num?)?.toDouble() ?? 0,
            quantity: (item['quantity'] as num?)?.toInt() ?? 1,
          ),
        )
        .toList();
  }

  static DateTime? _parseDate(dynamic value) =>
      value is String ? DateTime.tryParse(value) : null;
}

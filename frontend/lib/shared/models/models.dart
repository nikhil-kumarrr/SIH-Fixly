import 'package:equatable/equatable.dart';

enum UserRole { customer, worker }

enum KycReviewStatus { submitted, inReview, approved, rejected }

class AppUser extends Equatable {
  const AppUser({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
    this.email = '',
    this.avatar,
    this.eshramUan,
    this.insured = false,
    this.isVerified = false,
    this.hasWorkerProfile = false,
    this.bio,
    this.workAddress,
    this.category,
    this.categories = const [],
    this.skills = const [],
    this.hourlyRate = 0,
    this.experienceYears = 0,
    this.gender,
    this.upiId,
    this.emergencyName,
    this.emergencyPhone,
    this.emergencyRelation,
    this.homeState,
    this.homeCity,
    this.homePincode,
    this.marketingNotifications,
    this.systemNotifications,
    this.pushNotifications,
  });

  final String id;
  final String name;
  final String phone;
  final String email;
  final UserRole role;
  final String? avatar;
  final String? eshramUan;
  final bool insured;
  final bool isVerified;

  /// True when API returned a non-empty workerProfile (onboarding submitted).
  final bool hasWorkerProfile;
  final String? bio;
  final String? workAddress;
  final String? category;
  final List<String> categories;
  final List<String> skills;
  final double hourlyRate;
  final int experienceYears;
  final String? gender;
  final String? upiId;
  final String? emergencyName;
  final String? emergencyPhone;
  final String? emergencyRelation;

  /// Worker: onboarding state. Customer: unused.
  final String? homeState;

  /// Worker: onboarding district. Customer: savedAddresses.city.
  final String? homeCity;
  final String? homePincode;
  final bool? marketingNotifications;
  final bool? systemNotifications;
  final bool? pushNotifications;

  @override
  List<Object?> get props => [
    id,
    name,
    phone,
    email,
    role,
    avatar,
    eshramUan,
    insured,
    isVerified,
    hasWorkerProfile,
    bio,
    workAddress,
    category,
    categories,
    skills,
    hourlyRate,
    experienceYears,
    gender,
    upiId,
    emergencyName,
    emergencyPhone,
    emergencyRelation,
    homeState,
    homeCity,
    homePincode,
    marketingNotifications,
    systemNotifications,
    pushNotifications,
  ];
}

class WorkerProfile extends Equatable {
  const WorkerProfile({
    required this.id,
    required this.name,
    required this.skills,
    required this.rating,
    required this.jobsCompleted,
    required this.reliabilityScore,
    this.avatarUrl,
    this.insured = false,
    this.category,
    this.categories = const [],
    this.title,
    this.hourlyRate,
    this.minimumCharge,
    this.rateFormatted,
    this.distanceKm,
    this.distanceFormatted,
    this.isOnline = false,
    this.isAvailable = false,
    this.reviewCount = 0,
    this.reviews = const [],
    this.onTimeArrival,
    this.completionRate,
    this.customerFeedback,
    this.cancellationRate,
    this.serviceRadiusKm,
    this.kycStatus,
    this.isEmailVerified = false,
    this.bio,
    this.experienceYears,
    this.isVerified = true,
    this.federationId,
    this.federationName,
    this.includedTasks = const [],
    this.excludedTasks = const [],
    this.recentWorkPhotos = const [],
  });

  final String id;
  final String name;
  final List<String> skills;
  final double rating;
  final int jobsCompleted;
  final int reliabilityScore;
  final String? avatarUrl;
  final bool insured;
  final String? category;
  final List<String> categories;
  final String? title;
  final double? hourlyRate;
  final double? minimumCharge;
  final String? rateFormatted;
  final double? distanceKm;
  final String? distanceFormatted;
  final bool isOnline;
  final bool isAvailable;
  final int reviewCount;
  final List<WorkerReview> reviews;
  final double? onTimeArrival;
  final double? completionRate;
  final double? customerFeedback;
  final double? cancellationRate;
  final double? serviceRadiusKm;
  final String? kycStatus;
  final bool isEmailVerified;
  final String? bio;
  final int? experienceYears;
  final bool isVerified;
  final String? federationId;
  final String? federationName;
  final List<String> includedTasks;
  final List<String> excludedTasks;
  final List<String> recentWorkPhotos;

  @override
  List<Object?> get props => [
    id,
    name,
    skills,
    rating,
    jobsCompleted,
    reliabilityScore,
    insured,
    category,
    categories,
    title,
    hourlyRate,
    minimumCharge,
    rateFormatted,
    distanceKm,
    distanceFormatted,
    isOnline,
    isAvailable,
    reviewCount,
    reviews,
    onTimeArrival,
    completionRate,
    customerFeedback,
    cancellationRate,
    serviceRadiusKm,
    kycStatus,
    isEmailVerified,
    bio,
    experienceYears,
    isVerified,
    recentWorkPhotos,
  ];
}

class WorkerReview extends Equatable {
  const WorkerReview({
    required this.reviewerName,
    required this.rating,
    required this.comment,
    this.id,
    this.bookingId,
    this.createdAt,
    this.avatarUrl,
    this.photos = const [],
    this.badgesGiven = const [],
  });

  final String? id;
  final String? bookingId;
  final String reviewerName;
  final double rating;
  final String comment;
  final DateTime? createdAt;
  final String? avatarUrl;
  final List<String> photos;
  final List<String> badgesGiven;

  @override
  List<Object?> get props => [
        id,
        bookingId,
        reviewerName,
        rating,
        comment,
        createdAt,
        avatarUrl,
        photos,
        badgesGiven,
      ];
}


class ServiceItem extends Equatable {
  const ServiceItem({
    required this.id,
    required this.categoryId,
    required this.title,
    required this.description,
    required this.priceFrom,
    required this.rating,
    this.titleHi,
    this.descriptionHi,
    this.imageUrl,
    this.estimatedTime,
    this.whatsIncluded = const [],
    this.isActive = true,
  });

  final String id;
  final String categoryId;
  final String title;
  final String? titleHi;
  final String description;
  final String? descriptionHi;
  final double priceFrom;
  final double rating;
  final String? imageUrl;
  final String? estimatedTime;
  final List<String> whatsIncluded;
  final bool isActive;

  String titleFor(String locale) =>
      locale == 'hi' && titleHi != null ? titleHi! : title;

  String descriptionFor(String locale) =>
      locale == 'hi' && descriptionHi != null ? descriptionHi! : description;

  @override
  List<Object?> get props => [
    id,
    categoryId,
    title,
    priceFrom,
    rating,
    imageUrl,
    estimatedTime,
    whatsIncluded,
    isActive,
  ];
}

enum BookingStatus {
  draft,
  searching,
  accepted,
  arrived,
  inProgress,
  completed,
  paid,
  rating,
  cancelled,
}

class BookingAddOn extends Equatable {
  const BookingAddOn({
    required this.title,
    required this.price,
    this.quantity = 1,
  });

  final String title;
  final double price;
  final int quantity;

  @override
  List<Object?> get props => [title, price, quantity];
}

/// Worker rough estimate (parts + optional service charge on top of base).
class WorkerEstimation extends Equatable {
  const WorkerEstimation({
    this.estimatedTotal = 0,
    this.lockedBaseFee = 0,
    this.laborCost = 0,
    this.partsEstimate = 0,
    this.serviceCharge = 0,
    this.notes,
    this.submittedAt,
    this.customerAccepted = false,
  });

  final double estimatedTotal;
  final double lockedBaseFee;
  final double laborCost;
  final double partsEstimate;
  final double serviceCharge;
  final String? notes;
  final DateTime? submittedAt;
  final bool customerAccepted;

  factory WorkerEstimation.fromJson(Map<String, dynamic> json) {
    return WorkerEstimation(
      estimatedTotal: (json['estimatedTotal'] as num?)?.toDouble() ?? 0,
      lockedBaseFee: (json['lockedBaseFee'] as num?)?.toDouble() ?? 0,
      laborCost: (json['laborCost'] as num?)?.toDouble() ?? 0,
      partsEstimate: (json['partsEstimate'] as num?)?.toDouble() ?? 0,
      serviceCharge: (json['serviceCharge'] as num?)?.toDouble() ?? 0,
      notes: json['notes']?.toString(),
      submittedAt: json['submittedAt'] is String
          ? DateTime.tryParse(json['submittedAt'] as String)
          : null,
      customerAccepted: json['customerAccepted'] == true,
    );
  }

  @override
  List<Object?> get props => [
        estimatedTotal,
        lockedBaseFee,
        laborCost,
        partsEstimate,
        serviceCharge,
        notes,
        submittedAt,
        customerAccepted,
      ];
}

class BookingInvoice extends Equatable {
  const BookingInvoice({
    required this.bookingId,
    required this.serviceName,
    required this.status,
    required this.baseServiceFee,
    required this.extraPartsTotal,
    required this.platformFee,
    required this.totalAmount,
    this.paymentStatus,
    this.paymentMethod,
    this.transactionId,
    this.customerName,
    this.customerPhone,
    this.workerName,
    this.workerPhone,
    this.addOns = const [],
    this.jobStartedAt,
    this.jobCompletedAt,
    this.couponCode,
    this.couponDiscount = 0,
    this.urgentFee = 0,
  });

  final String bookingId;
  final String serviceName;
  final String status;
  final double baseServiceFee;
  final double extraPartsTotal;
  final double platformFee;
  final double totalAmount;
  final String? paymentStatus;
  final String? paymentMethod;
  final String? transactionId;
  final String? customerName;
  final String? customerPhone;
  final String? workerName;
  final String? workerPhone;
  final List<BookingAddOn> addOns;
  final DateTime? jobStartedAt;
  final DateTime? jobCompletedAt;
  final String? couponCode;
  final double couponDiscount;
  final double urgentFee;

  /// What customer pays (authoritative invoice total).
  double get customerTotal =>
      totalAmount > 0
          ? totalAmount
          : (baseServiceFee +
                  extraPartsTotal +
                  platformFee +
                  urgentFee -
                  couponDiscount)
              .clamp(0.0, double.infinity);

  /// Worker take-home: labor + parts + urgent. Coupon is Fixly subsidy — not deducted.
  double get workerPayout {
    return (baseServiceFee + extraPartsTotal + urgentFee)
        .clamp(0.0, double.infinity);
  }

  factory BookingInvoice.fromJson(Map<String, dynamic> json) {
    return BookingInvoice(
      bookingId: json['bookingId']?.toString() ?? '',
      serviceName: json['serviceName']?.toString() ?? 'Service',
      status: json['status']?.toString() ?? 'PENDING',
      baseServiceFee: (json['baseServiceFee'] as num?)?.toDouble() ?? 0,
      extraPartsTotal: (json['extraPartsTotal'] as num?)?.toDouble() ?? 0,
      platformFee: (json['platformFee'] as num?)?.toDouble() ?? 0,
      totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0,
      paymentStatus: json['paymentStatus']?.toString(),
      paymentMethod: json['paymentMethod']?.toString(),
      transactionId: json['transactionId']?.toString(),
      customerName: json['customerName']?.toString(),
      customerPhone: json['customerPhone']?.toString(),
      workerName: json['workerName']?.toString(),
      workerPhone: json['workerPhone']?.toString(),
      addOns: (json['addOns'] as List?)
              ?.map((e) => BookingAddOn(
                    title: e['title']?.toString() ?? '',
                    price: (e['price'] as num?)?.toDouble() ?? 0,
                    quantity: (e['quantity'] as num?)?.toInt() ?? 1,
                  ))
              .toList() ??
          const [],
      jobStartedAt: json['jobStartedAt'] != null ? DateTime.tryParse(json['jobStartedAt'].toString()) : null,
      jobCompletedAt: json['jobCompletedAt'] != null ? DateTime.tryParse(json['jobCompletedAt'].toString()) : null,
      couponCode: json['couponCode']?.toString(),
      couponDiscount: (json['couponDiscount'] as num?)?.toDouble() ?? 0,
      urgentFee: (json['urgentFee'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  List<Object?> get props => [
        bookingId,
        totalAmount,
        paymentStatus,
        addOns,
        couponCode,
        couponDiscount,
      ];
}

class Booking extends Equatable {
  const Booking({
    required this.id,
    required this.serviceId,
    required this.serviceTitle,
    required this.status,
    required this.estimatedPrice,
    this.workerId,
    this.workerName,
    this.address,
    this.scheduledAt,
    this.addOns = const [],
    this.baseServiceFee,
    this.platformFee,
    this.extraPartsTotal,
    this.displayId,
    this.serviceCategory,
    this.serviceImage,
    this.estimatedTime,
    this.whatsIncluded = const [],
    this.problemDescription,
    this.problemPhotos = const [],
    this.problemVideos = const [],
    this.paymentMethod,
    this.paymentStatus,
    this.transactionId,
    this.arrivalOtp,
    this.createdAt,
    this.jobStartedAt,
    this.jobCompletedAt,
    this.isReviewed = false,
    this.workerReviewed = false,
    this.workerAvatar,
    this.workerRating,
    this.workerJobsCompleted,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.customerAvatar,
    this.customerLat,
    this.customerLng,
    this.rawStatus,
    this.bookingType,
    this.isEmergency = false,
    this.urgentFee,
    this.timeSlot,
    this.totalAmount,
    this.invoice,
    this.workerEstimation,
    this.workerNavigationStartedAt,
    this.declineReason,
    this.declinedBy,
    this.cancelReason,
    this.cancelledBy,
    this.cancelledAt,
  });

  final String id;
  final String serviceId;
  final String serviceTitle;
  final BookingStatus status;
  final double estimatedPrice;
  final String? workerId;
  final String? workerName;
  final String? address;
  final DateTime? scheduledAt;
  final List<BookingAddOn> addOns;
  final double? baseServiceFee;
  final double? platformFee;
  final double? extraPartsTotal;
  final String? displayId;
  final String? serviceCategory;
  final String? serviceImage;
  final String? estimatedTime;
  final List<String> whatsIncluded;
  final String? problemDescription;
  final List<String> problemPhotos;
  final List<String> problemVideos;
  final String? paymentMethod;
  final String? paymentStatus;
  final String? transactionId;
  final String? arrivalOtp;
  final DateTime? createdAt;
  final DateTime? jobStartedAt;
  final DateTime? jobCompletedAt;
  final bool isReviewed;
  final bool workerReviewed;
  final String? workerAvatar;
  final double? workerRating;
  final int? workerJobsCompleted;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final String? customerAvatar;
  final double? customerLat;
  final double? customerLng;
  final String? rawStatus;
  final String? bookingType;
  final bool isEmergency;
  final double? urgentFee;
  final String? timeSlot;
  final double? totalAmount;
  final BookingInvoice? invoice;
  final WorkerEstimation? workerEstimation;
  final DateTime? workerNavigationStartedAt;
  final String? declineReason;
  final String? declinedBy;
  final String? cancelReason;
  final String? cancelledBy;
  final DateTime? cancelledAt;

  bool get workerHasStartedNavigation => workerNavigationStartedAt != null;

  bool get isCancelled =>
      status == BookingStatus.cancelled ||
      (rawStatus ?? '').toUpperCase() == 'CANCELLED';

  bool get isPaid =>
      status == BookingStatus.paid ||
      (paymentStatus ?? '').toUpperCase() == 'PAID' ||
      (rawStatus ?? '').toUpperCase() == 'PAID' ||
      (rawStatus ?? '').toUpperCase() == 'PAYMENT_PAID';

  /// Work done (or mapped completed) but customer still owes payment.
  bool get isAwaitingPayment {
    if (isCancelled || isPaid) return false;
    final raw = (rawStatus ?? '').toUpperCase();
    final pay = (paymentStatus ?? '').toUpperCase();
    if (raw == 'PAYMENT_PENDING' || raw == 'AWAITING_PAYMENT') return true;
    return status == BookingStatus.completed &&
        pay != 'PAID' &&
        raw != 'COMPLETED';
  }

  /// Job finished enough that review is expected for this role.
  bool get isJobFinishedForReview {
    if (isCancelled) return false;
    final raw = (rawStatus ?? '').toUpperCase();
    return isPaid ||
        isAwaitingPayment ||
        status == BookingStatus.completed ||
        status == BookingStatus.paid ||
        status == BookingStatus.rating ||
        raw == 'COMPLETED' ||
        raw == 'PAYMENT_PENDING' ||
        raw == 'AWAITING_PAYMENT' ||
        raw == 'PAID';
  }

  /// Customer rates after pay; worker rates after job complete.
  bool needsReview({required bool isWorker}) {
    if (!isJobFinishedForReview) return false;
    if (isWorker) return !workerReviewed;
    return isPaid && !isReviewed;
  }

  bool get cancelledByWorker {
    if (!isCancelled) return false;
    final by = (cancelledBy ?? declinedBy ?? '').trim();
    final worker = (workerId ?? '').trim();
    if (by.isNotEmpty && worker.isNotEmpty && by == worker) return true;
    return declineReason != null && declineReason!.trim().isNotEmpty;
  }

  double get totalPrice {
    // 1. Authoritative backend values: DO NOT recalculate or add extra parts on top!
    if (totalAmount != null && totalAmount! > 0) {
      return totalAmount!;
    }
    if (invoice != null && invoice!.totalAmount > 0) {
      return invoice!.totalAmount;
    }

    // 2. Pre-invoice initial estimate calculation:
    final extra = (extraPartsTotal != null && extraPartsTotal! > 0)
        ? extraPartsTotal!
        : addOns.fold<double>(0.0, (sum, a) => sum + (a.price * a.quantity));
    final platform = platformFee ?? 0.0;
    final urgent = urgentFee ?? 0.0;

    // Only add extra parts if baseServiceFee is explicitly specified.
    // If baseServiceFee is null, estimatedPrice already reflects the full total — NEVER add extra on top!
    if (baseServiceFee != null && baseServiceFee! > 0) {
      return baseServiceFee! + extra + platform + urgent;
    }

    return estimatedPrice + urgent;
  }

  /// Worker payout only (excludes platform fee; coupon is Fixly subsidy).
  double get workerPayout {
    if (invoice != null) return invoice!.workerPayout;
    final base = baseServiceFee ?? 0.0;
    final extra = extraPartsTotal ??
        addOns.fold<double>(0.0, (sum, a) => sum + (a.price * a.quantity));
    final urgent = urgentFee ?? 0.0;
    if (base > 0 || extra > 0 || urgent > 0) {
      return (base + extra + urgent).clamp(0.0, double.infinity);
    }
    final total = totalAmount ?? totalPrice;
    final platform = platformFee ?? 0.0;
    return (total - platform).clamp(0.0, double.infinity);
  }

  bool get isSosBooking =>
      isEmergency ||
      (bookingType ?? '').toUpperCase() == 'EMERGENCY_SOS' ||
      (bookingType ?? '').toUpperCase() == 'SOS' ||
      (bookingType ?? '').toUpperCase() == 'EMERGENCY';

  bool get isScheduledBooking =>
      (bookingType ?? '').toUpperCase() == 'SCHEDULED' || scheduledAt != null;

  String get jobTypeLabel {
    if (isSosBooking) return 'EMERGENCY SOS';
    if (isScheduledBooking) return 'SCHEDULED';
    return 'STANDARD';
  }

  Booking copyWith({
    BookingStatus? status,
    String? workerId,
    String? workerName,
    String? workerAvatar,
    double? workerRating,
    int? workerJobsCompleted,
    double? estimatedPrice,
    List<BookingAddOn>? addOns,
    double? baseServiceFee,
    double? platformFee,
    double? extraPartsTotal,
    String? rawStatus,
    String? paymentStatus,
    double? totalAmount,
    BookingInvoice? invoice,
    WorkerEstimation? workerEstimation,
    DateTime? workerNavigationStartedAt,
  }) {
    return Booking(
      id: id,
      serviceId: serviceId,
      serviceTitle: serviceTitle,
      status: status ?? this.status,
      estimatedPrice: estimatedPrice ?? this.estimatedPrice,
      workerId: workerId ?? this.workerId,
      workerName: workerName ?? this.workerName,
      address: address,
      scheduledAt: scheduledAt,
      addOns: addOns ?? this.addOns,
      baseServiceFee: baseServiceFee ?? this.baseServiceFee,
      platformFee: platformFee ?? this.platformFee,
      extraPartsTotal: extraPartsTotal ?? this.extraPartsTotal,
      displayId: displayId,
      serviceCategory: serviceCategory,
      serviceImage: serviceImage,
      estimatedTime: estimatedTime,
      whatsIncluded: whatsIncluded,
      problemDescription: problemDescription,
      problemPhotos: problemPhotos,
      problemVideos: problemVideos,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      transactionId: transactionId,
      arrivalOtp: arrivalOtp,
      createdAt: createdAt,
      jobStartedAt: jobStartedAt,
      jobCompletedAt: jobCompletedAt,
      isReviewed: isReviewed,
      workerReviewed: workerReviewed,
      workerAvatar: workerAvatar ?? this.workerAvatar,
      workerRating: workerRating ?? this.workerRating,
      workerJobsCompleted: workerJobsCompleted ?? this.workerJobsCompleted,
      customerId: customerId,
      customerName: customerName,
      customerPhone: customerPhone,
      customerAvatar: customerAvatar,
      customerLat: customerLat,
      customerLng: customerLng,
      rawStatus: rawStatus ?? this.rawStatus,
      bookingType: bookingType,
      isEmergency: isEmergency,
      urgentFee: urgentFee,
      timeSlot: timeSlot,
      totalAmount: totalAmount ?? this.totalAmount,
      invoice: invoice ?? this.invoice,
      workerEstimation: workerEstimation ?? this.workerEstimation,
      workerNavigationStartedAt:
          workerNavigationStartedAt ?? this.workerNavigationStartedAt,
      declineReason: declineReason,
      declinedBy: declinedBy,
      cancelReason: cancelReason,
      cancelledBy: cancelledBy,
      cancelledAt: cancelledAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    serviceId,
    serviceTitle,
    status,
    estimatedPrice,
    workerId,
    addOns,
    displayId,
    problemDescription,
    paymentStatus,
    createdAt,
    customerName,
    totalAmount,
    invoice,
    workerNavigationStartedAt,
    declineReason,
    declinedBy,
    cancelReason,
    cancelledBy,
    cancelledAt,
  ];
}

enum JobStatus { incoming, active, completed }

class WorkerJob extends Equatable {
  const WorkerJob({
    required this.id,
    required this.title,
    required this.customerName,
    required this.address,
    required this.pay,
    required this.status,
    required this.distanceKm,
    this.customerLat,
    this.customerLng,
    this.customerPhone,
    this.customerAvatar,
    this.problemDescription,
    this.problemPhotos = const [],
    this.problemVideos = const [],
    this.serviceCategory,
    this.serviceImage,
    this.arrivalOtp,
    this.baseServiceFee,
    this.platformFee,
    this.extraPartsTotal,
    this.addOns = const [],
    this.jobStartedAt,
    this.jobCompletedAt,
    this.rawStatus,
    this.invoice,
    this.scheduledAt,
    this.bookingType,
    this.isEmergency = false,
  });

  final String id;
  final String title;
  final String customerName;
  final String address;
  final double pay;
  final JobStatus status;
  final double distanceKm;
  final double? customerLat;
  final double? customerLng;
  final String? customerPhone;
  final String? customerAvatar;
  final String? problemDescription;
  final List<String> problemPhotos;
  final List<String> problemVideos;
  final String? serviceCategory;
  final String? serviceImage;
  final String? arrivalOtp;
  final double? baseServiceFee;
  final double? platformFee;
  final double? extraPartsTotal;
  final List<BookingAddOn> addOns;
  final DateTime? jobStartedAt;
  final DateTime? jobCompletedAt;

  /// Raw backend status string e.g. 'APPROVED', 'ARRIVED', 'IN_PROGRESS'
  final String? rawStatus;
  final BookingInvoice? invoice;

  final DateTime? scheduledAt;
  final String? bookingType;
  final bool isEmergency;

  String get bookingId => id;

  bool get isSosBooking =>
      isEmergency ||
      (bookingType ?? '').toUpperCase() == 'EMERGENCY_SOS' ||
      (bookingType ?? '').toUpperCase() == 'SOS' ||
      (bookingType ?? '').toUpperCase() == 'EMERGENCY';

  bool get isScheduledBooking =>
      (bookingType ?? '').toUpperCase() == 'SCHEDULED' || scheduledAt != null;

  String get jobTypeLabel {
    if (isSosBooking) return 'EMERGENCY SOS';
    if (isScheduledBooking) return 'SCHEDULED';
    return 'STANDARD';
  }

  /// Worker take-home — never includes platform fee.
  double get workerPayout {
    if (invoice != null) return invoice!.workerPayout;
    final platform = platformFee ?? 0.0;
    final base = baseServiceFee ?? 0.0;
    final extras = extraPartsTotal ?? 0.0;
    if (base > 0 || extras > 0) {
      return (base + extras).clamp(0.0, double.infinity);
    }
    return (pay - platform).clamp(0.0, double.infinity);
  }

  WorkerJob copyWith({
    String? id,
    String? title,
    String? customerName,
    String? address,
    double? pay,
    JobStatus? status,
    double? distanceKm,
    double? customerLat,
    double? customerLng,
    String? customerPhone,
    String? customerAvatar,
    String? problemDescription,
    List<String>? problemPhotos,
    String? serviceCategory,
    String? serviceImage,
    String? arrivalOtp,
    double? baseServiceFee,
    double? platformFee,
    double? extraPartsTotal,
    List<BookingAddOn>? addOns,
    DateTime? jobStartedAt,
    DateTime? jobCompletedAt,
    String? rawStatus,
    BookingInvoice? invoice,
    DateTime? scheduledAt,
    String? bookingType,
  }) {
    return WorkerJob(
      id: id ?? this.id,
      title: title ?? this.title,
      customerName: customerName ?? this.customerName,
      address: address ?? this.address,
      pay: pay ?? this.pay,
      status: status ?? this.status,
      distanceKm: distanceKm ?? this.distanceKm,
      customerLat: customerLat ?? this.customerLat,
      customerLng: customerLng ?? this.customerLng,
      customerPhone: customerPhone ?? this.customerPhone,
      customerAvatar: customerAvatar ?? this.customerAvatar,
      problemDescription: problemDescription ?? this.problemDescription,
      problemPhotos: problemPhotos ?? this.problemPhotos,
      serviceCategory: serviceCategory ?? this.serviceCategory,
      serviceImage: serviceImage ?? this.serviceImage,
      arrivalOtp: arrivalOtp ?? this.arrivalOtp,
      baseServiceFee: baseServiceFee ?? this.baseServiceFee,
      platformFee: platformFee ?? this.platformFee,
      extraPartsTotal: extraPartsTotal ?? this.extraPartsTotal,
      addOns: addOns ?? this.addOns,
      jobStartedAt: jobStartedAt ?? this.jobStartedAt,
      jobCompletedAt: jobCompletedAt ?? this.jobCompletedAt,
      rawStatus: rawStatus ?? this.rawStatus,
      invoice: invoice ?? this.invoice,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      bookingType: bookingType ?? this.bookingType,
    );
  }

  @override
  List<Object?> get props => [
    id,
    title,
    customerName,
    address,
    pay,
    status,
    distanceKm,
    customerLat,
    customerLng,
    customerPhone,
    customerAvatar,
    problemDescription,
    problemPhotos,
    serviceCategory,
    serviceImage,
    arrivalOtp,
    baseServiceFee,
    platformFee,
    extraPartsTotal,
    addOns,
    jobStartedAt,
    jobCompletedAt,
    rawStatus,
    invoice,
    scheduledAt,
    bookingType,
  ];
}

class WalletTransaction extends Equatable {
  const WalletTransaction({
    required this.id,
    required this.label,
    required this.amount,
    required this.isCredit,
    this.date,
    this.transactionId,
    this.status,
    this.type,
  });

  final String id;
  final String label;
  final double amount;
  final bool isCredit;
  final DateTime? date;
  final String? transactionId;
  final String? status;
  final String? type;

  @override
  List<Object?> get props => [id, label, amount, isCredit, date, transactionId, status, type];
}

class NotificationItem extends Equatable {
  const NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.time,
    this.read = false,
    this.category,
    this.eventType,
    this.entityType,
    this.entityId,
    this.bookingId,
    this.action,
    this.data = const {},
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    final rawDate = json['createdAt'] ?? json['time'];
    return NotificationItem(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: (json['body'] ?? json['message'])?.toString() ?? '',
      time: DateTime.tryParse(rawDate?.toString() ?? '') ?? DateTime.now(),
      read: json['isRead'] == true || json['read'] == true,
      category: json['category']?.toString(),
      eventType: json['eventType']?.toString(),
      entityType: json['entityType']?.toString(),
      entityId: json['entityId']?.toString(),
      bookingId: json['bookingId']?.toString() ??
          (json['data'] is Map ? json['data']['bookingId']?.toString() : null) ??
          (json['entityType'] == 'booking' ? json['entityId']?.toString() : null),
      action:
          (json['action'] ??
                  (json['data'] is Map ? json['data']['action'] : null))
              ?.toString(),
      data: json['data'] is Map
          ? Map<String, dynamic>.from(json['data'] as Map)
          : const {},
    );
  }

  final String id;
  final String title;
  final String body;
  final DateTime time;
  final bool read;
  final String? category;
  final String? eventType;
  final String? entityType;
  final String? entityId;
  final String? bookingId;
  final String? action;
  final Map<String, dynamic> data;

  @override
  List<Object?> get props => [
    id,
    title,
    body,
    time,
    read,
    category,
    eventType,
    entityType,
    entityId,
    bookingId,
    action,
    data,
  ];
}

enum WorkerGender { male, female, other }

extension WorkerGenderX on WorkerGender {
  String get label => switch (this) {
    WorkerGender.male => 'Male',
    WorkerGender.female => 'Female',
    WorkerGender.other => 'Other',
  };
}

class OnboardingFormData extends Equatable {
  static const _unset = Object();

  const OnboardingFormData({
    this.fullName = '',
    this.phone = '',
    this.email = '',
    this.dateOfBirth,
    this.gender,
    this.state = '',
    this.district = '',
    this.aadhaar = '',
    this.pan = '',
    this.aadhaarFrontPath,
    this.aadhaarBackPath,
    this.panFrontPath,
    this.panBackPath,
    this.skills = const [],
    this.categoryRates = const {},
    this.experienceYears = 0,
    this.bio = '',
    this.serviceRadiusKm = 5,
    this.hasEshram = false,
    this.eshramUan = '',
    this.payoutMethod = PayoutMethod.bank,
    this.accountHolderName = '',
    this.bankAccount = '',
    this.ifscCode = '',
    this.upiId = '',
    this.bankVerified = false,
    this.upiVerified = false,
    this.certificateUploaded = false,
    this.certificatePath,
    this.certificateFileName,
    this.selfieVerified = false,
    this.selfieImageUrl,
    this.federationId,
    this.federationName,
    this.includedTasks = const {},
    this.excludedTasks = const {},
    this.societyId,
    this.societyMemberId,
    this.recentWorkPhotoPaths = const [],
  });

  final String fullName;
  final String phone;
  final String email;
  final DateTime? dateOfBirth;
  final WorkerGender? gender;
  final String state;
  final String district;
  final String aadhaar;
  final String pan;
  final String? aadhaarFrontPath;
  final String? aadhaarBackPath;
  final String? panFrontPath;
  final String? panBackPath;
  final List<String> skills;

  /// Hourly rate (₹) per skill/category id.
  final Map<String, int> categoryRates;
  final int experienceYears;
  final String bio;
  final double serviceRadiusKm;
  final bool hasEshram;
  final String eshramUan;
  final PayoutMethod payoutMethod;
  final String accountHolderName;
  final String bankAccount;
  final String ifscCode;
  final String upiId;
  final bool bankVerified;
  final bool upiVerified;
  final bool certificateUploaded;
  final String? certificatePath;
  final String? certificateFileName;
  final bool selfieVerified;
  final String? selfieImageUrl;
  final String? federationId;
  final String? federationName;
  final Map<String, List<String>> includedTasks;
  final Map<String, List<String>> excludedTasks;
  final String? societyId;
  final String? societyMemberId;
  final List<String> recentWorkPhotoPaths;

  bool get hasAadhaarPhotos =>
      (aadhaarFrontPath?.isNotEmpty ?? false) &&
      (aadhaarBackPath?.isNotEmpty ?? false);

  bool get hasPanPhotos =>
      (panFrontPath?.isNotEmpty ?? false) && (panBackPath?.isNotEmpty ?? false);

  /// Primary rate for API `rate` / `hourlyRate` — first selected skill with a rate.
  int get primaryRate {
    for (final skill in skills) {
      final rate = categoryRates[skill];
      if (rate != null && rate > 0) return rate;
    }
    return 0;
  }

  /// API-shaped rows: `{ category, rate }`.
  List<Map<String, dynamic>> get categoryRatesPayload => skills
      .where((id) => (categoryRates[id] ?? 0) > 0)
      .map((id) => {'category': id, 'rate': categoryRates[id]})
      .toList();

  OnboardingFormData copyWith({
    String? fullName,
    String? phone,
    String? email,
    Object? dateOfBirth = _unset,
    Object? gender = _unset,
    String? state,
    String? district,
    String? aadhaar,
    String? pan,
    Object? aadhaarFrontPath = _unset,
    Object? aadhaarBackPath = _unset,
    Object? panFrontPath = _unset,
    Object? panBackPath = _unset,
    List<String>? skills,
    Map<String, int>? categoryRates,
    int? experienceYears,
    String? bio,
    double? serviceRadiusKm,
    bool? hasEshram,
    String? eshramUan,
    PayoutMethod? payoutMethod,
    String? accountHolderName,
    String? bankAccount,
    String? ifscCode,
    String? upiId,
    bool? bankVerified,
    bool? upiVerified,
    bool? certificateUploaded,
    Object? certificatePath = _unset,
    Object? certificateFileName = _unset,
    bool? selfieVerified,
    Object? selfieImageUrl = _unset,
    String? federationId,
    String? federationName,
    Map<String, List<String>>? includedTasks,
    Map<String, List<String>>? excludedTasks,
    String? societyId,
    String? societyMemberId,
    List<String>? recentWorkPhotoPaths,
  }) {
    return OnboardingFormData(
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      dateOfBirth: identical(dateOfBirth, _unset)
          ? this.dateOfBirth
          : dateOfBirth as DateTime?,
      gender: identical(gender, _unset) ? this.gender : gender as WorkerGender?,
      state: state ?? this.state,
      district: district ?? this.district,
      aadhaar: aadhaar ?? this.aadhaar,
      pan: pan ?? this.pan,
      aadhaarFrontPath: identical(aadhaarFrontPath, _unset)
          ? this.aadhaarFrontPath
          : aadhaarFrontPath as String?,
      aadhaarBackPath: identical(aadhaarBackPath, _unset)
          ? this.aadhaarBackPath
          : aadhaarBackPath as String?,
      panFrontPath: identical(panFrontPath, _unset)
          ? this.panFrontPath
          : panFrontPath as String?,
      panBackPath: identical(panBackPath, _unset)
          ? this.panBackPath
          : panBackPath as String?,
      skills: skills ?? this.skills,
      categoryRates: categoryRates ?? this.categoryRates,
      experienceYears: experienceYears ?? this.experienceYears,
      bio: bio ?? this.bio,
      serviceRadiusKm: serviceRadiusKm ?? this.serviceRadiusKm,
      hasEshram: hasEshram ?? this.hasEshram,
      eshramUan: eshramUan ?? this.eshramUan,
      payoutMethod: payoutMethod ?? this.payoutMethod,
      accountHolderName: accountHolderName ?? this.accountHolderName,
      bankAccount: bankAccount ?? this.bankAccount,
      ifscCode: ifscCode ?? this.ifscCode,
      upiId: upiId ?? this.upiId,
      bankVerified: bankVerified ?? this.bankVerified,
      upiVerified: upiVerified ?? this.upiVerified,
      certificateUploaded: certificateUploaded ?? this.certificateUploaded,
      certificatePath: identical(certificatePath, _unset)
          ? this.certificatePath
          : certificatePath as String?,
      certificateFileName: identical(certificateFileName, _unset)
          ? this.certificateFileName
          : certificateFileName as String?,
      selfieVerified: selfieVerified ?? this.selfieVerified,
      selfieImageUrl: identical(selfieImageUrl, _unset)
          ? this.selfieImageUrl
          : selfieImageUrl as String?,
      federationId: federationId ?? this.federationId,
      federationName: federationName ?? this.federationName,
      includedTasks: includedTasks ?? this.includedTasks,
      excludedTasks: excludedTasks ?? this.excludedTasks,
      societyId: societyId ?? this.societyId,
      societyMemberId: societyMemberId ?? this.societyMemberId,
      recentWorkPhotoPaths:
          recentWorkPhotoPaths ?? this.recentWorkPhotoPaths,
    );
  }

  @override
  List<Object?> get props => [
    fullName,
    phone,
    email,
    dateOfBirth,
    gender,
    state,
    district,
    aadhaar,
    pan,
    aadhaarFrontPath,
    aadhaarBackPath,
    panFrontPath,
    panBackPath,
    skills,
    categoryRates,
    experienceYears,
    bio,
    serviceRadiusKm,
    hasEshram,
    eshramUan,
    payoutMethod,
    accountHolderName,
    bankAccount,
    ifscCode,
    upiId,
    bankVerified,
    upiVerified,
    certificateUploaded,
    certificatePath,
    certificateFileName,
    selfieVerified,
    selfieImageUrl,
    federationId,
    federationName,
    includedTasks,
    excludedTasks,
    societyId,
    societyMemberId,
    recentWorkPhotoPaths,
  ];
}

enum PayoutMethod { bank, upi }

class CouponBanner extends Equatable {
  const CouponBanner({
    required this.id,
    required this.title,
    required this.code,
    required this.discount,
    this.description = '',
    this.imageUrl = '',
    this.gradientColors = const ['#1E3A8A', '#3B82F6'],
    this.category = 'all',
    this.targetUserRole = 'all',
    this.minOrderValue = 0,
    this.maxDiscount = 500,
    this.validUntil,
    this.isActive = true,
  });

  final String id;
  final String title;
  final String code;
  final String discount;
  final String description;
  final String imageUrl;
  final List<String> gradientColors;
  final String category;
  final String targetUserRole;
  final double minOrderValue;
  final double maxDiscount;
  final DateTime? validUntil;
  final bool isActive;

  factory CouponBanner.fromJson(Map<String, dynamic> json) {
    return CouponBanner(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      discount: json['discount']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString() ?? '',
      gradientColors: (json['gradient'] as List?)?.map((e) => e.toString()).toList() ??
          const ['#1E3A8A', '#3B82F6'],
      category: json['category']?.toString() ?? 'all',
      targetUserRole: json['targetUserRole']?.toString() ?? 'all',
      minOrderValue: (json['minOrderValue'] as num?)?.toDouble() ?? 0,
      maxDiscount: (json['maxDiscount'] as num?)?.toDouble() ?? 500,
      validUntil: json['validUntil'] != null
          ? DateTime.tryParse(json['validUntil'].toString())
          : null,
      isActive: json['isActive'] != false,
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        code,
        discount,
        description,
        imageUrl,
        gradientColors,
        category,
        validUntil,
        isActive,
      ];
}

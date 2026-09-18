class AiAgentResponse {
  final bool success;
  final String reply;
  final String action;
  final Map<String, dynamic> state;
  final AiAgentData? data;
  final List<dynamic> workers;
  final Map<String, dynamic>? estimate;
  final Map<String, dynamic>? policy;
  final Map<String, dynamic>? booking;
  final List<dynamic> bookings;
  final List<String> suggestedReplies;
  /// Raw app action maps — parse with [parseAppActions] in UI.
  final List<Map<String, dynamic>> appActions;
  /// Preferred spoken line from backend (cleaner than markdown reply).
  final String? speakHint;

  AiAgentResponse({
    required this.success,
    required this.reply,
    required this.action,
    this.state = const {},
    this.data,
    this.workers = const [],
    this.estimate,
    this.policy,
    this.booking,
    this.bookings = const [],
    this.suggestedReplies = const [],
    this.appActions = const [],
    this.speakHint,
  });

  factory AiAgentResponse.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : null;

    final rawWorkers = (rawData != null && rawData['workers'] is List)
        ? rawData['workers'] as List<dynamic>
        : (json['workers'] is List ? json['workers'] as List<dynamic> : const []);

    final rawEstimate = (rawData != null && rawData['estimate'] is Map<String, dynamic>)
        ? rawData['estimate'] as Map<String, dynamic>
        : (json['estimate'] is Map<String, dynamic> ? json['estimate'] as Map<String, dynamic> : null);

    final rawPolicy = (rawData != null && rawData['policy'] is Map<String, dynamic>)
        ? rawData['policy'] as Map<String, dynamic>
        : (json['policy'] is Map<String, dynamic> ? json['policy'] as Map<String, dynamic> : null);

    final rawBooking = (rawData != null && rawData['booking'] is Map<String, dynamic>)
        ? rawData['booking'] as Map<String, dynamic>
        : (json['booking'] is Map<String, dynamic> ? json['booking'] as Map<String, dynamic> : null);

    final rawBookings = (rawData != null && rawData['bookings'] is List)
        ? rawData['bookings'] as List<dynamic>
        : (json['bookings'] is List ? json['bookings'] as List<dynamic> : const []);

    final parsedData = rawData != null
        ? AiAgentData.fromJson(rawData)
        : AiAgentData.fromJson(json);

    final rawSuggestions = json['suggestedReplies'];
    final suggestions = rawSuggestions is List
        ? rawSuggestions.map((e) => e.toString()).toList()
        : const <String>[];

    final rawApp = json['appActions'];
    final appActions = rawApp is List
        ? rawApp
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : const <Map<String, dynamic>>[];

    final hint = json['speakHint']?.toString().trim();

    return AiAgentResponse(
      success: json['success'] ?? false,
      reply: json['reply']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      state: (json['state'] as Map<String, dynamic>?) ?? const {},
      data: parsedData,
      workers: rawWorkers,
      estimate: rawEstimate,
      policy: rawPolicy,
      booking: rawBooking,
      bookings: rawBookings,
      suggestedReplies: suggestions,
      appActions: appActions,
      speakHint: (hint != null && hint.isNotEmpty) ? hint : null,
    );
  }

  // Typed convenience getters
  List<AgentWorkerItem> get workerItems => data?.workers ?? const [];
  AgentEstimate? get estimateModel => data?.estimate;
  AgentPolicy? get policyModel => data?.policy;
}

class AiAgentData {
  final String? step;
  final String? category;
  final List<AgentWorkerItem>? workers;
  final AgentEstimate? estimate;
  final AgentPolicy? policy;
  final Map<String, dynamic>? booking;
  final List<dynamic>? bookings;

  AiAgentData({
    this.step,
    this.category,
    this.workers,
    this.estimate,
    this.policy,
    this.booking,
    this.bookings,
  });

  factory AiAgentData.fromJson(Map<String, dynamic> json) {
    return AiAgentData(
      step: json['step']?.toString(),
      category: json['category']?.toString(),
      workers: json['workers'] != null && json['workers'] is List
          ? (json['workers'] as List)
              .whereType<Map<String, dynamic>>()
              .map((w) => AgentWorkerItem.fromJson(w))
              .toList()
          : null,
      estimate: json['estimate'] != null && json['estimate'] is Map<String, dynamic>
          ? AgentEstimate.fromJson(json['estimate'] as Map<String, dynamic>)
          : null,
      policy: json['policy'] != null && json['policy'] is Map<String, dynamic>
          ? AgentPolicy.fromJson(json['policy'] as Map<String, dynamic>)
          : null,
      booking: json['booking'] as Map<String, dynamic>?,
      bookings: json['bookings'] as List<dynamic>?,
    );
  }
}

class AgentWorkerItem {
  final String id;
  final String name;
  final String? phone;
  final String? avatar;
  final double rating;
  final double hourlyRate;
  final int experienceYears;
  final double distanceKm;

  AgentWorkerItem({
    required this.id,
    required this.name,
    this.phone,
    this.avatar,
    required this.rating,
    required this.hourlyRate,
    required this.experienceYears,
    required this.distanceKm,
  });

  factory AgentWorkerItem.fromJson(Map<String, dynamic> json) {
    return AgentWorkerItem(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Cooperative Worker',
      phone: json['phone']?.toString(),
      avatar: json['avatar']?.toString(),
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      hourlyRate: (json['hourlyRate'] as num?)?.toDouble() ?? 200.0,
      experienceYears: (json['experienceYears'] as num?)?.toInt() ?? 0,
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 1.0,
    );
  }

  Map<String, dynamic> toJson() => {
        '_id': id,
        'name': name,
        'phone': phone,
        'avatar': avatar,
        'rating': rating,
        'hourlyRate': hourlyRate,
        'experienceYears': experienceYears,
        'distanceKm': distanceKm,
      };
}

class AgentEstimate {
  final double baseServiceFee;
  final double urgentFee;
  final double platformFee;
  final double welfareContribution;
  final double totalAmount;
  final String currency;

  AgentEstimate({
    required this.baseServiceFee,
    required this.urgentFee,
    required this.platformFee,
    required this.welfareContribution,
    required this.totalAmount,
    required this.currency,
  });

  factory AgentEstimate.fromJson(Map<String, dynamic> json) {
    return AgentEstimate(
      baseServiceFee: (json['baseServiceFee'] as num?)?.toDouble() ?? 0.0,
      urgentFee: (json['urgentFee'] as num?)?.toDouble() ?? 0.0,
      platformFee: (json['platformFee'] as num?)?.toDouble() ?? 0.0,
      welfareContribution:
          (json['welfareContribution'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency']?.toString() ?? 'INR',
    );
  }

  Map<String, dynamic> toJson() => {
        'baseServiceFee': baseServiceFee,
        'urgentFee': urgentFee,
        'platformFee': platformFee,
        'welfareContribution': welfareContribution,
        'totalAmount': totalAmount,
        'currency': currency,
      };
}

class AgentPolicy {
  final String title;
  final String fairWageNotice;
  final String welfareFundNotice;
  final String platformCommission;

  AgentPolicy({
    required this.title,
    required this.fairWageNotice,
    required this.welfareFundNotice,
    required this.platformCommission,
  });

  factory AgentPolicy.fromJson(Map<String, dynamic> json) {
    return AgentPolicy(
      title: json['title']?.toString() ?? '',
      fairWageNotice: json['fairWageNotice']?.toString() ?? '',
      welfareFundNotice: json['welfareFundNotice']?.toString() ?? '',
      platformCommission: json['platformCommission']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'fairWageNotice': fairWageNotice,
        'welfareFundNotice': welfareFundNotice,
        'platformCommission': platformCommission,
      };
}

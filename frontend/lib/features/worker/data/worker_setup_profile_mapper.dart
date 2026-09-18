import 'dart:convert';
import 'dart:io';

import '../../../core/constants/app_constants.dart';
import '../../../core/location/app_location.dart';
import '../../../shared/models/models.dart';

/// Builds flat PUT `/api/workers/setup-profile` body (base64 data URIs for media).
abstract final class WorkerSetupProfileMapper {
  static final _categoryIds = ServiceCategories.all.map((c) => c.id).toSet();

  static Future<Map<String, dynamic>> toBody(OnboardingFormData data) async {
    final categories = data.skills
        .where(_categoryIds.contains)
        .toList(growable: false);
    final primaryCategory = categories.isNotEmpty
        ? categories.first
        : (data.skills.isNotEmpty ? data.skills.first : null);
    final loc = AppLocation.instance;
    final dob = data.dateOfBirth;
    final dobStr = dob == null
        ? null
        : '${dob.year.toString().padLeft(4, '0')}-'
              '${dob.month.toString().padLeft(2, '0')}-'
              '${dob.day.toString().padLeft(2, '0')}';

    final avatar = await _toDataUri(data.selfieImageUrl);
    final aadhaarFront = await _toDataUri(data.aadhaarFrontPath);
    final aadhaarBack = await _toDataUri(data.aadhaarBackPath);
    final panFront = await _toDataUri(data.panFrontPath);
    final panBack = await _toDataUri(data.panBackPath);
    final certUri = await _toDataUri(data.certificatePath);

    final certifications = <String>[
      if (certUri != null && certUri.isNotEmpty) certUri,
    ];

    final workAddress =
        (loc.addressLabel != null && loc.addressLabel!.isNotEmpty)
        ? loc.addressLabel
        : null;

    final recentWorkPhotos = <String>[];
    for (final path in data.recentWorkPhotoPaths) {
      final uri = await _toDataUri(path);
      if (uri != null && uri.isNotEmpty) recentWorkPhotos.add(uri);
    }

    return {
      'name': data.fullName.trim(),
      'phone': data.phone.trim(),
      if (dobStr != null) 'dateOfBirth': dobStr,
      if (data.gender != null) 'gender': data.gender!.name,
      if (avatar != null) 'avatar': avatar,
      if (avatar != null) 'selfieImageUrl': avatar,
      if (primaryCategory != null) 'category': primaryCategory,
      'categories': categories,
      'rate': data.primaryRate,
      'hourlyRate': data.primaryRate,
      'categoryRates': data.categoryRatesPayload,
      'experienceYears': data.experienceYears,
      'bio': data.bio.trim(),
      'skills': data.skills,
      'certifications': certifications,
      'aadhaarNumber': data.aadhaar.replaceAll(' ', ''),
      if (aadhaarFront != null) 'aadhaarFrontPhoto': aadhaarFront,
      if (aadhaarBack != null) 'aadhaarBackPhoto': aadhaarBack,
      'panNumber': data.pan.trim().toUpperCase(),
      if (panFront != null) 'panFrontPhoto': panFront,
      if (panBack != null) 'panBackPhoto': panBack,
      'govermentIdType': 'Aadhaar Card',
      'govermentIdNumber': data.aadhaar.replaceAll(' ', ''),
      if (workAddress != null) 'workAddress': workAddress,
      if (loc.hasFix) 'location': loc.toGeoJsonPointOrNull(),
      if (data.state.trim().isNotEmpty) 'state': data.state.trim(),
      if (data.district.trim().isNotEmpty) 'district': data.district.trim(),
      if (data.hasEshram && data.eshramUan.trim().isNotEmpty)
        'eshramUan': data.eshramUan.trim(),
      if (recentWorkPhotos.isNotEmpty) 'recentWorkPhotos': recentWorkPhotos,
      'payoutMethod': data.payoutMethod.name,
      'bank': {
        'accountHolderName': data.accountHolderName.trim(),
        'accountNumber': data.bankAccount.trim(),
        'ifscCode': data.ifscCode.trim().toUpperCase(),
      },
      'upi': {'upiId': data.upiId.trim()},
      if (data.federationId != null) 'federationId': data.federationId,
      if (data.federationName != null) 'federationName': data.federationName,
      if (data.includedTasks.isNotEmpty) 'includedTasks': data.includedTasks,
      if (data.excludedTasks.isNotEmpty) 'excludedTasks': data.excludedTasks,
    };
  }

  static Future<String?> _toDataUri(String? path) async {
    if (path == null || path.trim().isEmpty) return null;
    final trimmed = path.trim();
    if (trimmed.startsWith('data:') ||
        trimmed.startsWith('http://') ||
        trimmed.startsWith('https://')) {
      return trimmed;
    }
    final file = File(trimmed);
    if (!await file.exists()) {
      throw StateError('File not found: $trimmed');
    }
    final bytes = await file.readAsBytes();
    final mime = _mimeFor(trimmed);
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  static String _mimeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    return 'application/octet-stream';
  }
}

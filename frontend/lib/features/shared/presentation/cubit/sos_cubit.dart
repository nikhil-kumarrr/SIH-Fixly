import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/location/app_location.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../bookings/data/bookings_api_repository.dart';
import '../../../home/data/home_api_repository.dart';
import '../../../../shared/models/models.dart';

class SosState extends Equatable {
  final bool isLoadingContacts;
  final List<Map<String, dynamic>> contacts;
  final bool isBroadcasting;
  final bool isLoadingEstimate;
  final String error;
  final String? successBookingId;
  final double? urgentFee;
  final double? estimateTotalMin;
  final double? estimateTotalMax;
  final List<ServiceItem> services;
  final String? selectedServiceId;

  const SosState({
    this.isLoadingContacts = false,
    this.contacts = const [],
    this.isBroadcasting = false,
    this.isLoadingEstimate = false,
    this.error = '',
    this.successBookingId,
    this.urgentFee,
    this.estimateTotalMin,
    this.estimateTotalMax,
    this.services = const [],
    this.selectedServiceId,
  });

  SosState copyWith({
    bool? isLoadingContacts,
    List<Map<String, dynamic>>? contacts,
    bool? isBroadcasting,
    bool? isLoadingEstimate,
    String? error,
    String? successBookingId,
    double? urgentFee,
    double? estimateTotalMin,
    double? estimateTotalMax,
    List<ServiceItem>? services,
    String? selectedServiceId,
    bool clearSuccess = false,
    bool clearError = false,
  }) {
    return SosState(
      isLoadingContacts: isLoadingContacts ?? this.isLoadingContacts,
      contacts: contacts ?? this.contacts,
      isBroadcasting: isBroadcasting ?? this.isBroadcasting,
      isLoadingEstimate: isLoadingEstimate ?? this.isLoadingEstimate,
      error: clearError ? '' : (error ?? this.error),
      successBookingId:
          clearSuccess ? null : (successBookingId ?? this.successBookingId),
      urgentFee: urgentFee ?? this.urgentFee,
      estimateTotalMin: estimateTotalMin ?? this.estimateTotalMin,
      estimateTotalMax: estimateTotalMax ?? this.estimateTotalMax,
      services: services ?? this.services,
      selectedServiceId: selectedServiceId ?? this.selectedServiceId,
    );
  }

  @override
  List<Object?> get props => [
        isLoadingContacts,
        contacts,
        isBroadcasting,
        isLoadingEstimate,
        error,
        successBookingId,
        urgentFee,
        estimateTotalMin,
        estimateTotalMax,
        services,
        selectedServiceId,
      ];
}

class SosCubit extends Cubit<SosState> {
  SosCubit({
    BookingsApiRepository? bookings,
    HomeApiRepository? home,
  })  : _bookings = bookings ?? BookingsApiRepository(),
        _home = home ?? HomeApiRepository(),
        super(const SosState());

  final BookingsApiRepository _bookings;
  final HomeApiRepository _home;

  Future<void> loadContacts() async {
    emit(state.copyWith(isLoadingContacts: true, clearError: true));
    try {
      final api = ApiServices.client;
      List<Map<String, dynamic>> contacts = [];
      try {
        final res = await api.get('/api/emergency/contacts');
        if (res['data'] != null) {
          contacts = List<Map<String, dynamic>>.from(res['data']);
        }
      } catch (_) {
        contacts = [
          {'name': 'Police', 'number': '100', 'icon': 'police'},
          {'name': 'Ambulance', 'number': '102', 'icon': 'ambulance'},
          {'name': 'Fire', 'number': '101', 'icon': 'fire'},
          {'name': 'Women Helpline', 'number': '1091', 'icon': 'women'},
        ];
      }

      List<ServiceItem> services = const [];
      try {
        services = await _home.fetchAllServices();
      } catch (_) {}

      emit(
        state.copyWith(
          isLoadingContacts: false,
          contacts: contacts,
          services: services,
          selectedServiceId: services.isNotEmpty ? services.first.id : null,
        ),
      );
      if (services.isNotEmpty) {
        await refreshEstimate(services.first.id);
      }
    } catch (e) {
      emit(state.copyWith(isLoadingContacts: false, error: e.toString()));
    }
  }

  Future<void> selectService(String serviceId) async {
    emit(state.copyWith(selectedServiceId: serviceId));
    await refreshEstimate(serviceId);
  }

  Future<void> refreshEstimate(String serviceId) async {
    emit(state.copyWith(isLoadingEstimate: true, clearError: true));
    try {
      final est = await _bookings.estimate(
        serviceId: serviceId,
        isEmergency: true,
      );
      emit(
        state.copyWith(
          isLoadingEstimate: false,
          urgentFee: est.urgentFee,
          estimateTotalMin: est.minTotal,
          estimateTotalMax: est.maxTotal,
        ),
      );
    } on ApiException catch (e) {
      emit(state.copyWith(isLoadingEstimate: false, error: e.message));
    } catch (e) {
      emit(state.copyWith(isLoadingEstimate: false, error: e.toString()));
    }
  }

  /// Creates SOS booking. Price = platform surcharge + service base (not worker-set).
  Future<bool> broadcastEmergencyBooking({
    required String serviceId,
    required String description,
    double? offeredPrice,
  }) async {
    emit(state.copyWith(isBroadcasting: true, clearError: true, clearSuccess: true));
    try {
      final loc = AppLocation.instance;
      if (!loc.hasFix) {
        emit(
          state.copyWith(
            isBroadcasting: false,
            error: 'Location required for emergency booking. Enable GPS and retry.',
          ),
        );
        return false;
      }

      final booking = await _bookings.createEmergency(
        serviceId: serviceId,
        issueDescription: description,
        latitude: loc.requireLat,
        longitude: loc.requireLng,
        offeredPrice: offeredPrice,
      );

      emit(
        state.copyWith(
          isBroadcasting: false,
          successBookingId: booking.id,
        ),
      );
      return true;
    } on ApiException catch (e) {
      emit(state.copyWith(isBroadcasting: false, error: e.message));
      return false;
    } catch (e) {
      emit(
        state.copyWith(
          isBroadcasting: false,
          error: ApiException.fromError(e),
        ),
      );
      return false;
    }
  }

  Future<bool> triggerInJobSos(String bookingId) async {
    emit(state.copyWith(isBroadcasting: true, clearError: true));
    try {
      await _bookings.triggerSos(bookingId);
      emit(state.copyWith(isBroadcasting: false));
      return true;
    } on ApiException catch (e) {
      emit(state.copyWith(isBroadcasting: false, error: e.message));
      return false;
    } catch (e) {
      emit(
        state.copyWith(
          isBroadcasting: false,
          error: ApiException.fromError(e),
        ),
      );
      return false;
    }
  }
}

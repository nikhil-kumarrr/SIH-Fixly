import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/network/customer_realtime_service.dart';
import '../../../../shared/data/mock/mock_repository.dart';
import '../../../../shared/models/models.dart';
import '../../../bookings/data/bookings_api_repository.dart';
import '../../../payments/data/payments_api_repository.dart';
import '../../../payments/services/razorpay_checkout_service.dart';

part 'booking_flow_state.dart';

class BookingFlowCubit extends Cubit<BookingFlowState> {
  BookingFlowCubit({
    MockRepository? repository,
    BookingsApiRepository? bookingsRepository,
    PaymentsApiRepository? paymentsRepository,
    RazorpayCheckoutService? razorpayCheckout,
  }) : _repo = repository ?? MockRepository.instance,
       _bookings = bookingsRepository ?? BookingsApiRepository(),
       _payments = paymentsRepository ?? PaymentsApiRepository(),
       _razorpay = razorpayCheckout ?? RazorpayCheckoutService(),
       super(const BookingFlowState());

  final MockRepository _repo;
  final BookingsApiRepository _bookings;
  final PaymentsApiRepository _payments;
  final RazorpayCheckoutService _razorpay;

  Timer? _statusPollTimer;
  StreamSubscription<Map<String, dynamic>>? _statusSubscription;
  String? _listeningBookingId;

  void _safeEmit(BookingFlowState next) {
    if (isClosed) return;
    emit(next);
  }

  void selectService(ServiceItem service) {
    _safeEmit(state.copyWith(service: service, step: BookingStatus.draft));
  }

  /// Load an existing booking into state (e.g. from order history tap).
  void loadFromBooking(Booking booking) {
    _repo.activeBooking = booking;
    _safeEmit(state.copyWith(
      booking: booking,
      step: booking.status,
      clearError: true,
    ));
    listenToSocketUpdates(booking.id);
  }

  /// Start polling booking status every 5s (for finding-worker / accepted screens).
  void startStatusPolling(String bookingId) {
    _statusPollTimer?.cancel();
    _statusPollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (isClosed) return;
      await refreshBooking(bookingId);
    });
  }

  void stopStatusPolling() {
    _statusPollTimer?.cancel();
    _statusPollTimer = null;
  }

  /// Connect to socket and listen for real-time booking_status_update events.
  void listenToSocketUpdates(String bookingId) {
    if (bookingId.isEmpty || isClosed) return;
    if (_listeningBookingId == bookingId && _statusSubscription != null) return;
    _listeningBookingId = bookingId;
    CustomerRealtimeService.instance.trackBooking(bookingId);

    _statusSubscription?.cancel();
    _statusSubscription = CustomerRealtimeService.instance.bookingStatusStream.listen((map) async {
      if (isClosed) return;
      final eventBookingId = map['bookingId']?.toString();
      final canonicalId = map['canonicalBookingId']?.toString();
      final current = state.booking;
      if (current != null &&
          eventBookingId != null &&
          eventBookingId != current.id &&
          canonicalId != current.id &&
          eventBookingId != bookingId) {
        return;
      }

      final newStatus = map['status']?.toString();
      final paymentStatus = map['paymentStatus']?.toString();

      // Instant UI from socket payload, then hydrate via API.
      if (current != null && (newStatus != null || paymentStatus != null)) {
        final mapped = BookingsApiRepository.mapStatus(newStatus ?? current.rawStatus);
        _safeEmit(
          state.copyWith(
            booking: current.copyWith(
              status: paymentStatus == 'PAID' ? BookingStatus.paid : mapped,
              rawStatus: paymentStatus == 'PAID'
                  ? 'COMPLETED'
                  : (newStatus ?? current.rawStatus),
              paymentStatus: paymentStatus ?? current.paymentStatus,
            ),
            step: paymentStatus == 'PAID' ? BookingStatus.paid : mapped,
          ),
        );
      }
      if (isClosed) return;
      await refreshBooking(bookingId);
    });

    // Polling as fallback when socket drops
    startStatusPolling(bookingId);
  }

  Future<void> submitBookingDetails({
    required String address,
    DateTime? scheduledAt,
    required String problemDescription,
    String? workerId,
    List<String> photoPaths = const [],
    List<String> videoPaths = const [],
    bool isEmergency = false,
  }) async {
    final service = state.service;
    if (service == null) {
      _safeEmit(state.copyWith(errorMessage: 'Please select a service first'));
      return;
    }
    _safeEmit(state.copyWith(isLoading: true, clearError: true));
    try {
      final booking = await _bookings.create(
        serviceId: service.id,
        addressLine: address,
        problemDescription: problemDescription,
        workerId: workerId,
        scheduledTime: isEmergency ? null : scheduledAt,
        serviceTitle: service.title,
        photoPaths: photoPaths,
        videoPaths: videoPaths,
        isEmergency: isEmergency,
        bookingType: isEmergency ? 'EMERGENCY_SOS' : null,
        timeSlot: isEmergency ? 'Immediate (SOS Emergency)' : null,
      );
      if (isClosed) return;
      _repo.activeBooking = booking;
      _safeEmit(
        state.copyWith(
          booking: booking,
          address: address,
          scheduledAt: scheduledAt,
          step: BookingStatus.searching,
          isLoading: false,
        ),
      );
      listenToSocketUpdates(booking.id);
    } on ApiException catch (e) {
      _safeEmit(state.copyWith(isLoading: false, errorMessage: e.message));
    } catch (e) {
      _safeEmit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> confirmEstimate() async {
    _safeEmit(state.copyWith(isLoading: false, step: BookingStatus.draft));
  }

  Future<void> searchWorker() async {
    _safeEmit(state.copyWith(isLoading: true, step: BookingStatus.searching));
    await Future<void>.delayed(const Duration(seconds: 1));
    if (isClosed) return;
    _safeEmit(
      state.copyWith(
        isLoading: false,
        step: BookingStatus.searching,
        booking: state.booking,
      ),
    );
  }

  Future<void> workerAccepted() async {
    final booking = state.booking;
    if (booking == null) return;
    _safeEmit(state.copyWith(isLoading: true, clearError: true));
    try {
      final updated = await _bookings.getById(
        booking.id,
        serviceTitle: booking.serviceTitle,
      );
      if (isClosed) return;
      _repo.activeBooking = updated;
      _safeEmit(
        state.copyWith(
          isLoading: false,
          step: updated.workerId != null
              ? BookingStatus.accepted
              : BookingStatus.searching,
          booking: updated,
        ),
      );
    } on ApiException catch (e) {
      _safeEmit(state.copyWith(isLoading: false, errorMessage: e.message));
    }
  }

  Future<void> refreshBooking([String? bookingId]) async {
    if (isClosed) return;
    final idToFetch = bookingId ?? state.booking?.id;
    if (idToFetch == null) return;
    try {
      final updated = await _bookings.getById(
        idToFetch,
        serviceTitle: state.booking?.serviceTitle ?? 'Fixly Service',
      );
      if (isClosed) return;
      _repo.activeBooking = updated;
      _safeEmit(state.copyWith(booking: updated, step: updated.status, clearError: true));
      // Keep socket joined for live status without manual reload.
      listenToSocketUpdates(updated.id);
    } on ApiException catch (e) {
      _safeEmit(state.copyWith(errorMessage: e.message));
    }
  }

  double _payableAmount([Booking? targetBooking]) {
    final booking = targetBooking ?? state.booking;
    if (booking?.totalAmount != null && booking!.totalAmount! > 0) {
      return booking.totalAmount!;
    }
    if (booking?.invoice?.totalAmount != null && booking!.invoice!.totalAmount > 0) {
      return booking.invoice!.totalAmount;
    }
    final totalPrice = booking?.totalPrice;
    if (totalPrice != null && totalPrice > 0) {
      return totalPrice;
    }
    if (booking != null && booking.estimatedPrice > 0) {
      return booking.estimatedPrice;
    }
    if (state.priceEstimate != null && state.priceEstimate!.maxTotal > 0) {
      return state.priceEstimate!.maxTotal;
    }
    return state.service?.priceFrom ?? 0;
  }

  Future<bool> payWithRazorpay({
    String? bookingId,
    double? amountOverride,
    String? customerName,
    String? email,
    String? phone,
  }) async {
    final targetBookingId = bookingId ?? state.booking?.id;
    if (targetBookingId == null) return false;
    _safeEmit(state.copyWith(isLoading: true, clearError: true));
    try {
      await refreshBooking(targetBookingId);
      if (isClosed) return false;
      final current = state.booking;
      if (current == null) {
        throw ApiException('Booking details not found');
      }
      final amount = amountOverride ?? _payableAmount(current);
      if (amount <= 0) {
        throw ApiException('Invalid payment amount');
      }

      await _payments.fetchConfig();
      final order = await _payments.createOrder(
        bookingId: current.id,
        amountRupees: amount,
      );

      final result = await _razorpay.openCheckout(
        order: order,
        description: '${current.serviceTitle} payment',
        customerName: customerName,
        email: email,
        phone: phone,
      );

      final verified = await _payments.verify(
        razorpayOrderId: result.orderId,
        razorpayPaymentId: result.paymentId,
        razorpaySignature: result.signature,
        bookingId: current.id,
      );
      if (!verified) {
        throw ApiException('Payment verification failed');
      }

      await refreshBooking(current.id);
      if (isClosed) return false;
      final updated = state.booking ??
          current.copyWith(
            status: BookingStatus.paid,
            paymentStatus: 'PAID',
          );
      _repo.activeBooking = updated;
      _safeEmit(
        state.copyWith(
          isLoading: false,
          step: BookingStatus.rating,
          booking: updated,
        ),
      );
      return true;
    } on ApiException catch (e) {
      _safeEmit(state.copyWith(isLoading: false, errorMessage: e.message));
      return false;
    } catch (e) {
      _safeEmit(
        state.copyWith(
          isLoading: false,
          errorMessage: ApiException.fromError(e),
        ),
      );
      return false;
    }
  }

  void reset() {
    _statusPollTimer?.cancel();
    _statusSubscription?.cancel();
    CustomerRealtimeService.instance.untrackBooking();
    _listeningBookingId = null;
    _razorpay.dispose();
    _repo.activeBooking = null;
    _safeEmit(const BookingFlowState());
  }

  @override
  Future<void> close() {
    _statusPollTimer?.cancel();
    _statusPollTimer = null;
    _statusSubscription?.cancel();
    _statusSubscription = null;
    _listeningBookingId = null;
    CustomerRealtimeService.instance.untrackBooking();
    _razorpay.dispose();
    return super.close();
  }
}

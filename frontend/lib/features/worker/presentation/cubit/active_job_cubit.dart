import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/network/worker_realtime_service.dart';
import '../../../../core/preferences/app_preferences.dart';
import '../../../../shared/models/models.dart';
import '../../../bookings/data/bookings_api_repository.dart';
import '../../../reviews/data/reviews_api_repository.dart';

part 'active_job_state.dart';

class ActiveJobCubit extends Cubit<ActiveJobState> {
  ActiveJobCubit({BookingsApiRepository? bookings})
      : _bookings = bookings ?? BookingsApiRepository(),
        super(const ActiveJobState());

  final BookingsApiRepository _bookings;
  StreamSubscription? _statusSub;
  Timer? _pollTimer;
  bool _finalizeInFlight = false;
  bool _refreshing = false;

  static const _terminalRaw = {
    'PAYMENT_PENDING',
    'COMPLETED',
    'PAYMENT_PAID',
    'PAID',
    'CANCELLED',
  };

  static int _statusRank(String? raw) {
    switch ((raw ?? '').toUpperCase()) {
      case 'PENDING':
      case 'SEARCHING':
        return 0;
      case 'APPROVED':
      case 'ACCEPTED':
        return 1;
      case 'ARRIVED':
        return 2;
      case 'ESTIMATION_GIVEN':
      case 'ESTIMATION_SUBMITTED':
        return 3;
      case 'READY_TO_START':
        return 4;
      case 'IN_PROGRESS':
        return 5;
      case 'PAYMENT_PENDING':
        return 6;
      case 'COMPLETED':
      case 'PAYMENT_PAID':
      case 'PAID':
        return 7;
      case 'CANCELLED':
        return 8;
      default:
        return -1;
    }
  }

  ActiveJobStatus _cubitStatusForRaw(String? raw) {
    switch ((raw ?? '').toUpperCase()) {
      case 'PAYMENT_PENDING':
        return ActiveJobStatus.awaitingPayment;
      case 'COMPLETED':
      case 'PAYMENT_PAID':
      case 'PAID':
        return ActiveJobStatus.paymentReceived;
      case 'IN_PROGRESS':
        return ActiveJobStatus.inProgress;
      default:
        return ActiveJobStatus.loaded;
    }
  }

  bool _wouldRegress(String? currentRaw, String? incomingRaw) {
    final cur = _statusRank(currentRaw);
    final next = _statusRank(incomingRaw);
    if (cur < 0 || next < 0) return false;
    return next < cur;
  }

  Future<void> load() async {
    if (isClosed) return;
    emit(state.copyWith(status: ActiveJobStatus.loading, clearError: true));
    try {
      final userId = await ApiServices.tokens.userId;
      if (isClosed) return;
      if (userId != null && userId.isNotEmpty) {
        WorkerRealtimeService.instance.initForWorker(userId);
      }

      final jobs = await _bookings.workerActive();
      if (isClosed) return;
      final job = jobs.isEmpty ? null : jobs.first;

      if (job != null) {
        WorkerRealtimeService.instance.trackBooking(job.id);
        await AppPreferences.instance.setActiveWorkerJobId(job.id);
      } else {
        await AppPreferences.instance.setActiveWorkerJobId(null);
      }
      if (isClosed) return;

      _bindRealtime();

      emit(
        ActiveJobState(
          status: _cubitStatusForRaw(job?.rawStatus),
          job: job,
        ),
      );
      _syncPoll();
    } on ApiException catch (e) {
      if (isClosed) return;
      emit(state.copyWith(status: ActiveJobStatus.failure, error: e.message));
    }
  }

  void _bindRealtime() {
    _statusSub?.cancel();
    _statusSub = WorkerRealtimeService.instance.bookingStatusStream.listen((data) {
      _onSocketStatusUpdate(data);
    });
  }

  void _syncPoll() {
    _pollTimer?.cancel();
    _pollTimer = null;
    final job = state.job;
    if (job == null) return;
    final raw = (job.rawStatus ?? '').toUpperCase();
    if (raw == 'CANCELLED' || raw == 'PAID' || raw == 'PAYMENT_PAID') {
      if (state.status == ActiveJobStatus.paymentReceived) {
        // Keep listening for payment; still poll until review navigates away.
      }
    }
    // Poll every 5s while job active (backup when socket silent).
    if (raw == 'COMPLETED' && state.status == ActiveJobStatus.reviewSubmitted) {
      return;
    }
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_pollRefresh());
    });
  }

  Future<void> _pollRefresh() async {
    if (_refreshing || _finalizeInFlight || state.job == null) return;
    _refreshing = true;
    try {
      final jobs = await _bookings.workerActive();
      if (isClosed) return;
      final fresh = jobs.isEmpty ? null : jobs.first;
      if (fresh == null) {
        // Paid/cancelled jobs leave the active list.
        if (state.status == ActiveJobStatus.awaitingPayment &&
            state.job != null) {
          emit(
            state.copyWith(
              status: ActiveJobStatus.paymentReceived,
              job: state.job!.copyWith(
                status: JobStatus.completed,
                rawStatus: 'PAYMENT_PAID',
              ),
            ),
          );
          return;
        }
        if (state.status == ActiveJobStatus.paymentReceived) return;
        emit(state.copyWith(status: ActiveJobStatus.loaded, job: null));
        _pollTimer?.cancel();
        return;
      }

      final current = state.job!;
      if (_wouldRegress(current.rawStatus, fresh.rawStatus)) {
        return;
      }

      final changed = fresh.rawStatus != current.rawStatus ||
          fresh.status != current.status ||
          fresh.invoice?.totalAmount != current.invoice?.totalAmount ||
          fresh.invoice?.paymentStatus != current.invoice?.paymentStatus ||
          fresh.jobStartedAt != current.jobStartedAt;

      if (!changed &&
          _cubitStatusForRaw(fresh.rawStatus) == state.status) {
        return;
      }

      emit(
        state.copyWith(
          status: _cubitStatusForRaw(fresh.rawStatus),
          job: fresh,
        ),
      );
    } catch (_) {
      // Next tick retries.
    } finally {
      _refreshing = false;
    }
  }

  void _onSocketStatusUpdate(Map<String, dynamic> data) {
    if (isClosed) return;
    final currentJob = state.job;
    if (currentJob == null) return;

    final bookingId = data['bookingId']?.toString();
    final canonicalId = data['canonicalBookingId']?.toString();
    if (bookingId != currentJob.id &&
        canonicalId != currentJob.id) {
      return;
    }

    final newStatus = data['status']?.toString();
    final paymentStatus = data['paymentStatus']?.toString() ??
        (data['invoice'] is Map
            ? (data['invoice'] as Map)['paymentStatus']?.toString()
            : null);

    // While finalizing billing, ignore stale IN_PROGRESS from add-parts emit.
    if (_finalizeInFlight) {
      final upper = (newStatus ?? '').toUpperCase();
      if (paymentStatus != 'PAID' &&
          upper != 'PAYMENT_PENDING' &&
          upper != 'COMPLETED' &&
          upper != 'PAID' &&
          upper != 'PAYMENT_PAID') {
        return;
      }
    }

    if (paymentStatus == 'PAID' ||
        newStatus == 'COMPLETED' ||
        newStatus == 'PAID' ||
        newStatus == 'PAYMENT_PAID') {
      emit(
        state.copyWith(
          status: ActiveJobStatus.paymentReceived,
          job: currentJob.copyWith(
            status: JobStatus.completed,
            rawStatus: 'PAYMENT_PAID',
            invoice: data['invoice'] is Map
                ? BookingInvoice.fromJson(
                    Map<String, dynamic>.from(data['invoice'] as Map),
                  )
                : currentJob.invoice,
          ),
        ),
      );
      return;
    }

    if (newStatus == null || newStatus.isEmpty) {
      // Invoice-only update — refresh invoice, never regress status.
      if (data['invoice'] is Map) {
        emit(
          state.copyWith(
            job: currentJob.copyWith(
              invoice: BookingInvoice.fromJson(
                Map<String, dynamic>.from(data['invoice'] as Map),
              ),
            ),
          ),
        );
      }
      return;
    }

    // Never let a stale IN_PROGRESS (e.g. from add-parts socket) undo billing.
    if (_wouldRegress(currentJob.rawStatus, newStatus) ||
        (state.status == ActiveJobStatus.awaitingPayment &&
            newStatus.toUpperCase() == 'IN_PROGRESS') ||
        (state.status == ActiveJobStatus.paymentReceived &&
            !_terminalRaw.contains(newStatus.toUpperCase()))) {
      return;
    }

    if (newStatus.toUpperCase() == 'PAYMENT_PENDING') {
      emit(
        state.copyWith(
          status: ActiveJobStatus.awaitingPayment,
          job: currentJob.copyWith(
            rawStatus: 'PAYMENT_PENDING',
            invoice: data['invoice'] is Map
                ? BookingInvoice.fromJson(
                    Map<String, dynamic>.from(data['invoice'] as Map),
                  )
                : currentJob.invoice,
          ),
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        status: _cubitStatusForRaw(newStatus),
        job: currentJob.copyWith(
          rawStatus: newStatus,
          invoice: data['invoice'] is Map
              ? BookingInvoice.fromJson(
                  Map<String, dynamic>.from(data['invoice'] as Map),
                )
              : currentJob.invoice,
        ),
      ),
    );
  }

  Future<void> completeJob() async {
    if (state.job == null || _finalizeInFlight) return;
    final raw = (state.job!.rawStatus ?? '').toUpperCase();
    if (raw == 'PAYMENT_PENDING' ||
        raw == 'COMPLETED' ||
        raw == 'PAYMENT_PAID' ||
        state.status == ActiveJobStatus.awaitingPayment ||
        state.status == ActiveJobStatus.paymentReceived) {
      return;
    }
    _finalizeInFlight = true;
    emit(state.copyWith(status: ActiveJobStatus.loading, clearError: true));
    try {
      final res = await _bookings.complete(state.job!.id);
      final nextStatus =
          res['status']?.toString() ?? res['booking']?['status']?.toString();
      if (nextStatus == 'PAYMENT_PENDING') {
        emit(
          state.copyWith(
            status: ActiveJobStatus.awaitingPayment,
            job: state.job!.copyWith(rawStatus: 'PAYMENT_PENDING'),
          ),
        );
      } else if (nextStatus == 'COMPLETED') {
        emit(
          state.copyWith(
            status: ActiveJobStatus.paymentReceived,
            job: state.job!.copyWith(
              status: JobStatus.completed,
              rawStatus: 'PAYMENT_PAID',
            ),
          ),
        );
      } else {
        emit(
          state.copyWith(
            status: _cubitStatusForRaw(nextStatus),
            job: state.job!.copyWith(rawStatus: nextStatus ?? state.job!.rawStatus),
          ),
        );
      }
      _syncPoll();
    } on ApiException catch (e) {
      emit(
        state.copyWith(
          status: ActiveJobStatus.inProgress,
          error: e.message,
        ),
      );
    } finally {
      _finalizeInFlight = false;
    }
  }

  /// Arrival OTP only — does not start work.
  Future<void> verifyArrivalOtp({required String otp}) async {
    if (state.job == null) return;
    emit(state.copyWith(status: ActiveJobStatus.loading, clearError: true));
    try {
      await _bookings.verifyArrivalOtp(bookingId: state.job!.id, otp: otp);
      final jobs = await _bookings.workerActive();
      emit(
        state.copyWith(
          status: ActiveJobStatus.loaded,
          job: jobs.isEmpty
              ? state.job!.copyWith(rawStatus: 'ARRIVED')
              : jobs.first,
        ),
      );
    } on ApiException catch (e) {
      emit(state.copyWith(status: ActiveJobStatus.failure, error: e.message));
    }
  }

  Future<void> startJob() async {
    if (state.job == null) return;
    emit(state.copyWith(status: ActiveJobStatus.loading, clearError: true));
    try {
      await _bookings.startJob(state.job!.id);
      final jobs = await _bookings.workerActive();
      emit(
        state.copyWith(
          status: ActiveJobStatus.inProgress,
          job: jobs.isEmpty
              ? state.job!.copyWith(rawStatus: 'IN_PROGRESS')
              : jobs.first,
        ),
      );
    } on ApiException catch (e) {
      emit(state.copyWith(status: ActiveJobStatus.failure, error: e.message));
    }
  }

  Future<void> addExtraParts(
    List<Map<String, dynamic>> parts, {
    bool replace = false,
  }) async {
    if (state.job == null) return;
    emit(state.copyWith(status: ActiveJobStatus.loading, clearError: true));
    try {
      await _bookings.addParts(
        bookingId: state.job!.id,
        extraItems: parts,
        replace: replace,
      );
      final jobs = await _bookings.workerActive();
      emit(
        state.copyWith(
          status: ActiveJobStatus.inProgress,
          job: jobs.isEmpty ? state.job : jobs.first,
        ),
      );
    } on ApiException catch (e) {
      emit(state.copyWith(status: ActiveJobStatus.failure, error: e.message));
    }
  }

  /// Single-shot final billing → request payment. Prevents duplicate part stacks.
  Future<void> finalizeBillingAndRequestPayment(
    List<Map<String, dynamic>> parts,
  ) async {
    if (isClosed || state.job == null || _finalizeInFlight) return;
    final raw = (state.job!.rawStatus ?? '').toUpperCase();
    if (raw == 'PAYMENT_PENDING' ||
        raw == 'COMPLETED' ||
        raw == 'PAYMENT_PAID' ||
        state.status == ActiveJobStatus.awaitingPayment ||
        state.status == ActiveJobStatus.paymentReceived) {
      if (isClosed) return;
      emit(
        state.copyWith(
          status: ActiveJobStatus.awaitingPayment,
          job: state.job!.copyWith(rawStatus: 'PAYMENT_PENDING'),
        ),
      );
      return;
    }
    _finalizeInFlight = true;
    if (isClosed) {
      _finalizeInFlight = false;
      return;
    }
    emit(state.copyWith(status: ActiveJobStatus.loading, clearError: true));
    try {
      if (parts.isNotEmpty) {
        await _bookings.addParts(
          bookingId: state.job!.id,
          extraItems: parts,
          replace: true,
        );
      }
      if (isClosed) return;
      final res = await _bookings.complete(state.job!.id);
      if (isClosed) return;
      final nextStatus =
          res['status']?.toString() ?? res['booking']?['status']?.toString();
      final jobs = await _bookings.workerActive();
      if (isClosed) return;
      final job = jobs.isEmpty
          ? state.job!.copyWith(rawStatus: nextStatus ?? 'PAYMENT_PENDING')
          : jobs.first;
      // Force post-billing status — ignore stale IN_PROGRESS from add-parts socket race.
      final billedRaw =
          nextStatus == 'COMPLETED' ? 'PAYMENT_PAID' : 'PAYMENT_PENDING';
      emit(
        state.copyWith(
          status: nextStatus == 'COMPLETED'
              ? ActiveJobStatus.paymentReceived
              : ActiveJobStatus.awaitingPayment,
          job: job.copyWith(rawStatus: billedRaw),
        ),
      );
      _syncPoll();
    } on ApiException catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(
          status: ActiveJobStatus.failure,
          error: e.message,
        ),
      );
    } finally {
      _finalizeInFlight = false;
    }
  }

  Future<void> submitWorkerReview({
    required String bookingId,
    required String customerId,
    required int rating,
    String comment = '',
    List<String> traits = const [],
  }) async {
    if (isClosed) return;
    emit(state.copyWith(status: ActiveJobStatus.loading, clearError: true));
    try {
      await ReviewsApiRepository().submit(
        bookingId: bookingId,
        workerId: customerId,
        rating: rating,
        comment: comment,
        traits: traits,
        reviewerRole: 'worker',
      );
      if (isClosed) return;
      await AppPreferences.instance.setActiveWorkerJobId(null);
      if (isClosed) return;
      emit(state.copyWith(status: ActiveJobStatus.reviewSubmitted));
    } on ApiException catch (e) {
      if (isClosed) return;
      emit(state.copyWith(status: ActiveJobStatus.failure, error: e.message));
    }
  }

  @override
  Future<void> close() {
    _pollTimer?.cancel();
    _statusSub?.cancel();
    return super.close();
  }
}

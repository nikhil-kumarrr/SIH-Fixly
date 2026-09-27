import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/network/worker_realtime_service.dart';
import '../../../../shared/models/models.dart';
import '../../../auth/data/auth_api_repository.dart';
import '../../../bookings/data/bookings_api_repository.dart';
import '../../../payments/data/payments_api_repository.dart';
import '../../../workers/data/workers_api_repository.dart';

part 'worker_dashboard_state.dart';

class WorkerDashboardCubit extends Cubit<WorkerDashboardState> {
  WorkerDashboardCubit({
    AuthApiRepository? auth,
    BookingsApiRepository? bookings,
    PaymentsApiRepository? payments,
    WorkersApiRepository? workers,
  })  : _auth = auth ?? AuthApiRepository(),
        _bookings = bookings ?? BookingsApiRepository(),
        _payments = payments ?? PaymentsApiRepository(),
        _workers = workers ?? WorkersApiRepository(),
        super(const WorkerDashboardState());

  final AuthApiRepository _auth;
  final BookingsApiRepository _bookings;
  final PaymentsApiRepository _payments;
  final WorkersApiRepository _workers;

  StreamSubscription? _incomingSub;
  StreamSubscription? _claimedSub;
  StreamSubscription? _statusSub;
  StreamSubscription? _connectionSub;

  Future<void> load() async {
    emit(state.copyWith(status: WorkerDashboardStatus.loading, clearError: true));
    try {
      final userId = await ApiServices.tokens.userId;
      if (userId == null || userId.isEmpty) {
        throw ApiException('Not signed in');
      }
      final results = await Future.wait([
        _auth.fetchMe(),
        _payments.workerEarningsSummary(),
        _workers.fetchAvailability(),
        _bookings.workerIncoming(),
        _bookings.workerActive(),
        _workers.fetchReliability(userId),
      ]);
      final user = results[0] as AppUser;
      final summary = results[1] as Map<String, dynamic>;
      final availability = results[2] as Map<String, dynamic>;
      final incoming = results[3] as List<WorkerJob>;
      final active = results[4] as List<WorkerJob>;
      final reliability = results[5] as Map<String, dynamic>;

      // Initialize Socket.io for worker and subscribe to active booking
      WorkerRealtimeService.instance.initForWorker(userId);
      if (active.isNotEmpty) {
        WorkerRealtimeService.instance.trackBooking(active.first.id);
      } else {
        WorkerRealtimeService.instance.untrackBooking();
      }

      _incomingSub ??= WorkerRealtimeService.instance.incomingJobsStream.listen((_) {
        _silentRefresh();
      });
      _claimedSub ??= WorkerRealtimeService.instance.jobClaimedStream.listen((_) {
        _silentRefresh();
      });
      _statusSub ??= WorkerRealtimeService.instance.bookingStatusStream.listen((_) {
        _silentRefresh();
      });
      _connectionSub ??= WorkerRealtimeService.instance.connectionStream.listen((connected) {
        if (connected) {
          _silentRefresh();
        }
      });

      emit(
        WorkerDashboardState(
          status: WorkerDashboardStatus.loaded,
          workerName: user.name,
          todayEarnings: (summary['today'] as num?)?.toDouble() ?? 0,
          completedJobs: (summary['completedJobs'] as num?)?.toInt() ?? 0,
          reliabilityScore: (reliability['score'] as num?)?.toInt() ?? 0,
          incomingCount: incoming.length,
          incomingJobs: incoming,
          isAvailable: availability['isOnline'] == true,
          activeJob: active.isEmpty ? null : active.first,
          welfareFund: (summary['welfareFund'] as num?)?.toDouble() ?? 5000.0,
        ),
      );
    } on ApiException catch (e) {
      emit(state.copyWith(status: WorkerDashboardStatus.failure, error: e.message));
    } catch (e) {
      emit(state.copyWith(status: WorkerDashboardStatus.failure, error: ApiException.fromError(e)));
    }
  }

  Future<void> _silentRefresh() async {
    try {
      final userId = await ApiServices.tokens.userId;
      if (userId == null || isClosed) return;
      final results = await Future.wait([
        _payments.workerEarningsSummary(),
        _bookings.workerIncoming(),
        _bookings.workerActive(),
        _workers.fetchAvailability(),
      ]);
      final summary = results[0] as Map<String, dynamic>;
      final incoming = results[1] as List<WorkerJob>;
      final active = results[2] as List<WorkerJob>;
      final availability = results[3] as Map<String, dynamic>;
      if (!isClosed) {
        if (active.isNotEmpty) {
          WorkerRealtimeService.instance.trackBooking(active.first.id);
        } else {
          WorkerRealtimeService.instance.untrackBooking();
        }
        emit(state.copyWith(
          todayEarnings: (summary['today'] as num?)?.toDouble() ?? state.todayEarnings,
          completedJobs: (summary['completedJobs'] as num?)?.toInt() ?? state.completedJobs,
          incomingCount: incoming.length,
          incomingJobs: incoming,
          activeJob: active.isEmpty ? null : active.first,
          isAvailable: availability['isOnline'] == true,
        ));
      }
    } catch (_) {}
  }

  Future<void> toggleAvailability() async {
    final next = !state.isAvailable;
    try {
      final online = await _workers.setOnline(next);
      emit(state.copyWith(isAvailable: online));
      if (online) {
        WorkerRealtimeService.instance.reconnect();
      }
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message));
    }
  }

  Future<bool> acceptJob(String bookingId) async {
    emit(state.copyWith(acceptingJobId: bookingId, clearError: true));
    try {
      await _bookings.accept(bookingId);
      final updatedIncoming = state.incomingJobs.where((j) => j.id != bookingId).toList();
      emit(state.copyWith(
        incomingJobs: updatedIncoming,
        incomingCount: updatedIncoming.length,
        clearAcceptingJobId: true,
      ));
      await _silentRefresh();
      return true;
    } on ApiException catch (e) {
      emit(state.copyWith(clearAcceptingJobId: true, error: e.message));
      return false;
    } catch (e) {
      emit(state.copyWith(clearAcceptingJobId: true, error: ApiException.fromError(e)));
      return false;
    }
  }

  Future<bool> declineJob(String bookingId, {String reason = 'OTHER'}) async {
    try {
      await _bookings.decline(bookingId, reason: reason);
      final updatedIncoming = state.incomingJobs.where((j) => j.id != bookingId).toList();
      emit(state.copyWith(
        incomingJobs: updatedIncoming,
        incomingCount: updatedIncoming.length,
      ));
      return true;
    } catch (e) {
      emit(state.copyWith(error: ApiException.fromError(e)));
      return false;
    }
  }

  @override
  Future<void> close() {
    _incomingSub?.cancel();
    _claimedSub?.cancel();
    _statusSub?.cancel();
    _connectionSub?.cancel();
    return super.close();
  }
}


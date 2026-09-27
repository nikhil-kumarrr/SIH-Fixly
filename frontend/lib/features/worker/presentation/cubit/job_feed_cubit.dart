import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/network/worker_realtime_service.dart';
import '../../../../core/preferences/app_preferences.dart';
import '../../../../shared/models/models.dart';
import '../../../bookings/data/bookings_api_repository.dart';

part 'job_feed_state.dart';

class JobFeedCubit extends Cubit<JobFeedState> {
  JobFeedCubit({BookingsApiRepository? bookings})
    : _bookings = bookings ?? BookingsApiRepository(),
      super(const JobFeedState());

  final BookingsApiRepository _bookings;
  StreamSubscription? _incomingSub;
  StreamSubscription? _statusSub;
  StreamSubscription? _claimedSub;
  StreamSubscription? _connectionSub;

  Future<void> load() async {
    emit(state.copyWith(status: JobFeedStatus.loading, clearError: true));
    try {
      final userId = await ApiServices.tokens.userId;
      if (userId != null && userId.isNotEmpty) {
        WorkerRealtimeService.instance.initForWorker(userId);
      }

      final jobs = await _loadAllJobs();
      _setupRealtimeSubscriptions();

      emit(state.copyWith(status: JobFeedStatus.loaded, jobs: jobs));
    } on ApiException catch (e) {
      emit(state.copyWith(status: JobFeedStatus.failure, error: e.message));
    } catch (e) {
      emit(state.copyWith(status: JobFeedStatus.failure, error: ApiException.fromError(e)));
    }
  }

  void _setupRealtimeSubscriptions() {
    _incomingSub ??= WorkerRealtimeService.instance.incomingJobsStream.listen((_) {
      _silentReload();
    });
    _statusSub ??= WorkerRealtimeService.instance.bookingStatusStream.listen((_) {
      _silentReload();
    });
    _claimedSub ??= WorkerRealtimeService.instance.jobClaimedStream.listen((_) {
      _silentReload();
    });
    _connectionSub ??= WorkerRealtimeService.instance.connectionStream.listen((connected) {
      if (connected) {
        _silentReload();
      }
    });
  }

  Future<void> _silentReload() async {
    try {
      if (isClosed) return;
      final jobs = await _loadAllJobs();
      if (!isClosed) {
        emit(state.copyWith(status: JobFeedStatus.loaded, jobs: jobs));
      }
    } catch (_) {}
  }

  WorkerJob? jobById(String id) {
    try {
      return state.jobs.firstWhere((j) => j.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<bool> acceptJob(String id) async {
    emit(state.copyWith(actingJobId: id));
    try {
      await _bookings.accept(id);
      await AppPreferences.instance.setActiveWorkerJobId(id);
      final jobs = await _loadAllJobs();
      emit(state.copyWith(status: JobFeedStatus.loaded, jobs: jobs, clearActingJobId: true));
      return true;
    } on ApiException catch (e) {
      emit(state.copyWith(clearActingJobId: true, error: e.message));
      return false;
    } catch (e) {
      emit(state.copyWith(clearActingJobId: true, error: ApiException.fromError(e)));
      return false;
    }
  }

  Future<bool> declineJob(String id) async {
    emit(state.copyWith(actingJobId: id));
    try {
      await _bookings.decline(id);
      final jobs = await _loadAllJobs();
      emit(state.copyWith(status: JobFeedStatus.loaded, jobs: jobs, clearActingJobId: true));
      return true;
    } on ApiException catch (e) {
      emit(state.copyWith(clearActingJobId: true, error: e.message));
      return false;
    } catch (e) {
      emit(state.copyWith(clearActingJobId: true, error: ApiException.fromError(e)));
      return false;
    }
  }

  Future<bool> cancelScheduledJob(String id) async {
    emit(state.copyWith(actingJobId: id));
    try {
      await _bookings.workerCancel(id);
      final jobs = await _loadAllJobs();
      emit(state.copyWith(status: JobFeedStatus.loaded, jobs: jobs, clearActingJobId: true));
      return true;
    } on ApiException catch (e) {
      emit(state.copyWith(clearActingJobId: true, error: e.message));
      return false;
    } catch (e) {
      emit(state.copyWith(clearActingJobId: true, error: ApiException.fromError(e)));
      return false;
    }
  }

  Future<List<WorkerJob>> _loadAllJobs() async {
    final results = await Future.wait([
      _bookings.workerIncoming(),
      _bookings.workerActive(),
      _bookings.workerCompleted(),
    ]);
    return <WorkerJob>[...results[0], ...results[1], ...results[2]];
  }

  @override
  Future<void> close() {
    _incomingSub?.cancel();
    _statusSub?.cancel();
    _claimedSub?.cancel();
    _connectionSub?.cancel();
    return super.close();
  }
}

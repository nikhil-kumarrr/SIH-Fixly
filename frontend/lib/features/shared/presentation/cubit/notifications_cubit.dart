import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/api_exception.dart';
import '../../data/notifications_api_repository.dart';
import '../../../../shared/models/models.dart';

part 'notifications_state.dart';

class NotificationsCubit extends Cubit<NotificationsState> {
  NotificationsCubit({NotificationsApiRepository? repository})
    : _repo = repository ?? NotificationsApiRepository(),
      super(const NotificationsState());

  final NotificationsApiRepository _repo;

  Future<void> load() async {
    emit(
      state.copyWith(status: NotificationsStatus.loading, errorMessage: null),
    );
    try {
      emit(
        NotificationsState(
          status: NotificationsStatus.loaded,
          items: await _repo.list(),
        ),
      );
    } on ApiException catch (error) {
      emit(
        state.copyWith(
          status: NotificationsStatus.failure,
          errorMessage: error.message,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: NotificationsStatus.failure,
          errorMessage: ApiException.fromError(error),
        ),
      );
    }
  }

  Future<void> markAllRead() async {
    await _repo.markAllRead();
    await load();
  }

  Future<void> markRead(String id) async {
    await _repo.markRead(id);
    await load();
  }

  Future<void> delete(String id) async {
    await _repo.delete(id);
    await load();
  }
}

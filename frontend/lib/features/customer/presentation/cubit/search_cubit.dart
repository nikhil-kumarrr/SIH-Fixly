import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/location/app_location.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../shared/models/models.dart';
import '../../../home/data/home_api_repository.dart';
import '../../../workers/data/workers_api_repository.dart';

part 'search_state.dart';

class SearchCubit extends Cubit<SearchState> {
  SearchCubit({
    HomeApiRepository? homeRepository,
    WorkersApiRepository? workersRepository,
    String? initialQuery,
  }) : _home = homeRepository ?? HomeApiRepository(),
       _workers = workersRepository ?? WorkersApiRepository(),
       super(SearchState(query: initialQuery ?? '')) {
    _warmCache();
  }

  final HomeApiRepository _home;
  final WorkersApiRepository _workers;
  List<ServiceItem> _all = const [];

  Future<void> _warmCache() async {
    try {
      _all = await _home.fetchAllServices();
      if (state.query.isNotEmpty) {
        await search(state.query);
      }
    } catch (_) {}
  }

  Future<void> search(String query) async {
    emit(state.copyWith(query: query, isSearching: true));
    if (_all.isEmpty) {
      try {
        _all = await _home.fetchAllServices();
      } catch (_) {}
    }
    final q = query.trim().toLowerCase();
    final results = q.isEmpty
        ? _all
        : _all
              .where(
                (s) =>
                    s.title.toLowerCase().contains(q) ||
                    s.categoryId.toLowerCase().contains(q) ||
                    s.description.toLowerCase().contains(q),
              )
              .toList();
    emit(state.copyWith(results: results, isSearching: false));

    // The search screen also shows the complete specialist directory when
    // there is no text query. Omitting category lets the API return every
    // available specialist across all categories.
    await _loadWorkers(q.isEmpty ? null : q);
  }

  void clear() {
    emit(const SearchState());
  }

  Future<void> filterByCategory(String categoryId) async {
    emit(
      state.copyWith(
        query: categoryId,
        categoryId: categoryId,
        isSearching: true,
        isLoadingWorkers: true,
      ),
    );

    if (_all.isEmpty) {
      try {
        _all = await _home.fetchAllServices();
      } catch (_) {}
    }

    final normalized = categoryId.toLowerCase();
    final results = _all
        .where(
          (s) =>
              s.categoryId.toLowerCase() == normalized ||
              s.categoryId.toLowerCase().contains(normalized) ||
              normalized.contains(s.categoryId.toLowerCase()) ||
              (normalized == 'plumber' && s.categoryId.startsWith('plum')),
        )
        .toList();

    emit(state.copyWith(results: results, isSearching: false));

    await _loadWorkers(categoryId);
  }

  Future<void> _loadWorkers(String? categoryOrSkill) async {
    emit(
      state.copyWith(
        isLoadingWorkers: true,
        nearbyWorkers: const [],
        hasMoreWorkers: false,
        nextWorkerOffset: 0,
        clearWorkersEmpty: true,
      ),
    );
    try {
      final loc = AppLocation.instance;
      final lat = loc.hasFix
          ? loc.lat
          : 28.6139; // fallback coordinate if GPS not fixed
      final lng = loc.hasFix ? loc.lng : 77.2090;

      final page = await _workers.fetchNearbyPage(
        category: categoryOrSkill,
        sortBy: 'top_rated',
        lat: lat,
        lng: lng,
      );
      final workers = page.workers;

      final normalizedTarget = categoryOrSkill?.toLowerCase().trim() ?? '';

      // Top matching rank:
      // 1. Workers with skills explicitly matching target keyword/category
      // 2. Highest rating
      // 3. Number of jobs completed
      final sorted = List<WorkerProfile>.from(workers)
        ..sort((a, b) {
          final aMatchesSkill =
              normalizedTarget.isNotEmpty &&
              a.skills.any(
                (s) =>
                    s.toLowerCase().contains(normalizedTarget) ||
                    normalizedTarget.contains(s.toLowerCase()),
              );
          final bMatchesSkill =
              normalizedTarget.isNotEmpty &&
              b.skills.any(
                (s) =>
                    s.toLowerCase().contains(normalizedTarget) ||
                    normalizedTarget.contains(s.toLowerCase()),
              );

          if (aMatchesSkill && !bMatchesSkill) return -1;
          if (!aMatchesSkill && bMatchesSkill) return 1;

          final ratingDiff = b.rating.compareTo(a.rating);
          if (ratingDiff != 0) return ratingDiff;

          return b.jobsCompleted.compareTo(a.jobsCompleted);
        });

      final empty = sorted.isEmpty;
      emit(
        state.copyWith(
          nearbyWorkers: sorted,
          isLoadingWorkers: false,
          hasMoreWorkers: page.hasMore,
          nextWorkerOffset: page.nextOffset,
          clearWorkersEmpty: true,
          workersEmptyCode: empty ? page.code : null,
          workersEmptyMessage: empty ? page.message : null,
          searchRadiusKm: empty ? page.searchRadiusKm : null,
        ),
      );
    } catch (e) {
      final msg = e is ApiException
          ? e.message
          : e.toString().replaceFirst('Exception: ', '');
      emit(
        state.copyWith(
          nearbyWorkers: const [],
          isLoadingWorkers: false,
          clearWorkersEmpty: true,
          workersEmptyMessage: msg,
        ),
      );
    }
  }

  Future<void> loadMoreWorkers() async {
    if (state.isLoadingWorkers ||
        state.isLoadingMoreWorkers ||
        !state.hasMoreWorkers) {
      return;
    }
    emit(state.copyWith(isLoadingMoreWorkers: true));
    try {
      final loc = AppLocation.instance;
      final page = await _workers.fetchNearbyPage(
        category:
            state.categoryId ??
            (state.query.trim().isEmpty ? null : state.query.trim()),
        sortBy: 'top_rated',
        lat: loc.hasFix ? loc.lat : 28.6139,
        lng: loc.hasFix ? loc.lng : 77.2090,
        offset: state.nextWorkerOffset,
      );
      emit(
        state.copyWith(
          nearbyWorkers: [...state.nearbyWorkers, ...page.workers],
          hasMoreWorkers: page.hasMore,
          nextWorkerOffset: page.nextOffset,
          isLoadingMoreWorkers: false,
        ),
      );
    } catch (_) {
      emit(state.copyWith(isLoadingMoreWorkers: false));
    }
  }

  Future<void> refresh() async {
    _all = const [];
    final q = state.query.trim();
    if (state.categoryId != null && state.categoryId!.isNotEmpty) {
      await filterByCategory(state.categoryId!);
    } else {
      await search(q);
    }
  }
}

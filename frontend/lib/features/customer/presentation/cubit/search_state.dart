part of 'search_cubit.dart';

class SearchState extends Equatable {
  const SearchState({
    this.query = '',
    this.categoryId,
    this.results = const [],
    this.nearbyWorkers = const [],
    this.isSearching = false,
    this.isLoadingWorkers = false,
    this.hasMoreWorkers = false,
    this.nextWorkerOffset = 0,
    this.isLoadingMoreWorkers = false,
    this.workersEmptyCode,
    this.workersEmptyMessage,
    this.searchRadiusKm,
  });

  final String query;
  final String? categoryId;
  final List<ServiceItem> results;
  final List<WorkerProfile> nearbyWorkers;
  final bool isSearching;
  final bool isLoadingWorkers;
  final bool hasMoreWorkers;
  final int nextWorkerOffset;
  final bool isLoadingMoreWorkers;
  final String? workersEmptyCode;
  final String? workersEmptyMessage;
  final int? searchRadiusKm;

  SearchState copyWith({
    String? query,
    String? categoryId,
    List<ServiceItem>? results,
    List<WorkerProfile>? nearbyWorkers,
    bool? isSearching,
    bool? isLoadingWorkers,
    bool? hasMoreWorkers,
    int? nextWorkerOffset,
    bool? isLoadingMoreWorkers,
    String? workersEmptyCode,
    String? workersEmptyMessage,
    int? searchRadiusKm,
    bool clearWorkersEmpty = false,
  }) {
    return SearchState(
      query: query ?? this.query,
      categoryId: categoryId ?? this.categoryId,
      results: results ?? this.results,
      nearbyWorkers: nearbyWorkers ?? this.nearbyWorkers,
      isSearching: isSearching ?? this.isSearching,
      isLoadingWorkers: isLoadingWorkers ?? this.isLoadingWorkers,
      hasMoreWorkers: hasMoreWorkers ?? this.hasMoreWorkers,
      nextWorkerOffset: nextWorkerOffset ?? this.nextWorkerOffset,
      isLoadingMoreWorkers: isLoadingMoreWorkers ?? this.isLoadingMoreWorkers,
      workersEmptyCode: clearWorkersEmpty
          ? workersEmptyCode
          : (workersEmptyCode ?? this.workersEmptyCode),
      workersEmptyMessage: clearWorkersEmpty
          ? workersEmptyMessage
          : (workersEmptyMessage ?? this.workersEmptyMessage),
      searchRadiusKm: clearWorkersEmpty
          ? searchRadiusKm
          : (searchRadiusKm ?? this.searchRadiusKm),
    );
  }

  @override
  List<Object?> get props => [
    query,
    categoryId,
    results,
    nearbyWorkers,
    isSearching,
    isLoadingWorkers,
    hasMoreWorkers,
    nextWorkerOffset,
    isLoadingMoreWorkers,
    workersEmptyCode,
    workersEmptyMessage,
    searchRadiusKm,
  ];
}

import 'package:equatable/equatable.dart';
import 'package:fixly/core/constants/app_constants.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../shared/models/models.dart';
import '../../../home/data/home_api_repository.dart';

part 'customer_home_state.dart';

class CustomerHomeCubit extends Cubit<CustomerHomeState> {
  CustomerHomeCubit({HomeApiRepository? homeRepository})
      : _home = homeRepository ?? HomeApiRepository(),
        super(const CustomerHomeState());

  final HomeApiRepository _home;

  Future<void> load({bool forceNetwork = false}) async {
    emit(state.copyWith(status: CustomerHomeStatus.loading));
    try {
      try {
        final bundle = await _home.fetchHome(forceNetwork: forceNetwork);
        emit(
          state.copyWith(
            status: CustomerHomeStatus.loaded,
            categories: bundle.categories,
            popularServices: bundle.topServices,
            banners: bundle.banners,
          ),
        );
      } on ApiException {
        final categories = await _home.fetchCategories();
        List<CouponBanner> banners = const [];
        try {
          banners = await _home.fetchBanners();
        } catch (_) {}
        emit(
          state.copyWith(
            status: CustomerHomeStatus.loaded,
            categories: categories,
            popularServices: const [],
            banners: banners,
          ),
        );
      }
    } catch (_) {
      emit(state.copyWith(
        status: CustomerHomeStatus.error,
        banners: const [],
      ));
    }
  }

  void refresh() => load(forceNetwork: true);
}

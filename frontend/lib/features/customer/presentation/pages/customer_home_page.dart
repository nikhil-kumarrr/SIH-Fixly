import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router/route_names.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/map_constants.dart';
import '../../../../core/l10n/category_localizer.dart';
import '../../../../core/l10n/locale_scope.dart';
import '../../../../core/location/app_location.dart';
import '../../../../core/location/location_service.dart';
import '../../../../core/navigation/customer_navigation.dart';
import '../../../../core/navigation/screen_refresh.dart';
import '../../../../core/utils/toast_utils.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../../core/widgets/fixly_map_view.dart';
import '../../../../shared/data/mock/mock_repository.dart';
import '../../../../shared/models/models.dart';
import '../../../../shared/widgets/category_icon_tile.dart';
import '../../../auth/presentation/cubit/app_session_cubit.dart';
import '../cubit/customer_home_cubit.dart';

class CustomerHomePage extends StatelessWidget {
  const CustomerHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => CustomerHomeCubit()..load(),
      child: BlocListener<AppSessionCubit, AppSessionState>(
        listenWhen: (prev, curr) => prev.locale != curr.locale,
        listener: (context, session) {
          context.read<CustomerHomeCubit>().load(forceNetwork: true);
        },
        child: const _CustomerHomeView(),
      ),
    );
  }
}

class _CustomerHomeView extends StatefulWidget {
  const _CustomerHomeView();

  @override
  State<_CustomerHomeView> createState() => _CustomerHomeViewState();
}

class _CustomerHomeViewState extends State<_CustomerHomeView>
    with SingleTickerProviderStateMixin, RefreshWhenNavigatedTo {
  bool _locating = false;
  String? _selectedCategoryId; // null = 'All'
  bool _isMapExpanded = false;
  bool _isProgrammaticScroll = false;
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _mapExpandController;

  @override
  List<String> get refreshRoutePaths => [RouteNames.customerHome];

  @override
  void onScreenRefresh() {
    context.read<CustomerHomeCubit>().load(forceNetwork: true);
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _mapExpandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _mapExpandController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isProgrammaticScroll) return;
    if (_scrollController.hasClients &&
        _scrollController.offset > 20 &&
        _isMapExpanded) {
      setState(() => _isMapExpanded = false);
      _mapExpandController.reverse();
    }
  }

  String get _locationLabel {
    final label = AppLocation.instance.addressLabel?.trim();
    if (label != null && label.isNotEmpty) return label;
    if (AppLocation.instance.hasFix) {
      return '${AppLocation.instance.lat!.toStringAsFixed(4)}, '
          '${AppLocation.instance.lng!.toStringAsFixed(4)}';
    }
    return 'Location not set';
  }

  Future<void> _refreshLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final ok = await LocationService.instance.ensureOnAppOpen(context);
      if (!mounted) return;
      if (!ok) {
        ToastUtils.showToast(
          context: context,
          message: 'Could not get current location',
        );
      }
      setState(() {});
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _onMapLocationTapped(MapCoordinate coord) async {
    // 1. Immediately move customer location to tapped coordinates
    AppLocation.instance.update(
      latitude: coord.lat,
      longitude: coord.lng,
      address: 'Updating location…',
    );
    setState(() {});

    // 2. Reverse geocode coordinates to friendly street address
    try {
      final addr = await LocationService.instance
          .reverseGeocode(coord.lat, coord.lng)
          .timeout(const Duration(seconds: 4), onTimeout: () => null);
      if (mounted) {
        AppLocation.instance.update(
          latitude: coord.lat,
          longitude: coord.lng,
          address: (addr != null && addr.isNotEmpty)
              ? addr
              : '${coord.lat.toStringAsFixed(4)}, ${coord.lng.toStringAsFixed(4)}',
        );
        setState(() {});
        context.read<CustomerHomeCubit>().load(forceNetwork: true);
      }
    } catch (_) {}
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _refreshLocation(),
      context.read<CustomerHomeCubit>().load(forceNetwork: true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = LocaleScope.of(context).locale;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusBarH = MediaQuery.of(context).padding.top;

    final userName =
        MockRepository.instance.currentUser?.name ?? l10n.guestUser;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: scheme.surface,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF080F1E),
        body: BlocBuilder<CustomerHomeCubit, CustomerHomeState>(
          builder: (context, state) {
            // Filter popular services if a category is selected
            final filteredServices = _selectedCategoryId == null
                ? state.popularServices
                : state.popularServices
                      .where(
                        (s) =>
                            s.categoryId.toLowerCase() ==
                            _selectedCategoryId!.toLowerCase(),
                      )
                      .toList();

            return AppRefreshIndicator(
              onRefresh: _refreshAll,
              // NestedScrollView body scrolls at depth 1 — required for pull-to-refresh.
              notificationPredicate: (notification) =>
                  notification.depth == 0 || notification.depth == 1,
              child: NestedScrollView(
                  controller: _scrollController,
                  headerSliverBuilder: (context, innerBoxIsScrolled) {
                    return [
                      AnimatedBuilder(
                        animation: _mapExpandController,
                        builder: (context, child) {
                          final curveValue = Curves.easeInOutCubic.transform(
                            _mapExpandController.value,
                          );
                          final currentHeight =
                              154.0 + (statusBarH + 390.0 - 154.0) * curveValue;

                          return SliverAppBar(
                            pinned: true,
                            expandedHeight: currentHeight,
                            toolbarHeight: 130,
                            backgroundColor: scheme.surface,
                            elevation: 0,
                            flexibleSpace: FlexibleSpaceBar(
                              collapseMode: CollapseMode.pin,
                              background: curveValue > 0.0
                                  ? ClipRect(
                                      child: Align(
                                        alignment: Alignment.bottomCenter,
                                        heightFactor: curveValue,
                                        child: _HomeMapHero(
                                          statusBarH: statusBarH,
                                          locating: _locating,
                                          onCurrentLocationTap:
                                              _refreshLocation,
                                          onMapTap: _onMapLocationTapped,
                                        ),
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            title: AnimatedOpacity(
                              opacity: _isMapExpanded ? 0.0 : 1.0,
                              duration: const Duration(milliseconds: 200),
                              child: IgnorePointer(
                                ignoring: _isMapExpanded,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    left: 0,
                                    right: 0,
                                    bottom: 8,
                                  ),
                                  child: _AppBarTitleContent(
                                    userName: userName,
                                    locationLabel: _locationLabel,
                                    locating: _locating,
                                    onLocationTap: _refreshLocation,
                                    onMapToggleTap: () {
                                      if (!_isMapExpanded) {
                                        _isProgrammaticScroll = true;
                                        setState(() {
                                          _isMapExpanded = true;
                                        });
                                        _mapExpandController.forward();
                                        // Scroll to top to ensure map is fully visible
                                        _scrollController
                                            .animateTo(
                                              0,
                                              duration: const Duration(
                                                milliseconds: 300,
                                              ),
                                              curve: Curves.easeOut,
                                            )
                                            .then((_) {
                                              _isProgrammaticScroll = false;
                                            });
                                      }
                                    },
                                    onNotificationsTap: () => context.push(
                                      RouteNames.sharedNotifications,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            bottom: PreferredSize(
                              preferredSize: const Size.fromHeight(24),
                              child: Container(
                                height: 24,
                                decoration: BoxDecoration(
                                  color: scheme.surface,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(24),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ];
                  },
                  // Continuous, unified single scroll view for the entire body
                  body: Container(
                    color: scheme.surface,
                    child: ListView(
                      padding: const EdgeInsets.only(top: 4, bottom: 36),
                      physics: appRefreshScrollPhysics,
                      children: [
                        // 1. Quick Search & AI Discovery Pill
                        _buildSearchBar(context),
                        const SizedBox(height: 18),

                        // 2. Categories Section
                        _buildCategoriesSection(context, state, l10n, locale),
                        const SizedBox(height: 20),

                        // 3. Emergency / Urgent Assistance Promo Banner
                        _buildEmergencyBanner(context),
                        const SizedBox(height: 14),

                        // 3b. Coupon Banner Carousel (from backend / admin)
                        if (state.banners.isNotEmpty)
                          _CouponBannerCarousel(banners: state.banners),
                        const SizedBox(height: 8),

                        // 4. Popular Services Header & Category Filter Chips
                        _buildPopularServicesHeader(
                          context,
                          state,
                          l10n,
                          locale,
                          filteredServices.length,
                        ),
                        const SizedBox(height: 14),

                        // 5. Popular Services Cards List
                        if (state.status == CustomerHomeStatus.loading &&
                            state.popularServices.isEmpty)
                          _buildShimmerList()
                        else if (filteredServices.isEmpty)
                          _buildEmptyServices(context)
                        else
                          for (int i = 0; i < filteredServices.length; i++)
                            _ServiceTile(
                              service: filteredServices[i],
                              locale: locale,
                              index: i,
                              onTap: () => context.push(
                                '/customer/service/${filteredServices[i].id}',
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. Search Bar Widget
  // ---------------------------------------------------------------------------
  Widget _buildSearchBar(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.goCustomerTab(1),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Search electrician, plumber, repairs…',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: theme.hintColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => context.goCustomerTab(2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          size: 13,
                          color: AppColors.accent,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'AI Help',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. Categories Section
  // ---------------------------------------------------------------------------
  Widget _buildCategoriesSection(
    BuildContext context,
    CustomerHomeState state,
    dynamic l10n,
    String locale,
  ) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.categories,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              InkWell(
                onTap: () => context.push(RouteNames.customerCategories),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.viewAll,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 11,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (state.categories.isNotEmpty)
            _CategoryGrid(
              categories: state.categories
                  .take(AppConstants.homeCategoryPreviewCount)
                  .toList(),
              locale: locale,
              onCategoryTap: context.openCategorySearch,
            )
          else
            _buildEmptyCategories(context),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. Instant Emergency Assistance Banner
  // ---------------------------------------------------------------------------
  Widget _buildEmergencyBanner(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF334155)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.sos_rounded,
              color: Color(0xFFF87171),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Emergency Booking',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Get verified professionals in 15–20 minutes',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => context.push(RouteNames.sharedSos),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Book Fast',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4. Popular Services Header & Category Filter Chips
  // ---------------------------------------------------------------------------
  Widget _buildPopularServicesHeader(
    BuildContext context,
    CustomerHomeState state,
    dynamic l10n,
    String locale,
    int servicesCount,
  ) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      l10n.popularServices,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (servicesCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$servicesCount',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              InkWell(
                onTap: () => context.goCustomerTab(2),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.smart_toy_outlined,
                        size: 14,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        l10n.aiHelper,
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Horizontal Category Filter Chips to declutter the service list
        if (state.categories.isNotEmpty)
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _FilterChip(
                  label: 'All Services',
                  icon: Icons.apps_rounded,
                  isSelected: _selectedCategoryId == null,
                  onTap: () => setState(() => _selectedCategoryId = null),
                ),
                for (final cat in state.categories)
                  _FilterChip(
                    label: cat.nameFor(locale),
                    icon: cat.icon,
                    isSelected: _selectedCategoryId == cat.id,
                    onTap: () => setState(() => _selectedCategoryId = cat.id),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyCategories(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.hairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.category_outlined, size: 32, color: context.muted),
          const SizedBox(height: 6),
          Text(
            'No categories available',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyServices(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.search_off_rounded,
              size: 32,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'No services found in this category',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Explore other categories or reset filter to see all services.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: Theme.of(context).hintColor,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: () => setState(() => _selectedCategoryId = null),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Show All Services'),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerList() {
    return Column(
      children: const [
        _ShimmerServiceTile(),
        _ShimmerServiceTile(),
        _ShimmerServiceTile(),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Coupon Banner Carousel (Backend-driven, Admin-controlled)
// ---------------------------------------------------------------------------
class _CouponBannerCarousel extends StatefulWidget {
  const _CouponBannerCarousel({required this.banners});

  final List<CouponBanner> banners;

  @override
  State<_CouponBannerCarousel> createState() => _CouponBannerCarouselState();
}

class _CouponBannerCarouselState extends State<_CouponBannerCarousel> {
  static const int _kLoopMultiplier = 10000;
  late PageController _pageController;
  int _currentPage = 0;
  Timer? _autoScrollTimer;

  @override
  void initState() {
    super.initState();
    final initialPage = widget.banners.length > 1
        ? widget.banners.length * (_kLoopMultiplier ~/ 2)
        : 0;
    _pageController = PageController(
      viewportFraction: 0.91,
      initialPage: initialPage,
    );
    _startAutoScroll();
  }

  @override
  void didUpdateWidget(covariant _CouponBannerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.banners.length != widget.banners.length) {
      _startAutoScroll();
    }
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    if (widget.banners.length <= 1) return;
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.nextPage(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Color _parseHex(String hex) {
    try {
      final h = hex.replaceAll('#', '');
      final full = h.length == 6 ? 'FF$h' : h;
      return Color(int.parse(full, radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  bool _isExpiringSoon(DateTime? validUntil) {
    if (validUntil == null) return false;
    return validUntil.difference(DateTime.now()).inDays <= 3;
  }

  String _formatExpiry(DateTime? validUntil) {
    if (validUntil == null) return '';
    final days = validUntil.difference(DateTime.now()).inDays;
    if (days <= 0) return 'Expires today!';
    if (days == 1) return 'Expires tomorrow!';
    if (days <= 7) return 'Expires in $days days';
    return 'Valid till ${DateFormat('d MMM').format(validUntil)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 10),
          child: Row(
            children: [
              const Icon(
                Icons.local_offer_rounded,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'Exclusive Offers & Coupons',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  letterSpacing: -0.2,
                ),
              ),
              const Spacer(),
              if (widget.banners.length > 1)
                Text(
                  '${_currentPage + 1}/${widget.banners.length}',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.hintColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 140,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (rawIndex) {
              if (widget.banners.isEmpty) return;
              final index = rawIndex % widget.banners.length;
              if (_currentPage != index) {
                setState(() => _currentPage = index);
              }
            },
            itemCount: widget.banners.length > 1 ? null : widget.banners.length,
            itemBuilder: (context, rawIndex) {
              final index = widget.banners.isNotEmpty
                  ? rawIndex % widget.banners.length
                  : 0;
              final banner = widget.banners[index];
              final startColor = _parseHex(
                banner.gradientColors.isNotEmpty
                    ? banner.gradientColors.first
                    : '#1E3A8A',
              );
              final endColor = _parseHex(
                banner.gradientColors.length > 1
                    ? banner.gradientColors.last
                    : '#3B82F6',
              );
              final expiringSoon = _isExpiringSoon(banner.validUntil);
              final expiryLabel = _formatExpiry(banner.validUntil);

              return GestureDetector(
                onTap: () => _showCouponDialog(context, banner),
                child: Container(
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [startColor, endColor],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: startColor.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -20,
                        top: -20,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.07),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 40,
                        bottom: -30,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.2,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.confirmation_num_rounded,
                                              size: 10,
                                              color: Colors.white,
                                            ),
                                            SizedBox(width: 3),
                                            Text(
                                              'COUPON',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.8,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (expiringSoon) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(
                                              0xFFFEF3C7,
                                            ).withValues(alpha: 0.25),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.timer_rounded,
                                                size: 10,
                                                color: Color(0xFFFDE68A),
                                              ),
                                              SizedBox(width: 3),
                                              Text(
                                                'ENDING SOON',
                                                style: TextStyle(
                                                  color: Color(0xFFFDE68A),
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    banner.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14.5,
                                      height: 1.2,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (banner.description.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      banner.description,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.8,
                                        ),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w400,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  if (expiryLabel.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      expiryLabel,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.65,
                                        ),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    banner.discount,
                                    style: TextStyle(
                                      color: startColor,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                GestureDetector(
                                  onTap: () {
                                    Clipboard.setData(
                                      ClipboardData(text: banner.code),
                                    );
                                    ToastUtils.showToast(
                                      context: context,
                                      message: '✅ Code ${banner.code} copied!',
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.35,
                                        ),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          banner.code,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.copy_rounded,
                                          size: 11,
                                          color: Colors.white70,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (widget.banners.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.banners.length, (i) {
              final isActive = i == _currentPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: isActive ? 20 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.primary
                      : theme.hintColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }

  void _showCouponDialog(BuildContext context, CouponBanner banner) {
    final startColor = _parseHex(
      banner.gradientColors.isNotEmpty
          ? banner.gradientColors.first
          : '#1E3A8A',
    );
    final endColor = _parseHex(
      banner.gradientColors.length > 1 ? banner.gradientColors.last : '#3B82F6',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            24,
            20,
            24 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [startColor, endColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.local_offer_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          banner.discount,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          banner.title,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (banner.description.isNotEmpty) ...[
              Text(
                banner.description,
                style: Theme.of(
                  ctx,
                ).textTheme.bodyMedium?.copyWith(height: 1.4),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: Theme.of(ctx).hintColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Min. order ₹${banner.minOrderValue.toInt()}  •  Max discount ₹${banner.maxDiscount.toInt()}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(ctx).hintColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: banner.code));
                Navigator.pop(ctx);
                ToastUtils.showToast(
                  context: context,
                  message: '✅ Code ${banner.code} copied to clipboard!',
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: startColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: startColor.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      banner.code,
                      style: TextStyle(
                        color: startColor,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.copy_rounded,
                          size: 13,
                          color: Theme.of(ctx).hintColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Tap to copy code',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(ctx).hintColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: banner.code));
                Navigator.pop(ctx);
                ToastUtils.showToast(
                  context: context,
                  message: '✅ Code copied! Apply at checkout.',
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: startColor,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Copy & Use Coupon',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter Chip Component
// ---------------------------------------------------------------------------
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : theme.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color: isSelected ? Colors.white : theme.hintColor,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected
                      ? Colors.white
                      : theme.textTheme.bodyMedium?.color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// App Bar Title Content
// ---------------------------------------------------------------------------
class _AppBarTitleContent extends StatelessWidget {
  const _AppBarTitleContent({
    required this.userName,
    required this.locationLabel,
    required this.locating,
    required this.onLocationTap,
    required this.onMapToggleTap,
    required this.onNotificationsTap,
  });

  final String userName;
  final String locationLabel;
  final bool locating;
  final VoidCallback onLocationTap;
  final VoidCallback onMapToggleTap;
  final VoidCallback onNotificationsTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.timeGreeting(DateTime.now().hour),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    userName,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: onLocationTap,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            color: AppColors.primary400,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              locationLabel,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface.withValues(alpha: 0.95),
                              ),
                            ),
                          ),
                          if (locating) ...[
                            const SizedBox(width: 8),
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: AppColors.primary400,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: Border.all(
                  color: scheme.onSurface.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              child: IconButton(
                icon: Icon(
                  Icons.notifications_outlined,
                  color: scheme.onSurface,
                  size: 22,
                ),
                tooltip: l10n.notifications,
                onPressed: onNotificationsTap,
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Center(
          child: GestureDetector(
            onVerticalDragUpdate: (details) {
              // Open map if pulled down intentionally
              if (details.primaryDelta != null && details.primaryDelta! > 2.0) {
                onMapToggleTap();
              }
            },
            child: InkWell(
              onTap: onMapToggleTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'see map',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: scheme.onSurface.withValues(alpha: 0.75),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Interactive Map Hero
// ---------------------------------------------------------------------------
class _HomeMapHero extends StatelessWidget {
  const _HomeMapHero({
    required this.statusBarH,
    required this.locating,
    required this.onCurrentLocationTap,
    required this.onMapTap,
  });

  final double statusBarH;
  final bool locating;
  final VoidCallback onCurrentLocationTap;
  final ValueChanged<MapCoordinate> onMapTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final center = MapConstants.current;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (center != null)
          FixlyMapView(
            expand: true,
            borderRadius: BorderRadius.zero,
            center: center,
            zoom: 15.5,
            showDestinationPin: false,
            showStartPin: false,
            showUserLocation: true,
            claimGestures: true,
            showZoomControls: true,
            showRecenterButton: true,
            show3DControl: true,
            showCompassButton: true,
            showMovementControls: false,
            controlsBottomPadding: 34.0,
            onMapTap: onMapTap,
          )
        else
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onCurrentLocationTap,
            child: Container(
              color: const Color(0xFF0A1428),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.location_searching,
                      size: 32,
                      color: AppColors.primary400.withValues(alpha: 0.7),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap to detect your location',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Gradient for status bar legibility
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: statusBarH + 76,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    scheme.surface.withValues(alpha: 0.65),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),

        // Current Location button
        Positioned(
          top: statusBarH + 82,
          left: 14,
          child: Material(
            color: scheme.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(20),
            elevation: 3,
            shadowColor: Colors.black.withValues(alpha: 0.2),
            child: InkWell(
              onTap: onCurrentLocationTap,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (locating)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: AppColors.primary,
                        ),
                      )
                    else
                      const Icon(
                        Icons.my_location_rounded,
                        size: 15,
                        color: AppColors.primary,
                      ),
                    const SizedBox(width: 5),
                    Text(
                      'Current Location',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Category Grid
// ---------------------------------------------------------------------------
class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({
    required this.categories,
    required this.locale,
    required this.onCategoryTap,
  });

  final List<ServiceCategory> categories;
  final String locale;
  final ValueChanged<String> onCategoryTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int index = 0; index < categories.length; index++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: CategoryIconTile(
                category: categories[index],
                locale: locale,
                onTap: () => onCategoryTap(categories[index].id),
              ).appListEnter(context, index: index, id: categories[index].id),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Redesigned, Spacious Service Tile (Decluttered, Modern & High-Contrast)
// ---------------------------------------------------------------------------
class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.service,
    required this.locale,
    required this.index,
    required this.onTap,
  });

  final ServiceItem service;
  final String locale;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = service.titleFor(locale);
    final description = service.descriptionFor(locale);
    final hasImage =
        service.imageUrl != null && service.imageUrl!.trim().isNotEmpty;
    final estimatedTime = service.estimatedTime?.trim();
    final catColor = _serviceCategoryColor(service.categoryId);
    final catIcon = _serviceCategoryIcon(service.categoryId);
    final localizedCat = localizeCategory(service.categoryId, locale);
    final catName = localizedCat.isNotEmpty
        ? localizedCat
        : _formatCategoryName(service.categoryId);

    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Spacious Thumbnail (84x84)
                ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: catColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: hasImage
                        ? Image.network(
                            service.imageUrl!.trim(),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Center(
                              child: Icon(catIcon, color: catColor, size: 36),
                            ),
                            loadingBuilder: (_, child, progress) {
                              if (progress == null) return child;
                              return Center(
                                child: Icon(
                                  catIcon,
                                  color: catColor.withValues(alpha: 0.6),
                                  size: 32,
                                ),
                              );
                            },
                          )
                        : Center(
                            child: Icon(catIcon, color: catColor, size: 36),
                          ),
                  ),
                ),
                const SizedBox(width: 14),

                // 2. Info Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category tag & Rating Pill
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color: catColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(catIcon, size: 11, color: catColor),
                                const SizedBox(width: 4),
                                Text(
                                  catName,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: catColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  size: 12,
                                  color: Color(0xFFD97706),
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  service.rating > 0
                                      ? service.rating.toStringAsFixed(1)
                                      : 'New',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF92400E),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Service Title
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 15.5,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),

                      // Short Summary / What's Included
                      Text(
                        description.isNotEmpty
                            ? description
                            : (service.whatsIncluded.isNotEmpty
                                  ? service.whatsIncluded.first
                                  : 'Verified professional service'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.hintColor,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Bottom Row: Duration + Price + Book Action
                      Row(
                        children: [
                          if (estimatedTime != null &&
                              estimatedTime.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    size: 11,
                                    color: theme.hintColor,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    estimatedTime,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w500,
                                      color: theme.hintColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const Spacer(),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '₹${service.priceFrom.toInt()}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Book',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(width: 2),
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 12,
                                  color: Colors.white,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).appListEnter(context, index: index, id: service.id);
  }
}

// ---------------------------------------------------------------------------
// Helpers for Category Icons & Colors
// ---------------------------------------------------------------------------
IconData _serviceCategoryIcon(String? categoryId) {
  if (categoryId == null) return Icons.handyman_rounded;
  final c = categoryId.toLowerCase();
  if (c.contains('elect')) return Icons.bolt_rounded;
  if (c.contains('plumb')) return Icons.plumbing_rounded;
  if (c.contains('tech') || c.contains('appliance')) return Icons.build_rounded;
  if (c.contains('carpen')) return Icons.carpenter_rounded;
  if (c.contains('paint')) return Icons.format_paint_rounded;
  if (c.contains('care') || c.contains('nurse')) return Icons.favorite_rounded;
  if (c.contains('clean')) return Icons.cleaning_services_rounded;
  if (c.contains('garden')) return Icons.yard_rounded;
  return Icons.handyman_rounded;
}

Color _serviceCategoryColor(String? categoryId) {
  if (categoryId == null) return AppColors.primary;
  final c = categoryId.toLowerCase();
  if (c.contains('elect')) return const Color(0xFFEAB308);
  if (c.contains('plumb')) return const Color(0xFF0284C7);
  if (c.contains('tech') || c.contains('appliance'))
    return const Color(0xFF6366F1);
  if (c.contains('carpen')) return const Color(0xFFD97706);
  if (c.contains('paint')) return const Color(0xFF8B5CF6);
  if (c.contains('care') || c.contains('nurse')) return const Color(0xFFEC4899);
  if (c.contains('clean')) return const Color(0xFF10B981);
  if (c.contains('garden')) return const Color(0xFF16A34A);
  return AppColors.primary;
}

String _formatCategoryName(String? categoryId) {
  if (categoryId == null || categoryId.isEmpty) return 'Service';
  return categoryId
      .split('_')
      .map(
        (word) => word.isNotEmpty
            ? '${word[0].toUpperCase()}${word.substring(1)}'
            : '',
      )
      .join(' ');
}

// ---------------------------------------------------------------------------
// Shimmer Loading Tile
// ---------------------------------------------------------------------------
class _ShimmerServiceTile extends StatefulWidget {
  const _ShimmerServiceTile();

  @override
  State<_ShimmerServiceTile> createState() => _ShimmerServiceTileState();
}

class _ShimmerServiceTileState extends State<_ShimmerServiceTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: 0.4 + (_controller.value * 0.6),
          child: Container(
            margin: const EdgeInsets.only(left: 16, right: 16, bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 70,
                            height: 16,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            width: 40,
                            height: 16,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 140,
                        height: 16,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        height: 12,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Container(
                            width: 60,
                            height: 14,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            width: 70,
                            height: 22,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

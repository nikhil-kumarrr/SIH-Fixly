import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/l10n/category_localizer.dart';
import '../../../../core/navigation/customer_navigation.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../../shared/models/models.dart';
import '../../../auth/presentation/cubit/app_session_cubit.dart';
import '../cubit/search_cubit.dart';

class CustomerSearchPage extends StatelessWidget {
  const CustomerSearchPage({super.key, this.categoryId, this.showBack = false});

  final String? categoryId;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) {
        final cubit = SearchCubit();
        if (categoryId != null && categoryId!.isNotEmpty) {
          cubit.filterByCategory(categoryId!);
        } else {
          cubit.search('');
        }
        return cubit;
      },
      child: BlocListener<AppSessionCubit, AppSessionState>(
        listenWhen: (prev, curr) => prev.locale != curr.locale,
        listener: (context, session) {
          context.read<SearchCubit>().refresh();
        },
        child: _CustomerSearchView(categoryId: categoryId, showBack: showBack),
      ),
    );
  }
}

class _CustomerSearchView extends StatefulWidget {
  const _CustomerSearchView({this.categoryId, required this.showBack});

  final String? categoryId;
  final bool showBack;

  @override
  State<_CustomerSearchView> createState() => _CustomerSearchViewState();
}

class _CustomerSearchViewState extends State<_CustomerSearchView> {
  late final TextEditingController _searchController;
  Timer? _debounceTimer;
  String? _activeCategory;

  @override
  void initState() {
    super.initState();
    _activeCategory = widget.categoryId;
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  ServiceCategory? get _matchedCategory {
    final id = _activeCategory?.toLowerCase().trim();
    if (id == null || id.isEmpty) return null;
    for (final cat in ServiceCategories.all) {
      if (cat.id == id ||
          cat.nameEn.toLowerCase() == id ||
          id.contains(cat.id)) {
        return cat;
      }
    }
    return null;
  }

  String get _categoryTitle {
    final cat = _matchedCategory;
    if (cat != null) return cat.nameFor(context.l10n.locale);
    final id = _activeCategory ?? widget.categoryId;
    if (id == null || id.isEmpty) return context.l10n.search;
    return id[0].toUpperCase() + id.substring(1);
  }

  void _onCategorySelected(String? categoryId) {
    setState(() {
      _activeCategory = categoryId;
    });
    _searchController.clear();
    _debounceTimer?.cancel();
    if (categoryId != null && categoryId.isNotEmpty) {
      context.read<SearchCubit>().filterByCategory(categoryId);
    } else {
      context.read<SearchCubit>().search('');
    }
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      if (value.trim().isNotEmpty && _activeCategory != null) {
        setState(() => _activeCategory = null);
      }
      context.read<SearchCubit>().search(value);
    });
  }

  void _onSearchSubmitted(String value) {
    _debounceTimer?.cancel();
    if (value.trim().isNotEmpty && _activeCategory != null) {
      setState(() => _activeCategory = null);
    }
    context.read<SearchCubit>().search(value);
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {});
    _debounceTimer?.cancel();
    if (_activeCategory != null && _activeCategory!.isNotEmpty) {
      context.read<SearchCubit>().filterByCategory(_activeCategory!);
    } else {
      context.read<SearchCubit>().search('');
    }
  }

  Future<void> _onRefresh() async {
    await context.read<SearchCubit>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = l10n.locale;
    final theme = Theme.of(context);

    return AppScaffold(
      title: _categoryTitle,
      showBack: widget.showBack,
      body: AppRefreshIndicator(
        onRefresh: _onRefresh,
        child: CustomScrollView(
          physics: appRefreshScrollPhysics,
          slivers: [
            // Top breathing room between AppBar and body
            const SliverToBoxAdapter(child: SizedBox(height: 14)),

            // 1. Search Bar Header
            SliverToBoxAdapter(child: _buildSearchBar(context, theme)),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),

            // 2. Quick Category Filter Pills
            SliverToBoxAdapter(child: _buildCategoryFilterBar(context, locale)),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),

            // 3. Trust & Quality Assurance Banner
            SliverToBoxAdapter(child: _buildTrustBanner(context, theme)),
            const SliverToBoxAdapter(child: SizedBox(height: 18)),

            // 4. Top-Matching & Nearest Specialists Section
            SliverToBoxAdapter(
              child: BlocBuilder<SearchCubit, SearchState>(
                builder: (context, state) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.stars_rounded,
                                size: 18,
                                color: AppColors.accentDark,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Top Matching Specialists',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                    'Ranked by rating, skill relevance & proximity',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: context.muted,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (state.nearbyWorkers.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${state.nearbyWorkers.length} Available',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.success,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (state.isLoadingWorkers)
                        SizedBox(
                          height: 175,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: 2,
                            itemBuilder: (context, index) => Padding(
                              padding: EdgeInsets.only(
                                right: index == 1 ? 0 : 12,
                              ),
                              child: const _WorkerSkeletonCard(),
                            ),
                          ),
                        )
                      else if (state.nearbyWorkers.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 16,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: context.hairline),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: AppColors.warning.withValues(
                                          alpha: 0.15,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.location_off_outlined,
                                        size: 24,
                                        color: AppColors.warning,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            state.workersEmptyCode ==
                                                    'NO_WORKERS_FOUND'
                                                ? 'No professionals nearby'
                                                : 'No specialists found',
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            state.workersEmptyMessage
                                                        ?.trim()
                                                        .isNotEmpty ==
                                                    true
                                                ? state.workersEmptyMessage!
                                                : 'No available professionals found within ${state.searchRadiusKm ?? 20} km. Please try again shortly or select a different category.',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: context.muted,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () =>
                                        context.read<SearchCubit>().refresh(),
                                    icon: const Icon(
                                      Icons.refresh_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Try again'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        SizedBox(
                          height: 200,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount:
                                state.nearbyWorkers.length +
                                (state.isLoadingMoreWorkers ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index >= state.nearbyWorkers.length) {
                                return const Padding(
                                  padding: EdgeInsets.only(left: 12),
                                  child: _WorkerSkeletonCard(),
                                );
                              }
                              final worker = state.nearbyWorkers[index];
                              final serviceId = state.results.isNotEmpty
                                  ? state.results.first.id
                                  : '';
                              if (index >= state.nearbyWorkers.length - 2) {
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (context.mounted) {
                                    context
                                        .read<SearchCubit>()
                                        .loadMoreWorkers();
                                  }
                                });
                              }
                              return Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: _WorkerCard(
                                  worker: worker,
                                  targetCategory:
                                      _activeCategory ??
                                      widget.categoryId ??
                                      state.categoryId ??
                                      '',
                                  onTap: () => context.push(
                                    '/customer/worker/${worker.id}'
                                    '?serviceId=${Uri.encodeComponent(serviceId)}'
                                    '&category=${Uri.encodeComponent(_activeCategory ?? widget.categoryId ?? state.categoryId ?? '')}',
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 20),
                    ],
                  );
                },
              ),
            ),

            // 5. Category Services Section Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: BlocBuilder<SearchCubit, SearchState>(
                  builder: (context, state) {
                    final title = _activeCategory != null
                        ? '$_categoryTitle Packages'
                        : 'Available Services';
                    return Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.home_repair_service_rounded,
                            size: 18,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (state.results.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${state.results.length} Services',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: theme.hintColor,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),

            // 6. Services List / Empty state
            BlocBuilder<SearchCubit, SearchState>(
              builder: (context, state) {
                if (state.isSearching) {
                  return const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (state.results.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 36,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.search_off_rounded,
                                size: 40,
                                color: context.muted,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              _searchController.text.isNotEmpty
                                  ? 'No services matching "${_searchController.text}"'
                                  : l10n.noServicesFound,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Try searching with another keyword or pick a different category.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: context.muted,
                              ),
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: () {
                                _clearSearch();
                                _onCategorySelected(null);
                              },
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('Reset All Filters'),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final service = state.results[index];
                      return _ServicePackageTile(
                        service: service,
                        locale: locale,
                        onTap: () =>
                            context.push('/customer/service/${service.id}'),
                      ).appListEnter(context, index: index, id: service.id);
                    }, childCount: state.results.length),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, ThemeData theme) {
    final hasQuery = _searchController.text.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          const Icon(Icons.search_rounded, color: AppColors.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              onSubmitted: _onSearchSubmitted,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: _activeCategory != null
                    ? 'Search in $_categoryTitle...'
                    : 'Search electrician, plumber, repairs...',
                hintStyle: TextStyle(
                  fontSize: 13.5,
                  color: theme.hintColor,
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (hasQuery)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              color: theme.hintColor,
              splashRadius: 18,
              onPressed: _clearSearch,
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => context.goCustomerTab(2),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          AppConstants.voiceAiEnabled
                              ? Icons.mic_rounded
                              : Icons.chat_bubble_rounded,
                          size: 14,
                          color: AppColors.accentDark,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'Fixly AI',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accentDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilterBar(BuildContext context, String locale) {
    final isAllSelected = _activeCategory == null || _activeCategory!.isEmpty;

    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _CategoryPill(
            label: 'All Services',
            icon: Icons.grid_view_rounded,
            isSelected: isAllSelected,
            onTap: () => _onCategorySelected(null),
          ),
          const SizedBox(width: 8),
          ...ServiceCategories.all.map((cat) {
            final isSelected = _activeCategory?.toLowerCase().trim() == cat.id;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _CategoryPill(
                label: cat.nameFor(locale),
                icon: cat.icon,
                isSelected: isSelected,
                onTap: () => _onCategorySelected(isSelected ? null : cat.id),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTrustBanner(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.14)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.verified_rounded,
                size: 14,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Background-verified specialists • Fixed transparent pricing',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w600,
                  fontSize: 11.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// CATEGORY FILTER PILL
// -------------------------------------------------------------
class _CategoryPill extends StatelessWidget {
  const _CategoryPill({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: isSelected ? AppColors.primary : theme.cardColor,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : scheme.outlineVariant.withValues(alpha: 0.5),
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
              Icon(
                icon,
                size: 15,
                color: isSelected ? Colors.white : AppColors.primary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
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

// -------------------------------------------------------------
// WORKER CARD WIDGET (Rich, High-rated, Distance, Skill Badges)
// -------------------------------------------------------------
class _WorkerCard extends StatelessWidget {
  const _WorkerCard({
    required this.worker,
    required this.targetCategory,
    required this.onTap,
  });

  final WorkerProfile worker;
  final String targetCategory;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final normalizedCategory = targetCategory.toLowerCase().trim();

    return Container(
      width: 270,

      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.hairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Row: Avatar + Name + Rating
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.primary,
                              width: 1.5,
                            ),
                          ),
                          child: ClipOval(
                            child:
                                (worker.avatarUrl != null &&
                                    worker.avatarUrl!.isNotEmpty)
                                ? Image.network(
                                    worker.avatarUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const Icon(
                                              Icons.person_rounded,
                                              size: 26,
                                              color: AppColors.primary,
                                            ),
                                  )
                                : const Icon(
                                    Icons.person_rounded,
                                    size: 26,
                                    color: AppColors.primary,
                                  ),
                          ),
                        ),
                        if (worker.isVerified)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: AppColors.success,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check,
                                size: 10,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            worker.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (worker.title != null && worker.title!.isNotEmpty)
                            Text(
                              worker.title!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: context.muted),
                            ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.accent.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      size: 13,
                                      color: AppColors.accentDark,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      worker.rating > 0
                                          ? worker.rating.toStringAsFixed(1)
                                          : 'New',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.accentDark,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${worker.jobsCompleted} jobs',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: context.muted),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Distance & Rate row
                Row(
                  children: [
                    if (worker.distanceKm != null) ...[
                      const Icon(
                        Icons.near_me_rounded,
                        size: 13,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        worker.distanceFormatted ??
                            '${worker.distanceKm} km away',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                    ] else ...[
                      const Icon(
                        Icons.bolt_rounded,
                        size: 14,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        'Fast dispatch',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: context.muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                    ],
                    Text(
                      worker.rateFormatted ??
                          (worker.hourlyRate != null
                              ? '₹${worker.hourlyRate!.toInt()} base price'
                              : 'Top Rated'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Skills matching chips
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children:
                      (worker.skills.isNotEmpty
                              ? worker.skills.take(3)
                              : ['General Service', 'Verified'])
                          .map((skill) {
                            final isMatching =
                                normalizedCategory.isNotEmpty &&
                                (skill.toLowerCase().contains(
                                      normalizedCategory,
                                    ) ||
                                    normalizedCategory.contains(
                                      skill.toLowerCase(),
                                    ));

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isMatching
                                    ? AppColors.primary.withValues(alpha: 0.1)
                                    : (context.isDark
                                          ? Colors.white10
                                          : const Color(0xfff1f5f9)),
                                borderRadius: BorderRadius.circular(6),
                                border: isMatching
                                    ? Border.all(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.3,
                                        ),
                                      )
                                    : null,
                              ),
                              child: Text(
                                localizeCategory(skill, context.l10n.locale),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: isMatching
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isMatching
                                      ? AppColors.primary
                                      : (context.isDark
                                            ? Colors.white70
                                            : Colors.black87),
                                ),
                              ),
                            );
                          })
                          .toList(),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      worker.isAvailable && worker.isOnline
                          ? Icons.circle
                          : Icons.circle_outlined,
                      size: 10,
                      color: worker.isAvailable && worker.isOnline
                          ? AppColors.success
                          : context.muted,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      worker.isAvailable && worker.isOnline
                          ? 'Available now'
                          : 'Currently unavailable',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: worker.isAvailable && worker.isOnline
                            ? AppColors.success
                            : context.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkerSkeletonCard extends StatelessWidget {
  const _WorkerSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      highlightColor: Theme.of(context).colorScheme.surface,
      child: Container(
        width: 260,
        height: 175,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// SERVICE PACKAGE TILE (With Image, Details & Action)
// -------------------------------------------------------------
class _ServicePackageTile extends StatelessWidget {
  const _ServicePackageTile({
    required this.service,
    required this.locale,
    required this.onTap,
  });

  final ServiceItem service;
  final String locale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasImage =
        service.imageUrl != null && service.imageUrl!.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Service Image / Icon
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  colors: AppColors.primaryGradient,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: hasImage
                    ? Image.network(
                        service.imageUrl!.trim(),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(
                              Icons.home_repair_service_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const Center(
                            child: Icon(
                              Icons.home_repair_service_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          );
                        },
                      )
                    : const Icon(
                        Icons.home_repair_service_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
              ),
            ),
            const SizedBox(width: 14),

            // Service details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service.titleFor(locale),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    service.descriptionFor(locale),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'From ₹${service.priceFrom.toInt()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      if (service.estimatedTime != null &&
                          service.estimatedTime!.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: (context.isDark
                                  ? Colors.white10
                                  : const Color(0xfff1f5f9)),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.access_time_rounded,
                                  size: 11,
                                  color: AppColors.outline,
                                ),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    service.estimatedTime!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.outline,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, color: AppColors.outline),
          ],
        ),
      ),
    );
  }
}

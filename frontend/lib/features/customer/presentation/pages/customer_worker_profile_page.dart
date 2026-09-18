import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router/route_names.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/network/api_config.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/l10n/category_localizer.dart';
import '../../../../shared/models/models.dart';
import '../../../shared/presentation/widgets/service_scope_widgets.dart';
import '../../../workers/data/workers_api_repository.dart';

class CustomerWorkerProfilePage extends StatefulWidget {
  const CustomerWorkerProfilePage({
    required this.workerId,
    this.serviceId,
    super.key,
  });

  final String workerId;
  final String? serviceId;

  @override
  State<CustomerWorkerProfilePage> createState() =>
      _CustomerWorkerProfilePageState();
}

class _CustomerWorkerProfilePageState extends State<CustomerWorkerProfilePage> {
  late Future<WorkerProfile> _future;

  @override
  void initState() {
    super.initState();
    _loadWorker();
  }

  final List<WorkerReview> _extraReviews = [];
  int _reviewsPage = 1;
  bool _hasMoreReviews = false;
  bool _loadingMoreReviews = false;
  WorkerProfile? _profileForReviews;

  void _loadWorker() {
    _extraReviews.clear();
    _reviewsPage = 1;
    _hasMoreReviews = false;
    _loadingMoreReviews = false;
    _profileForReviews = null;
    _future = WorkersApiRepository().fetchWorker(widget.workerId).then((w) {
      _hasMoreReviews = w.reviewCount > w.reviews.length;
      _profileForReviews = w;
      return w;
    });
  }

  bool _canLoadMoreReviews(WorkerProfile worker) {
    final displayCount = worker.reviews.length + _extraReviews.length;
    final total = worker.reviewCount > 0 ? worker.reviewCount : displayCount;
    return _hasMoreReviews || total > displayCount;
  }

  bool _onReviewsScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification is! ScrollUpdateNotification &&
        notification is! OverscrollNotification &&
        notification is! ScrollEndNotification &&
        notification is! ScrollMetricsNotification) {
      return false;
    }
    final worker = _profileForReviews;
    if (worker == null || _loadingMoreReviews || !_canLoadMoreReviews(worker)) {
      return false;
    }
    // Near bottom (or content still short) → fetch next page.
    if (notification.metrics.extentAfter < 320) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final w = _profileForReviews;
        if (w == null || _loadingMoreReviews || !_canLoadMoreReviews(w)) return;
        _loadMoreReviews(w);
      });
    }
    return false;
  }

  Future<void> _loadMoreReviews(WorkerProfile worker) async {
    if (_loadingMoreReviews || !_canLoadMoreReviews(worker)) return;
    setState(() => _loadingMoreReviews = true);
    try {
      final nextPage = _reviewsPage + 1;
      final res = await WorkersApiRepository().fetchWorkerReviews(
        worker.id,
        page: nextPage,
        limit: 5,
      );
      if (!mounted) return;
      setState(() {
        _reviewsPage = nextPage;
        final existingKeys = {
          ...worker.reviews.map((r) => r.id ?? '${r.reviewerName}_${r.createdAt}'),
          ..._extraReviews.map((r) => r.id ?? '${r.reviewerName}_${r.createdAt}'),
        };
        for (final r in res.reviews) {
          final key = r.id ?? '${r.reviewerName}_${r.createdAt}';
          if (!existingKeys.contains(key)) {
            _extraReviews.add(r);
            existingKeys.add(key);
          }
        }
        _hasMoreReviews = res.hasMore;
        _loadingMoreReviews = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMoreReviews = false);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loadWorker();
    });
    await _future;
  }

  Future<void> _onBookPressed(WorkerProfile worker) async {
    final minPriceText = worker.rateFormatted ??
        (worker.hourlyRate != null
            ? '₹${worker.hourlyRate!.toStringAsFixed(0)}'
            : (worker.minimumCharge != null
                ? '₹${worker.minimumCharge!.toStringAsFixed(0)}'
                : '₹199'));

    final agreed = await _showBookingPolicySheet(context, worker, minPriceText);
    if (agreed != true || !mounted) return;

    context.push(
      '${RouteNames.customerBooking}?workerId=${worker.id}'
      '&serviceId=${Uri.encodeComponent(widget.serviceId ?? '')}'
      '&category=${Uri.encodeComponent(worker.category ?? '')}',
    );
  }

  Future<bool?> _showBookingPolicySheet(
    BuildContext context,
    WorkerProfile worker,
    String minPriceText,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (sheetContext) {
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.paddingOf(sheetContext).bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: scheme.outline.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Title and policy icon
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.shield_outlined,
                        color: scheme.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Important Booking Policy',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Visiting & Inspection Terms',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.hintColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Highlighted Visiting / Minimum Charge Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.payments_outlined,
                          color: scheme.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Visiting & Diagnosis Charge',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: scheme.primary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              minPriceText,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: scheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Base Fee',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Policy Explanation Points
                _buildPolicyItem(
                  context,
                  icon: Icons.home_repair_service_rounded,
                  title: 'On-Site Problem Diagnosis',
                  description:
                      'The professional will visit your location to inspect the issue firsthand and assess the required service work.',
                ),
                const SizedBox(height: 12),
                _buildPolicyItem(
                  context,
                  icon: Icons.price_check_rounded,
                  title: 'Upfront Quote Before Starting',
                  description:
                      'After checking the issue, the worker will explain what needs fixing and quote the total price (including any replacement parts and labor). Work begins only with your approval.',
                ),
                const SizedBox(height: 12),
                _buildPolicyItem(
                  context,
                  icon: Icons.info_outline_rounded,
                  iconColor: AppColors.secondary,
                  title: 'Cancellation / Inspection Charge',
                  description:
                      'If after the worker arrives and inspects the problem you choose not to proceed with the repair, this minimum base charge ($minPriceText) applies for their visit, time, and diagnosis.',
                ),
                const SizedBox(height: 12),
                _buildPolicyItem(
                  context,
                  icon: Icons.check_circle_outline_rounded,
                  iconColor: AppColors.success,
                  title: 'Adjusted in Total Invoice',
                  description:
                      'If you proceed with the service, this base charge is adjusted directly into your total final bill.',
                ),

                const SizedBox(height: 24),

                // Action buttons: "Cancel" and "I Agree, Continue"
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext, false),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          side: BorderSide(
                            color: scheme.outline.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(sheetContext, true),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          backgroundColor: scheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 2,
                        ),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text(
                          'I Agree, Continue',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPolicyItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    Color? iconColor,
  }) {
    final theme = Theme.of(context);
    final color = iconColor ?? theme.colorScheme.primary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.35,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WorkerProfile>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return AppScaffold(
            title: context.l10n.workerProfile,
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snap.hasError || !snap.hasData) {
          return AppScaffold(
            title: context.l10n.workerProfile,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person_off_rounded,
                        size: 38,
                        color: AppColors.error,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Worker Not Found',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snap.error?.toString().replaceAll('ApiException: ', '') ??
                          'Unable to load worker information.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).hintColor,
                          ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => context.pop(),
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          label: const Text('Go Back'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final worker = snap.data!;
        final locale = context.l10n.locale;
        final localizedSkills = localizeCategoryList(worker.skills, locale);
        final localizedCategory =
            localizeCategory(worker.category, locale);
        final skillLabel = localizedSkills.isEmpty
            ? (localizedCategory.isNotEmpty
                ? localizedCategory
                : 'Skilled Specialist')
            : localizedSkills.join(' • ');
        final aboutSkill = worker.skills.isEmpty
            ? (worker.category?.toLowerCase() ?? 'professional')
            : worker.skills.first.toLowerCase();
        final hasRatingHistory =
            worker.jobsCompleted > 0 || worker.reviewCount > 0;
        final kycLabel = switch (worker.kycStatus?.toLowerCase()) {
          'approved' => 'Identity verified',
          'submitted' || 'pending' || 'in_review' => 'Identity under review',
          _ => worker.isVerified ? 'Profile verified' : 'Verification pending',
        };

        return AppScaffold(
          title: context.l10n.workerProfile,
          padding: EdgeInsets.zero,
          bottomNavigationBar: _buildStickyBookingBar(context, worker),
          body: AppRefreshIndicator(
            onRefresh: _refresh,
            child: NotificationListener<ScrollNotification>(
              onNotification: _onReviewsScroll,
              child: ListView(
                physics: appRefreshScrollPhysics,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                // 1. Worker Hero Header Card with left-aligned avatar
                _buildHeroCard(context, worker, skillLabel)
                    .animate()
                    .fadeIn(duration: 250.ms)
                    .slideY(begin: 0.04, end: 0),

                const SizedBox(height: 14),

                // 2. High-level performance stat badges
                _buildStatsStrip(context, worker, hasRatingHistory)
                    .animate()
                    .fadeIn(delay: 80.ms),

                const SizedBox(height: 16),

                // 3. About Worker & Specialized Skills
                _buildAboutCard(context, worker, aboutSkill)
                    .animate()
                    .fadeIn(delay: 140.ms),

                const SizedBox(height: 16),

                // Cooperative Federation Affiliation
                if (worker.federationName != null && worker.federationName!.isNotEmpty) ...[
                  CooperativeFederationBadge(
                    federationName: worker.federationName!,
                  ).animate().fadeIn(delay: 160.ms),
                  const SizedBox(height: 16),
                ] else ...[
                  const CooperativeFederationBadge(
                    federationName: 'National Labour Cooperative Federation of India (NLCF)',
                  ).animate().fadeIn(delay: 160.ms),
                  const SizedBox(height: 16),
                ],

                // What is Included & Not Included (Reference Image 1)
                WhatIsIncludedCard(
                  primaryCategoryId: worker.category,
                  includedTasks: worker.includedTasks,
                  excludedTasks: worker.excludedTasks,
                ).animate().fadeIn(delay: 180.ms),

                const SizedBox(height: 16),

                // How it's Done (Reference Image 2)
                HowItsDoneCard(
                  primaryCategoryId: worker.category,
                ).animate().fadeIn(delay: 200.ms),

                const SizedBox(height: 16),

                // Frequently Asked Questions (Reference Image 2)
                ServiceFaqSection(
                  primaryCategoryId: worker.category,
                ).animate().fadeIn(delay: 220.ms),

                const SizedBox(height: 16),

                // 4. Trust, Safety & Verification
                _buildTrustCard(context, worker, kycLabel)
                    .animate()
                    .fadeIn(delay: 240.ms),

                if (worker.recentWorkPhotos.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildWorkPortfolioCard(context, worker)
                      .animate()
                      .fadeIn(delay: 250.ms),
                ],

                const SizedBox(height: 16),

                // 5. Customer Reviews & Ratings
                _buildReviewsCard(context, worker, hasRatingHistory)
                    .animate()
                    .fadeIn(delay: 260.ms),

                const SizedBox(height: 24),

                // 6. Inline Booking Call-to-Action button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () => _onBookPressed(worker),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.calendar_month_rounded, size: 20),
                    label: const Text(
                      'Book This Worker',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ).animate().fadeIn(delay: 300.ms),
              ],
            ),
            ),
          ),
        );
      },
    );
  }

  // --- Sticky Bottom Booking Bar ---
  Widget _buildStickyBookingBar(BuildContext context, WorkerProfile worker) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final rateText = worker.rateFormatted ??
        (worker.hourlyRate != null
            ? '₹${worker.hourlyRate!.toStringAsFixed(0)} base price'
            : (worker.minimumCharge != null
                ? 'From ₹${worker.minimumCharge!.toStringAsFixed(0)}'
                : 'Standard rate'));

    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPadding > 0 ? bottomPadding + 8 : 14),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.12),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Starting Rate',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).hintColor,
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  rateText,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: () => _onBookPressed(worker),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(120, 46),
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 2,
            ),
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text(
              'Book Now',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  // --- 1. Hero Header Card ---
  Widget _buildHeroCard(
    BuildContext context,
    WorkerProfile worker,
    String skillLabel,
  ) {
    final theme = Theme.of(context);
    final isOnline = worker.isOnline;

    return Material(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.14),
        ),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Image Avatar with Online Badge
            _buildAvatar(context, worker, size: 84),

            const SizedBox(width: 16),

            // Right Info Column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name and verified mark
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          worker.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: 19,
                          ),
                        ),
                      ),
                      if (worker.isVerified || worker.insured) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.verified_rounded,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 3),

                  // Trade / Title
                  Text(
                    worker.title?.isNotEmpty == true
                        ? worker.title!
                        : skillLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Online status and location chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: (isOnline ? AppColors.success : AppColors.outline)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: isOnline
                                    ? AppColors.success
                                    : AppColors.outline,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              isOnline ? 'Online now' : 'Offline',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isOnline
                                    ? AppColors.success
                                    : AppColors.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (worker.distanceKm != null ||
                          worker.distanceFormatted != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.location_on_rounded,
                              size: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              worker.distanceFormatted ??
                                  '${worker.distanceKm} km',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),

                  if (worker.hourlyRate != null ||
                      worker.rateFormatted != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      worker.rateFormatted ??
                          '₹${worker.hourlyRate!.toStringAsFixed(0)} base price',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Avatar Builder: Base64 / Network / Relative URL / Fallback ---
  Widget _buildAvatar(
    BuildContext context,
    WorkerProfile worker, {
    required double size,
  }) {
    final avatar = worker.avatarUrl?.trim();
    Widget imageWidget;

    if (avatar != null && avatar.isNotEmpty) {
      if (avatar.startsWith('data:image')) {
        try {
          final commaIndex = avatar.indexOf(',');
          final base64String =
              commaIndex != -1 ? avatar.substring(commaIndex + 1) : avatar;
          final bytes = base64Decode(base64String);
          imageWidget = Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _buildInitialsFallback(worker, size),
          );
        } catch (_) {
          imageWidget = _buildInitialsFallback(worker, size);
        }
      } else {
        final fullUrl = avatar.startsWith('http')
            ? avatar
            : '${ApiConfig.baseUrl}${avatar.startsWith('/') ? '' : '/'}$avatar';
        imageWidget = Image.network(
          fullUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _buildInitialsFallback(worker, size),
        );
      }
    } else {
      imageWidget = _buildInitialsFallback(worker, size);
    }

    final isOnline = worker.isOnline;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: imageWidget,
          ),
        ),
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: isOnline ? AppColors.success : AppColors.outline,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).cardColor,
                width: 2.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInitialsFallback(WorkerProfile worker, double size) {
    final initial = worker.name.trim().isNotEmpty
        ? worker.name.trim()[0].toUpperCase()
        : 'W';

    return Container(
      width: size,
      height: size,
      color: AppColors.primary.withValues(alpha: 0.12),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
        ),
      ),
    );
  }

  // --- 2. 4-Stat Metrics Bar ---
  Widget _buildStatsStrip(
    BuildContext context,
    WorkerProfile worker,
    bool hasRatingHistory,
  ) {
    final theme = Theme.of(context);

    return Material(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Row(
          children: [
            _buildStatItem(
              context,
              icon: Icons.star_rounded,
              iconColor: Colors.amber,
              value: hasRatingHistory && worker.rating > 0
                  ? worker.rating.toStringAsFixed(1)
                  : 'New',
              label: 'Rating',
            ),
            _buildStatDivider(context),
            _buildStatItem(
              context,
              icon: Icons.work_history_rounded,
              iconColor: AppColors.primary,
              value: '${worker.jobsCompleted}',
              label: 'Jobs Done',
            ),
            _buildStatDivider(context),
            _buildStatItem(
              context,
              icon: Icons.shield_rounded,
              iconColor: AppColors.secondary,
              value: worker.jobsCompleted > 0
                  ? '${worker.reliabilityScore}%'
                  : '100%',
              label: 'Reliability',
            ),
            _buildStatDivider(context),
            _buildStatItem(
              context,
              icon: Icons.schedule_rounded,
              iconColor: AppColors.success,
              value: _percent(worker.onTimeArrival),
              label: 'On-Time',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
  }) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 4),
              Text(
                value,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: Theme.of(context).hintColor,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatDivider(BuildContext context) {
    return Container(
      width: 1,
      height: 26,
      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
    );
  }

  // --- 3. About & Skills Card ---
  Widget _buildAboutCard(
    BuildContext context,
    WorkerProfile worker,
    String aboutSkill,
  ) {
    final theme = Theme.of(context);
    final locale = context.l10n.locale;
    final bioText = worker.bio?.isNotEmpty == true
        ? worker.bio!
        : worker.jobsCompleted > 0
            ? 'Experienced $aboutSkill with ${worker.jobsCompleted} completed jobs delivering quality verified service on Fixly.'
            : 'Verified $aboutSkill professional ready to provide prompt and high-standard service.';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.person_outline_rounded,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'About Worker',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            bioText,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.45,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
            ),
          ),
          if (worker.skills.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Specialized Skills',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.hintColor,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: worker.skills.map((skill) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 13,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        localizeCategory(skill, locale),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // --- 4. Trust & Credentials Card ---
  Widget _buildTrustCard(
    BuildContext context,
    WorkerProfile worker,
    String kycLabel,
  ) {
    final theme = Theme.of(context);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.verified_user_outlined,
                size: 20,
                color: AppColors.success,
              ),
              const SizedBox(width: 8),
              Text(
                'Trust & Verification',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _TrustRowTile(
            icon: Icons.fingerprint_rounded,
            label: 'ID Verification',
            value: kycLabel,
            isHighlight: worker.kycStatus?.toLowerCase() == 'approved' ||
                worker.isVerified,
          ),
          if (worker.insured)
            const _TrustRowTile(
              icon: Icons.shield_outlined,
              label: 'Protection Plan',
              value: 'Fixly Insurance Covered',
              isHighlight: true,
            ),
          _TrustRowTile(
            icon: Icons.task_alt_rounded,
            label: 'Job Completion Rate',
            value: worker.jobsCompleted == 0
                ? 'No data yet'
                : _percent(worker.completionRate),
          ),
          _TrustRowTile(
            icon: Icons.speed_rounded,
            label: 'On-Time Arrival',
            value: worker.jobsCompleted == 0
                ? 'No data yet'
                : _percent(worker.onTimeArrival),
          ),
          if (worker.serviceRadiusKm != null)
            _TrustRowTile(
              icon: Icons.radar_rounded,
              label: 'Service Area',
              value: '${worker.serviceRadiusKm!.toStringAsFixed(0)} km radius',
            ),
          const SizedBox(height: 6),
          Text(
            worker.jobsCompleted == 0
                ? 'This partner is newly registered on Fixly. Performance metrics will automatically populate following completed bookings.'
                : 'Performance metrics calculated directly from verified customer orders.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.hintColor,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  // --- Completed Work Portfolio Card ---
  Widget _buildWorkPortfolioCard(BuildContext context, WorkerProfile worker) {
    final theme = Theme.of(context);
    final photos = worker.recentWorkPhotos;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.photo_library_outlined,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Recent Completed Work',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${photos.length} photos',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (ctx, idx) {
                final photo = photos[idx];
                final fullUrl = photo.startsWith('http')
                    ? photo
                    : '${ApiConfig.baseUrl}${photo.startsWith('/') ? '' : '/'}$photo';
                return GestureDetector(
                  onTap: () => _showPhotoPreview(context, fullUrl),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 110,
                      height: 96,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.outline.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Image.network(
                        fullUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(Icons.broken_image_rounded, size: 28),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- 5. Customer Reviews Card ---
  Widget _buildReviewsCard(
    BuildContext context,
    WorkerProfile worker,
    bool hasRatingHistory,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final itemBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final itemBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    final displayReviews = [...worker.reviews, ..._extraReviews];
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final canLoadMore = _canLoadMoreReviews(worker);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.rate_review_outlined,
                    size: 20,
                    color: Colors.amber,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Customer Reviews',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (worker.reviewCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                      const SizedBox(width: 2),
                      Text(
                        worker.rating > 0
                            ? worker.rating.toStringAsFixed(1)
                            : 'N/A',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (!hasRatingHistory)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No ratings or reviews recorded for this worker yet.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
            )
          else if (displayReviews.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                worker.reviewCount > 0
                    ? '${worker.reviewCount} total customer ratings recorded.'
                    : 'No written reviews yet.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
            )
          else ...[
            for (var i = 0; i < displayReviews.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              Builder(
                builder: (context) {
                  final review = displayReviews[i];
                  final reviewKey =
                      review.id ?? '${review.reviewerName}_${review.createdAt}_$i';
                  Widget tile = DecoratedBox(
                    decoration: BoxDecoration(
                      color: itemBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: itemBorder),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: _ReviewItemTile(review: review),
                    ),
                  );
                  if (!reduceMotion) {
                    tile = tile
                        .animate(key: ValueKey('review-$reviewKey'))
                        .fadeIn(
                          duration: 280.ms,
                          delay: Duration(milliseconds: (i % 5) * 40),
                          curve: Curves.easeOutCubic,
                        )
                        .slideY(
                          begin: 0.05,
                          end: 0,
                          duration: 280.ms,
                          delay: Duration(milliseconds: (i % 5) * 40),
                          curve: Curves.easeOutCubic,
                        );
                  }
                  return tile;
                },
              ),
            ],
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: _loadingMoreReviews
                  ? Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Loading more reviews…',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.hintColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      )
                          .animate()
                          .fadeIn(duration: 180.ms),
                    )
                  : canLoadMore
                      ? const SizedBox(height: 8)
                      : (_extraReviews.isNotEmpty || _reviewsPage > 1)
                          ? Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Center(
                                child: Text(
                                  'You\'ve seen all reviews',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.hintColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
            ),
          ],
        ],
      ),
    );
  }
}

class _TrustRowTile extends StatelessWidget {
  const _TrustRowTile({
    required this.icon,
    required this.label,
    required this.value,
    this.isHighlight = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isHighlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: isHighlight
                ? AppColors.success
                : Theme.of(context).hintColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isHighlight
                      ? AppColors.success
                      : Theme.of(context).colorScheme.onSurface,
                ),
          ),
        ],
      ),
    );
  }
}

class _ReviewItemTile extends StatelessWidget {
  const _ReviewItemTile({required this.review});

  final WorkerReview review;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('d MMM yyyy');
    final dateStr = review.createdAt != null
        ? dateFormat.format(review.createdAt!)
        : null;

    final avatarUrl = review.avatarUrl?.trim();
    Widget avatarWidget;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      final fullUrl = avatarUrl.startsWith('http')
          ? avatarUrl
          : '${ApiConfig.baseUrl}${avatarUrl.startsWith('/') ? '' : '/'}$avatarUrl';
      avatarWidget = CircleAvatar(
        radius: 14,
        backgroundImage: NetworkImage(fullUrl),
        backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        onBackgroundImageError: (_, __) {},
        child: null,
      );
    } else {
      avatarWidget = CircleAvatar(
        radius: 14,
        backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        child: Text(
          review.reviewerName.isNotEmpty
              ? review.reviewerName[0].toUpperCase()
              : 'C',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            avatarWidget,
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                review.reviewerName,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            if (dateStr != null) ...[
              Text(
                dateStr,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: Theme.of(context).hintColor,
                    ),
              ),
              const SizedBox(width: 8),
            ],
            ...List.generate(
              review.rating.round().clamp(1, 5),
              (_) => const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 38),
          child: Text(
            review.comment.isEmpty ? 'No comment provided.' : review.comment,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  height: 1.35,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
                ),
          ),
        ),
        if (review.bookingId != null && review.bookingId!.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 38),
            child: Text(
              review.bookingId!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: Theme.of(context).hintColor,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
        if (review.badgesGiven.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 38),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: review.badgesGiven.map((badge) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
        if (review.photos.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 38),
            child: SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: review.photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final photoUrl = review.photos[index];
                  final fullUrl = photoUrl.startsWith('http')
                      ? photoUrl
                      : '${ApiConfig.baseUrl}${photoUrl.startsWith('/') ? '' : '/'}$photoUrl';
                  return GestureDetector(
                    onTap: () => _showPhotoPreview(context, fullUrl),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .outline
                                .withValues(alpha: 0.25),
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Image.network(
                          fullUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image_rounded, size: 20),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }
}

void _showPhotoPreview(BuildContext context, String imageUrl) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          InteractiveViewer(
            panEnabled: true,
            boundaryMargin: const EdgeInsets.all(20),
            minScale: 0.5,
            maxScale: 4.0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text('Could not load image'),
                ),
              ),
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: CircleAvatar(
              backgroundColor: Colors.black.withValues(alpha: 0.6),
              radius: 18,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.close, color: Colors.white, size: 20),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}


String _percent(double? value) =>
    value == null ? '100%' : '${value.toStringAsFixed(0)}%';

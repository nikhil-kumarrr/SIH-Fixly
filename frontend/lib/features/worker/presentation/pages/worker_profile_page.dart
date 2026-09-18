import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/l10n/category_localizer.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../auth/presentation/cubit/app_session_cubit.dart';
import '../../../shared/presentation/cubit/profile_cubit.dart';
import '../widgets/worker_payout_account_sheet.dart';
import '../../../../core/utils/toast_utils.dart';

class WorkerProfilePage extends StatefulWidget {
  const WorkerProfilePage({super.key});

  @override
  State<WorkerProfilePage> createState() => _WorkerProfilePageState();
}

class _WorkerProfilePageState extends State<WorkerProfilePage> {
  bool _refreshingLocation = false;

  @override
  void initState() {
    super.initState();
    context.read<ProfileCubit>().load();
  }

  Future<void> _signOut() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.signOut),
        content: Text(l10n.signOutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.signOut),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    context.read<AppSessionCubit>().signOut();
    context.go(RouteNames.login);
  }

  Future<void> _refresh() async {
    await context.read<ProfileCubit>().load();
  }

  Future<void> _useCurrentLocation() async {
    if (_refreshingLocation) return;
    setState(() => _refreshingLocation = true);
    try {
      await context.read<ProfileCubit>().refreshCurrentLocation();
      if (!mounted) return;
      ToastUtils.showToast(context: context, message: 'Current location saved to your profile');
    } catch (e) {
      if (!mounted) return;
      ToastUtils.showToast(context: context, message: 'Could not save location: $e');
    } finally {
      if (mounted) setState(() => _refreshingLocation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        return AppScaffold(
          title: l10n.myProfile,
          showBack: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: l10n.settings,
              onPressed: () => context.push(RouteNames.sharedSettings),
            ),
          ],
          body: state.status == ProfileStatus.loading
              ? const Center(child: CircularProgressIndicator())
              : AppRefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    physics: appRefreshScrollPhysics,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    children: [
                      _WorkerHeroCard(
                        name: state.name,
                        phone: state.phone,
                        email: state.email,
                        category: state.category,
                        categories: state.categories,
                        hourlyRate: state.hourlyRate,
                        experienceYears: state.experienceYears,
                        insured: state.insured,
                        workAddress: state.workAddress,
                        locationLabel: state.locationSummary,
                        refreshingLocation: _refreshingLocation,
                        onUseCurrentLocation: _useCurrentLocation,
                        onEditTap: () async {
                          await context.push(RouteNames.sharedEditProfile);
                          if (context.mounted) {
                            context.read<ProfileCubit>().load();
                          }
                        },
                      ).appListEnter(context, index: 0, id: 'hero'),
                      const SizedBox(height: AppSpacing.lg),

                      // Bio snippet if available
                      if (state.bio.isNotEmpty) ...[
                        _WorkerBioCard(
                          bio: state.bio,
                        ).appListEnter(context, index: 1, id: 'bio'),
                        const SizedBox(height: AppSpacing.lg),
                      ],

                      // Skills section
                      if (state.skills.isNotEmpty) ...[
                        _SectionHeader(
                          icon: Icons.auto_awesome_rounded,
                          title: 'Specialized Skills',
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        _SkillsCard(
                          skills: state.skills,
                        ).appListEnter(context, index: 2, id: 'skills'),
                        const SizedBox(height: AppSpacing.lg),
                      ],

                      // Management Menu
                      _SectionHeader(
                        icon: Icons.dashboard_customize_outlined,
                        title: 'Partner Dashboard',
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      _WorkerMenuCard(
                        children: [
                          _WorkerMenuTile(
                            icon: Icons.badge_outlined,
                            iconColor: AppColors.primary,
                            title: l10n.editProfile,
                            subtitle:
                                'Update trade category, skills, rate & details',
                            onTap: () async {
                              await context.push(RouteNames.sharedEditProfile);
                              if (context.mounted) {
                                context.read<ProfileCubit>().load();
                              }
                            },
                          ),
                          _WorkerMenuTile(
                            icon: Icons.verified_outlined,
                            iconColor: AppColors.secondary,
                            title: l10n.reliabilityScore,
                            subtitle:
                                'View your rating and on-time completion record',
                            onTap: () =>
                                context.push(RouteNames.workerReliability),
                          ),
                          _WorkerMenuTile(
                            icon: Icons.receipt_long_rounded,
                            iconColor: AppColors.primary,
                            title: l10n.orderHistory,
                            subtitle: 'View your completed and incoming orders',
                            onTap: () =>
                                context.push(RouteNames.sharedOrderHistory),
                          ),
                          _WorkerMenuTile(
                            icon: Icons.currency_rupee_outlined,
                            iconColor: AppColors.primary,
                            title: 'Rate Settings',
                            subtitle: 'Manage your base price or service rates',
                            onTap: () =>
                                context.push(RouteNames.workerRateSettings),
                          ),
                          _WorkerMenuTile(
                            icon: Icons.account_balance_wallet_outlined,
                            iconColor: AppColors.primary,
                            title: 'Wallet & Withdrawals',
                            subtitle: 'Earnings, withdraw funds & transactions',
                            onTap: () =>
                                context.push(RouteNames.workerWallet),
                          ),
                          _WorkerMenuTile(
                            icon: Icons.account_balance_rounded,
                            iconColor: AppColors.primary,
                            title: 'Bank & UPI Settings',
                            subtitle: 'Setup or update bank account & UPI ID for payouts',
                            onTap: () => WorkerPayoutAccountSheet.show(
                              context,
                              initialUpi: state.upiId,
                            ),
                          ),
                          _WorkerMenuTile(
                            icon: Icons.groups_rounded,
                            iconColor: AppColors.primary,
                            title: 'Cooperative Society & Federation',
                            subtitle: 'Membership ID, affiliation & welfare benefits',
                            onTap: () =>
                                context.push(RouteNames.workerCooperative),
                          ),
                          _WorkerMenuTile(
                            icon: Icons.health_and_safety_outlined,
                            iconColor: AppColors.primary,
                            title: 'Welfare & Insurance',
                            subtitle: 'View your e-Shram status and resources',
                            onTap: () =>
                                context.push(RouteNames.workerWelfare),
                          ),
                          _WorkerMenuTile(
                            icon: Icons.assignment_turned_in_outlined,
                            iconColor: AppColors.primary,
                            title: 'Work Scope, SOP & FAQs',
                            subtitle: 'Trade procedures, boundaries & worker rights',
                            onTap: () =>
                                context.push(RouteNames.workerFaq),
                          ),
                          _WorkerMenuTile(
                            icon: Icons.support_agent_rounded,
                            iconColor: AppColors.primary,
                            title: l10n.support,
                            subtitle:
                                'Cooperative worker help & emergency desk',
                            onTap: () =>
                                context.push(RouteNames.sharedSupportChat),
                          ),
                        ],
                      ).appListEnter(context, index: 3, id: 'menu'),
                      const SizedBox(height: AppSpacing.xl),

                      // Sign Out button
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: OutlinedButton.icon(
                          onPressed: _signOut,
                          icon: const Icon(Icons.logout_rounded, size: 20),
                          label: Text(l10n.signOut),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: BorderSide(
                              color: AppColors.error.withValues(alpha: 0.5),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                            ),
                          ),
                        ),
                      ).appListEnter(context, index: 4, id: 'signout'),
                      const SizedBox(height: AppSpacing.xl),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _WorkerHeroCard extends StatelessWidget {
  const _WorkerHeroCard({
    required this.name,
    required this.phone,
    required this.email,
    required this.category,
    required this.hourlyRate,
    required this.experienceYears,
    required this.insured,
    required this.workAddress,
    required this.locationLabel,
    required this.refreshingLocation,
    required this.onUseCurrentLocation,
    required this.onEditTap,
    this.categories = const [],
  });

  final String name;
  final String phone;
  final String email;
  final String category;
  final List<String> categories;
  final double hourlyRate;
  final int experienceYears;
  final bool insured;
  final String workAddress;
  final String locationLabel;
  final bool refreshingLocation;
  final VoidCallback onUseCurrentLocation;
  final VoidCallback onEditTap;

  // Show ALL selected categories in the user's language (or none) — never a
  // mixed English (Hindi) label.
  String _categoryLabel(BuildContext context) {
    final locale = context.l10n.locale;
    final raw = categories.isNotEmpty
        ? categories
        : (category.isNotEmpty ? <String>[category] : const <String>[]);
    final labels = localizeCategoryList(raw, locale);
    if (labels.isEmpty) return 'Skilled Professional';
    return labels.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryDark,
            AppColors.primary,
            AppColors.primary400,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: Colors.white,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'W',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.verified_rounded,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isNotEmpty ? name : 'Fixly Partner',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _categoryLabel(context),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (phone.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        phone,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: onEditTap,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(44, 44),
                ),
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: 'Edit Profile',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  locationLabel.isNotEmpty
                      ? locationLabel
                      : (workAddress.isNotEmpty
                          ? workAddress
                          : 'Location not set'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ),
              IconButton(
                onPressed: refreshingLocation ? null : onUseCurrentLocation,
                tooltip: 'Use current location',
                color: Colors.white,
                icon: refreshingLocation
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.my_location_outlined),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: AppSpacing.md),

          // Worker Metrics Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _HeroMetric(
                label: 'Base Price',
                value: hourlyRate > 0
                    ? '₹${hourlyRate.toStringAsFixed(0)} base price'
                    : 'Standard',
                icon: Icons.currency_rupee_rounded,
              ),
              Container(width: 1, height: 28, color: Colors.white24),
              _HeroMetric(
                label: 'Experience',
                value: experienceYears > 0
                    ? '$experienceYears yrs'
                    : 'Verified',
                icon: Icons.work_history_outlined,
              ),
              Container(width: 1, height: 28, color: Colors.white24),
              _HeroMetric(
                label: 'Coverage',
                value: insured ? 'Insured' : 'Cooperative',
                icon: Icons.health_and_safety_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.85)),
            const SizedBox(width: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _WorkerBioCard extends StatelessWidget {
  const _WorkerBioCard({required this.bio});

  final String bio;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notes_rounded, size: 16, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'About Me',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: context.muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              bio,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkillsCard extends StatelessWidget {
  const _SkillsCard({required this.skills});

  final List<String> skills;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = context.l10n.locale;

    return Material(
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in skills)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  localizeCategory(s, locale),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs, left: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: context.muted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkerMenuCard extends StatelessWidget {
  const _WorkerMenuCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(height: 1, color: scheme.outline.withValues(alpha: 0.15)),
          ],
        ],
      ),
    );
  }
}

class _WorkerMenuTile extends StatelessWidget {
  const _WorkerMenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effColor = iconColor ?? scheme.primary;

    return ListTile(
      minVerticalPadding: 12,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: effColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: effColor, size: 22),
      ),
      title: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: context.muted),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../../shared/widgets/shared_widgets.dart';
import '../../../auth/presentation/cubit/app_session_cubit.dart';
import '../cubit/profile_cubit.dart';

class ProfileHubPage extends StatefulWidget {
  const ProfileHubPage({super.key});

  @override
  State<ProfileHubPage> createState() => _ProfileHubPageState();
}

class _ProfileHubPageState extends State<ProfileHubPage> {
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

  Future<void> _refreshProfile() async {
    await context.read<ProfileCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        return AppScaffold(
          title: l10n.profile,
          showBack: false,
          body: AppRefreshIndicator(
            onRefresh: _refreshProfile,
            child: ListView(
              physics: appRefreshScrollPhysics,
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                _ProfileHeroCard(
                  name: state.name,
                  phone: state.phone,
                  email: state.email,
                  insured: state.insured,
                  locationLabel: state.locationSummary,
                  roleLabel: l10n.customerMember,
                  onEditTap: () async {
                    await context.push(RouteNames.sharedEditProfile);
                    if (context.mounted) {
                      context.read<ProfileCubit>().load();
                    }
                  },
                ).appListEnter(context, index: 0, id: 'header'),
                const SizedBox(height: AppSpacing.xl),

                _SectionHeader(
                  icon: Icons.history_rounded,
                  title: 'Activity & Orders',
                ),
                const SizedBox(height: AppSpacing.xs),
                _ModernHubGroup(
                  children: [
                    _ModernHubTile(
                      icon: Icons.receipt_long_rounded,
                      iconColor: AppColors.primary,
                      title: l10n.orderHistory,
                      subtitle: 'View your completed and active bookings',
                      onTap: () => context.push(RouteNames.sharedOrderHistory),
                    ),
                    _ModernHubTile(
                      icon: Icons.payments_outlined,
                      iconColor: AppColors.primary,
                      title: 'Payment history',
                      subtitle: 'Razorpay receipts and transaction IDs',
                      onTap: () => context.push(RouteNames.customerPayments),
                    ),
                    _ModernHubTile(
                      icon: Icons.notifications_outlined,
                      iconColor: AppColors.secondary,
                      title: l10n.notifications,
                      subtitle: 'Alerts, updates and messages',
                      onTap: () => context.push(RouteNames.sharedNotifications),
                    ),
                  ],
                ).appListEnter(context, index: 1, id: 'activity'),
                const SizedBox(height: AppSpacing.lg),

                _SectionHeader(
                  icon: Icons.manage_accounts_outlined,
                  title: l10n.account,
                ),
                const SizedBox(height: AppSpacing.xs),
                _ModernHubGroup(
                  children: [
                    _ModernHubTile(
                      icon: Icons.badge_outlined,
                      iconColor: AppColors.primary,
                      title: l10n.editProfile,
                      subtitle: 'Update name, phone, emergency contact & address',
                      onTap: () async {
                        await context.push(RouteNames.sharedEditProfile);
                        if (context.mounted) {
                          context.read<ProfileCubit>().load();
                        }
                      },
                    ),
                    _ModernHubTile(
                      icon: Icons.tune_rounded,
                      iconColor: AppColors.secondary,
                      title: l10n.settings,
                      subtitle: 'Theme, language, privacy and security',
                      onTap: () => context.push(RouteNames.sharedSettings),
                    ),
                  ],
                ).appListEnter(context, index: 2, id: 'account'),
                const SizedBox(height: AppSpacing.lg),

                _SectionHeader(
                  icon: Icons.health_and_safety_outlined,
                  title: l10n.helpSafety,
                ),
                const SizedBox(height: AppSpacing.xs),
                _ModernHubGroup(
                  children: [
                    _ModernHubTile(
                      icon: Icons.support_agent_rounded,
                      iconColor: AppColors.primary,
                      title: l10n.support,
                      subtitle: '24/7 assistance and dispute help',
                      onTap: () => context.push(RouteNames.sharedSupportChat),
                    ),
                    _ModernHubTile(
                      icon: Icons.emergency_share_rounded,
                      iconColor: AppColors.error,
                      title: l10n.emergencySos,
                      subtitle: 'Immediate safety alert with live location',
                      onTap: () => context.push(RouteNames.sharedSos),
                    ),
                  ],
                ).appListEnter(context, index: 3, id: 'help'),
                const SizedBox(height: AppSpacing.xl),

                // Sign out action
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

class _ProfileHeroCard extends StatelessWidget {
  const _ProfileHeroCard({
    required this.name,
    required this.phone,
    required this.email,
    required this.insured,
    required this.locationLabel,
    required this.roleLabel,
    required this.onEditTap,
  });

  final String name;
  final String phone;
  final String email;
  final bool insured;
  final String locationLabel;
  final String roleLabel;
  final VoidCallback onEditTap;

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
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
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
                        Icons.check,
                        size: 10,
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
                      name.isNotEmpty ? name : 'Fixly User',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (phone.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        phone,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        email,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                    if (locationLabel.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 14,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              locationLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                        ],
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
          const SizedBox(height: AppSpacing.md),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  _HeaderChip(label: roleLabel),
                  if (insured) const InsuranceBadge(compact: true),
                ],
              ),
              Row(
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Verified Member',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
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

class _ModernHubGroup extends StatelessWidget {
  const _ModernHubGroup({required this.children});

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
              Divider(
                height: 1,
                color: scheme.outline.withValues(alpha: 0.15),
              ),
          ],
        ],
      ),
    );
  }
}

class _ModernHubTile extends StatelessWidget {
  const _ModernHubTile({
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
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
      subtitle: Text(
        subtitle,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.muted,
            ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

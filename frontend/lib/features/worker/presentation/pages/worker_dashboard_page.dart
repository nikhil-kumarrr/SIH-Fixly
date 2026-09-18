import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/navigation/screen_refresh.dart';
import '../../../../core/network/worker_realtime_service.dart';
import '../../../../core/utils/toast_utils.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../../services/webrtc_call_service.dart';
import '../../../../shared/models/models.dart';
import '../cubit/worker_dashboard_cubit.dart';
import '../widgets/worker_sos_sheet.dart';

class WorkerDashboardPage extends StatefulWidget {
  const WorkerDashboardPage({super.key});

  @override
  State<WorkerDashboardPage> createState() => _WorkerDashboardPageState();
}

class _WorkerDashboardPageState extends State<WorkerDashboardPage>
    with RefreshWhenNavigatedTo {
  @override
  List<String> get refreshRoutePaths => [RouteNames.workerDashboard];

  @override
  void onScreenRefresh() {
    context.read<WorkerDashboardCubit>().load();
  }

  @override
  void initState() {
    super.initState();
    context.read<WorkerDashboardCubit>().load();
  }

  void _navigateToTab(int branchIndex, String routeName) {
    // Branch indexes must match StatefulShellRoute branches in app_router.dart
    // Worker: 0 dashboard, 1 jobs, 2 earnings, 3 profile
    final shell = StatefulNavigationShell.maybeOf(context);
    if (shell != null) {
      shell.goBranch(branchIndex);
    } else {
      context.go(routeName);
    }
  }

  Future<void> _callActiveJobCustomer(WorkerJob activeJob) async {
    final bookingId = activeJob.id;
    if (bookingId.isEmpty) {
      ToastUtils.showError(context: context, message: 'Booking ID not available');
      return;
    }
    final peerName = activeJob.customerName.trim();
    context.push(
      RouteNames.call,
      extra: {
        'bookingId': bookingId,
        'peerName': peerName.isEmpty ? 'Customer' : peerName,
        'peerRole': 'customer',
        'peerAvatar': activeJob.customerAvatar,
        'serviceTitle': activeJob.title,
        'isIncoming': false,
      },
    );

    final success = await WebRTCCallService.instance.startCall(
      bookingId: bookingId,
      expectedPeerName: peerName.isEmpty ? 'Customer' : peerName,
      expectedPeerRole: 'customer',
      expectedPeerAvatar: activeJob.customerAvatar,
      expectedServiceTitle: activeJob.title,
    );

    if (!success && mounted) {
      ToastUtils.showError(context: context, message: 'Could not connect call');
    }
  }

  Future<void> _handleAcceptJob(WorkerJob job) async {
    final cubit = context.read<WorkerDashboardCubit>();
    final success = await cubit.acceptJob(job.id);
    if (!mounted) return;

    if (success) {
      ToastUtils.showSuccess(
        context: context,
        message: '🎉 Job Accepted! Customer has been notified.',
      );
      context.push(RouteNames.workerActiveJob);
    } else {
      ToastUtils.showError(
        context: context,
        message: cubit.state.error ?? 'Failed to accept job. Please try again.',
      );
    }
  }

  Future<void> _handleDeclineJob(WorkerJob job) async {
    final cubit = context.read<WorkerDashboardCubit>();
    final success = await cubit.declineJob(job.id);
    if (!mounted) return;

    if (success) {
      ToastUtils.showToast(
        context: context,
        message: 'Job passed. We will send you other requests.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BlocBuilder<WorkerDashboardCubit, WorkerDashboardState>(
      builder: (context, state) {
        final workerName = state.workerName.isEmpty ? l10n.guestUser : state.workerName;

        return Scaffold(
          backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          appBar: _buildAppBar(context, state, workerName, isDark),
          body: AppRefreshIndicator(
            onRefresh: () => context.read<WorkerDashboardCubit>().load(),
            child: state.status == WorkerDashboardStatus.loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    physics: appRefreshScrollPhysics,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    children: [
                      // 1. Availability Status Hero Card with Custom Tactile Toggle
                      _buildAvailabilityHero(context, state, isDark),
                      const SizedBox(height: 14),

                      // 2. Daily Performance & Stats Bar
                      _buildDailyStatsBar(context, state, isDark),
                      const SizedBox(height: 18),

                      // 3. Incoming Job Requests (Direct Accept & Decline)
                      if (state.incomingJobs.isNotEmpty) ...[
                        _buildIncomingJobsSection(context, state, isDark),
                        const SizedBox(height: 18),
                      ],

                      // 4. Active Ongoing Job (If any)
                      if (state.activeJob != null) ...[
                        _buildActiveJobCard(context, state.activeJob!, isDark),
                        const SizedBox(height: 18),
                      ],

                      // 5. Unified Workspace & Performance Hub
                      _buildWorkspaceHub(context, state, isDark),
                    ],
                  ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    WorkerDashboardState state,
    String workerName,
    bool isDark,
  ) {
    return AppBar(
      automaticallyImplyLeading: false,
      elevation: 0,
      titleSpacing: 12,
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
            child: Text(
              workerName.isNotEmpty ? workerName[0].toUpperCase() : 'W',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Hi, $workerName',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.verified, size: 12, color: Color(0xFF10B981)),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        'Verified Partner',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white60 : const Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        // Worker Availability Status Badge
        StreamBuilder<bool>(
          stream: WorkerRealtimeService.instance.connectionStream,
          initialData: WorkerRealtimeService.instance.isConnected,
          builder: (context, snapshot) {
            final isLive = snapshot.data ?? WorkerRealtimeService.instance.isConnected;
            final isOnline = state.isAvailable;
            final badgeDotColor = isOnline ? const Color(0xFF10B981) : const Color(0xFF94A3B8);
            final statusLabel = isOnline ? 'ONLINE' : 'OFFLINE';
            final tooltipMsg = isOnline
                ? (isLive ? 'Online • Live Sync Active' : 'Online • Connecting...')
                : 'Offline • Tap to go online';

            return Tooltip(
              message: tooltipMsg,
              child: GestureDetector(
                onTap: () {
                  context.read<WorkerDashboardCubit>().toggleAvailability();
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 14),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isOnline
                          ? const Color(0xFF10B981).withValues(alpha: 0.4)
                          : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: badgeDotColor,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: isOnline
                              ? const Color(0xFF10B981)
                              : (isDark ? Colors.white60 : const Color(0xFF64748B)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),

        // Worker SOS Action
        IconButton(
          tooltip: 'Emergency SOS',
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.all(4),
          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          icon: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: const Icon(
              Icons.health_and_safety_rounded,
              color: Colors.red,
              size: 16,
            ),
          ),
          onPressed: () => WorkerSosSheet.show(context),
        ),

        // Notifications
        IconButton(
          tooltip: 'Notifications',
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          icon: const Icon(Icons.notifications_outlined, size: 20),
          onPressed: () => context.push(RouteNames.sharedNotifications),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildAvailabilityHero(BuildContext context, WorkerDashboardState state, bool isDark) {
    final isOnline = state.isAvailable;

    return Container(
      decoration: BoxDecoration(
        color: isOnline
            ? (isDark ? const Color(0xFF0F291E) : const Color(0xFFF0FDF4))
            : (isDark ? const Color(0xFF1E293B) : Colors.white),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isOnline
              ? const Color(0xFF10B981).withValues(alpha: 0.45)
              : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          width: 1.2,
        ),
        boxShadow: [
          if (isOnline)
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.2 : 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Icon badge with status indicator
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOnline
                  ? const Color(0xFF10B981).withValues(alpha: 0.15)
                  : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9)),
              border: Border.all(
                color: isOnline
                    ? const Color(0xFF10B981).withValues(alpha: 0.4)
                    : (isDark ? Colors.white10 : const Color(0xFFCBD5E1)),
              ),
            ),
            child: Icon(
              isOnline ? Icons.sensors_rounded : Icons.power_settings_new_rounded,
              color: isOnline
                  ? const Color(0xFF10B981)
                  : (isDark ? Colors.white54 : const Color(0xFF64748B)),
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isOnline ? 'ONLINE & ACTIVE' : 'YOU ARE OFFLINE',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        letterSpacing: 0.4,
                        color: isOnline
                            ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                            : (isDark ? Colors.white : const Color(0xFF0F172A)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isOnline
                            ? const Color(0xFF10B981)
                            : const Color(0xFF94A3B8),
                        boxShadow: [
                          if (isOnline)
                            BoxShadow(
                              color: const Color(0xFF10B981).withValues(alpha: 0.6),
                              blurRadius: 6,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  isOnline
                      ? 'Live on radar • Ready for job alerts'
                      : 'Toggle on to start receiving bookings',
                  style: TextStyle(
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Custom tactile toggle button
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              context.read<WorkerDashboardCubit>().toggleAvailability();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeInOut,
              width: 64,
              height: 34,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: isOnline
                    ? const Color(0xFF10B981)
                    : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                boxShadow: [
                  if (isOnline)
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                ],
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutBack,
                alignment: isOnline ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Icon(
                    isOnline ? Icons.check_rounded : Icons.power_settings_new_rounded,
                    size: 15,
                    color: isOnline ? const Color(0xFF10B981) : const Color(0xFF64748B),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyStatsBar(
    BuildContext context,
    WorkerDashboardState state,
    bool isDark,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Row(
        children: [
          _buildStatItem(
            label: "Today's Earned",
            value: '₹${state.todayEarnings.toStringAsFixed(0)}',
            isDark: isDark,
            onTap: () => context.push(RouteNames.workerEarnings),
          ),
          Container(
            height: 28,
            width: 1,
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
          _buildStatItem(
            label: 'Jobs Done',
            value: '${state.completedJobs}',
            isDark: isDark,
            onTap: () => _navigateToTab(1, RouteNames.workerJobs),
          ),
          Container(
            height: 28,
            width: 1,
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
          _buildStatItem(
            label: 'Trust Score',
            value: '${state.reliabilityScore}%',
            isDark: isDark,
            onTap: () => context.push(RouteNames.workerReliability),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required String label,
    required String value,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white60 : const Color(0xFF64748B),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIncomingJobsSection(BuildContext context, WorkerDashboardState state, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Text(
                  'Incoming Requests',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${state.incomingJobs.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                    ),
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: () => _navigateToTab(1, RouteNames.workerJobs),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
              child: const Text(
                'View All',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final job in state.incomingJobs.take(2)) ...[
          _buildJobRequestCard(context, job, state.acceptingJobId == job.id, isDark),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildJobRequestCard(BuildContext context, WorkerJob job, bool isAccepting, bool isDark) {
    return Material(
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          context.push(RouteNames.workerJobDetailPath(job.id)).then((_) {
            if (context.mounted) context.read<WorkerDashboardCubit>().load();
          });
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          job.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${job.customerName} • ${job.distanceKm.toStringAsFixed(1)} km away',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : const Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '₹${job.pay.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 14,
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      job.address.isNotEmpty ? job.address : 'Near your service area',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : const Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (job.problemDescription != null && job.problemDescription!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Text(
                    'Note: ${job.problemDescription!.trim()}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                      color: isDark ? Colors.white60 : const Color(0xFF475569),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: isAccepting ? null : () => _handleDeclineJob(job),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? Colors.white70 : const Color(0xFF64748B),
                      side: BorderSide(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Decline',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: isAccepting ? null : () => _handleAcceptJob(job),
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: isAccepting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Accept Job',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveJobCard(BuildContext context, WorkerJob activeJob, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'ACTIVE ONGOING JOB',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : const Color(0xFF475569),
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                '₹${activeJob.pay.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            activeJob.title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 2),
          Text(
            'Customer: ${activeJob.customerName}',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white60 : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 14,
                color: isDark ? Colors.white54 : const Color(0xFF64748B),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  activeJob.address,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton(
                  onPressed: () => _callActiveJobCustomer(activeJob),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? Colors.white70 : const Color(0xFF334155),
                    side: BorderSide(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.phone_outlined, size: 15),
                      SizedBox(width: 4),
                      Text('Call', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () => context.push(RouteNames.workerActiveJob),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Open Job Console',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspaceHub(BuildContext context, WorkerDashboardState state, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Workspace & Tools',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.2),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.25,
          children: [
            _HubCard(
              title: 'Earnings',
              badge: '₹${state.todayEarnings.toStringAsFixed(0)}',
              subtitle: 'Today & breakdown',
              icon: Icons.insights_rounded,
              isDark: isDark,
              onTap: () => context.push(RouteNames.workerEarnings),
            ),
            _HubCard(
              title: 'My Wallet',
              badge: 'Payouts',
              subtitle: 'Bank & UPI transfers',
              icon: Icons.account_balance_wallet_outlined,
              isDark: isDark,
              onTap: () => _navigateToTab(2, RouteNames.workerWallet),
            ),
            _HubCard(
              title: 'Job Feed',
              badge: '${state.completedJobs} Done',
              subtitle: 'Requests & history',
              icon: Icons.assignment_outlined,
              isDark: isDark,
              onTap: () => _navigateToTab(1, RouteNames.workerJobs),
            ),
            _HubCard(
              title: 'Reliability',
              badge: '${state.reliabilityScore}%',
              subtitle: 'Trust & rating score',
              icon: Icons.verified_outlined,
              isDark: isDark,
              onTap: () => context.push(RouteNames.workerReliability),
            ),
            _HubCard(
              title: 'Welfare Fund',
              badge: 'e-Shram',
              subtitle: 'Govt benefits & aid',
              icon: Icons.shield_outlined,
              isDark: isDark,
              onTap: () => context.push(RouteNames.workerWelfare),
            ),
            _HubCard(
              title: 'Rate Settings',
              badge: 'Base Rates',
              subtitle: 'Configure pricing',
              icon: Icons.tune_outlined,
              isDark: isDark,
              onTap: () => context.push(RouteNames.workerRateSettings),
            ),
          ],
        ),
      ],
    );
  }
}

class _HubCard extends StatelessWidget {
  const _HubCard({
    required this.title,
    required this.badge,
    required this.subtitle,
    required this.icon,
    required this.isDark,
    required this.onTap,
  });

  final String title;
  final String badge;
  final String subtitle;
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: isDark ? 0.18 : 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: primaryColor.withValues(alpha: isDark ? 0.3 : 0.15),
                      ),
                    ),
                    child: Icon(
                      icon,
                      color: primaryColor,
                      size: 20,
                    ),
                  ),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white70 : const Color(0xFF475569),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: isDark ? Colors.white38 : Colors.black26,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w400,
                      color: isDark ? Colors.white54 : const Color(0xFF64748B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

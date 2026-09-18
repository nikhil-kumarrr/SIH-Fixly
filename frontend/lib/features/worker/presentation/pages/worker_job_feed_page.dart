import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/navigation/screen_refresh.dart';
import '../../../../core/network/worker_realtime_service.dart';
import '../../../../core/utils/toast_utils.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../../services/webrtc_call_service.dart';
import '../../../../shared/models/models.dart';
import '../cubit/job_feed_cubit.dart';

class WorkerJobFeedPage extends StatefulWidget {
  const WorkerJobFeedPage({super.key});

  @override
  State<WorkerJobFeedPage> createState() => _WorkerJobFeedPageState();
}

class _WorkerJobFeedPageState extends State<WorkerJobFeedPage>
    with RefreshWhenNavigatedTo {
  String _selectedFilter = 'ALL'; // 'ALL', 'INCOMING', 'ACTIVE', 'COMPLETED'

  @override
  List<String> get refreshRoutePaths => [RouteNames.workerJobs];

  @override
  void onScreenRefresh() {
    context.read<JobFeedCubit>().load();
  }

  @override
  void initState() {
    super.initState();
    context.read<JobFeedCubit>().load();
  }

  Future<void> _handleAcceptJob(WorkerJob job) async {
    final success = await context.read<JobFeedCubit>().acceptJob(job.id);
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
        message: 'Failed to accept job. It may have expired or been claimed.',
      );
    }
  }

  Future<void> _handleDeclineJob(WorkerJob job) async {
    final success = await context.read<JobFeedCubit>().declineJob(job.id);
    if (!mounted) return;

    if (success) {
      ToastUtils.showInfo(
        context: context,
        message: 'Job declined.',
      );
    }
  }

  Future<void> _callCustomerWebRtc(WorkerJob job) async {
    final bookingId = job.id;
    if (bookingId.isEmpty) {
      ToastUtils.showError(context: context, message: 'Booking ID not available');
      return;
    }
    final peerName = job.customerName.trim();
    context.push(
      RouteNames.call,
      extra: {
        'bookingId': bookingId,
        'peerName': peerName.isEmpty ? 'Customer' : peerName,
        'peerRole': 'customer',
        'peerAvatar': job.customerAvatar,
        'serviceTitle': job.title,
        'isIncoming': false,
      },
    );

    final success = await WebRTCCallService.instance.startCall(
      bookingId: bookingId,
      expectedPeerName: peerName.isEmpty ? 'Customer' : peerName,
      expectedPeerRole: 'customer',
      expectedPeerAvatar: job.customerAvatar,
      expectedServiceTitle: job.title,
    );

    if (!success && mounted) {
      ToastUtils.showError(context: context, message: 'Could not connect call');
    }
  }

  List<WorkerJob> _getFilteredJobs(JobFeedState state) {
    switch (_selectedFilter) {
      case 'INCOMING':
        return state.incomingJobs;
      case 'ACTIVE':
        return state.activeJobs;
      case 'COMPLETED':
        return state.completedJobs;
      case 'ALL':
      default:
        return state.jobs;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BlocConsumer<JobFeedCubit, JobFeedState>(
      listener: (context, state) {
        if (state.error != null && state.error!.isNotEmpty) {
          ToastUtils.showError(context: context, message: state.error!);
        }
      },
      builder: (context, state) {
        final filteredJobs = _getFilteredJobs(state);

        return AppScaffold(
          title: context.l10n.jobFeed,
          showBack: false,
          padding: EdgeInsets.zero,
          actions: [
            StreamBuilder<bool>(
              stream: WorkerRealtimeService.instance.connectionStream,
              initialData: WorkerRealtimeService.instance.isConnected,
              builder: (context, snapshot) {
                final isLive = snapshot.data ?? false;
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isLive
                                ? const Color(0xFF10B981)
                                : (isDark ? Colors.white38 : Colors.grey),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isLive ? 'Live' : 'Offline',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isLive
                                ? const Color(0xFF10B981)
                                : (isDark ? Colors.white60 : Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
          body: state.status == JobFeedStatus.loading && state.jobs.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    // Clean, neutral horizontal filter pill bar
                    _buildFilterBar(
                      state,
                      _selectedFilter,
                      (filter) => setState(() => _selectedFilter = filter),
                      isDark,
                    ),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    ),

                    // Job feed full-width list spanning edge-to-edge
                    Expanded(
                      child: AppRefreshIndicator(
                        onRefresh: () => context.read<JobFeedCubit>().load(),
                        child: filteredJobs.isEmpty
                            ? _buildEmptyState(context, isDark)
                            : ListView.separated(
                                physics: appRefreshScrollPhysics,
                                padding: const EdgeInsets.only(top: 8, bottom: 96),
                                itemCount: filteredJobs.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final job = filteredJobs[index];
                                  final isActing = state.actingJobId == job.id;

                                  return _JobFeedItem(
                                    job: job,
                                    isActing: isActing,
                                    isDark: isDark,
                                    onAccept: () => _handleAcceptJob(job),
                                    onDecline: () => _handleDeclineJob(job),
                                    onCancelScheduled: () => context
                                        .read<JobFeedCubit>()
                                        .cancelScheduledJob(job.id),
                                    onCall: job.status != JobStatus.completed
                                        ? () => _callCustomerWebRtc(job)
                                        : null,
                                    onTap: () => context.push(
                                      RouteNames.workerJobDetailPath(job.id),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildFilterBar(
    JobFeedState state,
    String selectedFilter,
    ValueChanged<String> onFilterSelected,
    bool isDark,
  ) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final filters = [
      {'key': 'ALL', 'label': 'All', 'count': state.jobs.length},
      {'key': 'INCOMING', 'label': 'Incoming', 'count': state.incomingJobs.length},
      {'key': 'ACTIVE', 'label': 'Active', 'count': state.activeJobs.length},
      {'key': 'COMPLETED', 'label': 'Completed', 'count': state.completedJobs.length},
    ];

    return Container(
      width: double.infinity,
      color: isDark ? const Color(0xFF0F172A) : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((f) {
            final key = f['key'] as String;
            final label = f['label'] as String;
            final count = f['count'] as int;
            final isSelected = selectedFilter == key;

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: () => onFilterSelected(key),
                borderRadius: BorderRadius.circular(20),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? primaryColor
                        : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? primaryColor
                          : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected
                              ? Colors.white
                              : (isDark ? Colors.white70 : const Color(0xFF475569)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white.withValues(alpha: 0.25)
                              : (isDark
                                  ? Colors.white.withValues(alpha: 0.1)
                                  : Colors.black.withValues(alpha: 0.06)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? Colors.white
                                : (isDark ? Colors.white70 : const Color(0xFF475569)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    String message = 'No jobs available in feed';
    String hint = 'New customer service requests will appear here automatically via WebSocket live sync.';

    if (_selectedFilter == 'INCOMING') {
      message = 'No pending job requests';
      hint = 'When nearby customers request services, they will appear here instantly.';
    } else if (_selectedFilter == 'ACTIVE') {
      message = 'No active jobs';
      hint = 'Accepted jobs will show up here as active orders.';
    } else if (_selectedFilter == 'COMPLETED') {
      message = 'No completed jobs yet';
      hint = 'Completed customer orders will be listed here.';
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.2),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 44,
                  color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                ),
                const SizedBox(height: 14),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  hint,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).hintColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_selectedFilter != 'ALL') ...[
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: () => setState(() => _selectedFilter = 'ALL'),
                    child: const Text('View All Jobs'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _JobFeedItem extends StatelessWidget {
  const _JobFeedItem({
    required this.job,
    required this.isActing,
    required this.isDark,
    required this.onAccept,
    required this.onDecline,
    required this.onCancelScheduled,
    required this.onTap,
    this.onCall,
  });

  final WorkerJob job;
  final bool isActing;
  final bool isDark;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onCancelScheduled;
  final VoidCallback onTap;
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final isScheduled = job.bookingType == 'SCHEDULED' || job.scheduledAt != null;
    final isIncoming = job.status == JobStatus.incoming;
    final isActive = job.status == JobStatus.active;
    final isCompleted = job.status == JobStatus.completed;

    return Material(
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                width: 1,
              ),
              bottom: BorderSide(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                width: 1,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Badges (Job Type Tag + Status Chip) on left, Payout on right
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildJobTypeTag(job, isDark),
                      const SizedBox(width: 6),
                      _buildStatusChip(job.status, isDark),
                    ],
                  ),
                  Text(
                    '₹${job.pay.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: primaryColor,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Row 2: Service Title
              Text(
                job.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 6),

              // Row 3: Customer and Distance
              Row(
                children: [
                  Icon(
                    Icons.person_outline_rounded,
                    size: 14,
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      job.customerName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white70 : const Color(0xFF475569),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '  •  ',
                    style: TextStyle(
                      color: isDark ? Colors.white38 : Colors.black26,
                    ),
                  ),
                  Icon(
                    Icons.near_me_outlined,
                    size: 13,
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${job.distanceKm.toStringAsFixed(1)} km away',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Row 4: Address and Phone Call
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
                  if (onCall != null) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: onCall,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.phone_outlined,
                              size: 13,
                              color: primaryColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Call',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              // Customer waiting banner if incoming
              if (isIncoming) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFFB45309).withValues(alpha: 0.3)
                          : const Color(0xFFFDE68A),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.hourglass_bottom_rounded,
                        size: 14,
                        color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Customer waiting for acceptance • You have to go',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Scheduled slot indicator if scheduled
              if (isScheduled && job.scheduledAt != null) ...[
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
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 14,
                            color: isDark ? Colors.white60 : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Scheduled: ${DateFormat('MMM d, y • h:mm a').format(job.scheduledAt!)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white70 : const Color(0xFF475569),
                            ),
                          ),
                        ],
                      ),
                      if (isIncoming || isActive)
                        GestureDetector(
                          onTap: isActing ? null : onCancelScheduled,
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isActing ? Colors.grey : Colors.red.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],

              // Problem description note
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
                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],

              // Action buttons with THEME COLOR
              if (isIncoming) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isActing ? null : onDecline,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? Colors.white70 : const Color(0xFF475569),
                          side: BorderSide(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Decline',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isActing ? null : onAccept,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: isActing
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
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                              ),
                      ),
                    ),
                  ],
                ),
              ] else if (isActive) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Open Job Console',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ] else if (isCompleted) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Completed',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white54 : const Color(0xFF64748B),
                      ),
                    ),
                    Text(
                      'View Details →',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: primaryColor,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(JobStatus status, bool isDark) {
    String label;
    Color textColor;
    Color bgColor;
    Color borderColor;

    switch (status) {
      case JobStatus.incoming:
        label = 'Incoming';
        textColor = const Color(0xFFD97706);
        bgColor = isDark
            ? const Color(0xFF451A03).withValues(alpha: 0.5)
            : const Color(0xFFFEF3C7);
        borderColor = isDark
            ? const Color(0xFFB45309).withValues(alpha: 0.4)
            : const Color(0xFFFDE68A);
        break;
      case JobStatus.active:
        label = 'In Progress';
        textColor = const Color(0xFF059669);
        bgColor = isDark
            ? const Color(0xFF064E3B).withValues(alpha: 0.5)
            : const Color(0xFFD1FAE5);
        borderColor = isDark
            ? const Color(0xFF059669).withValues(alpha: 0.4)
            : const Color(0xFFA7F3D0);
        break;
      case JobStatus.completed:
        label = 'Completed';
        textColor = isDark ? Colors.white60 : const Color(0xFF64748B);
        bgColor = isDark ? Colors.white10 : const Color(0xFFF1F5F9);
        borderColor = isDark ? Colors.white12 : const Color(0xFFE2E8F0);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: textColor,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildJobTypeTag(WorkerJob job, bool isDark) {
    if (job.isSosBooking) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF450A0A) : const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: isDark ? const Color(0xFFB91C1C) : const Color(0xFFFCA5A5),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt_rounded, size: 11, color: Color(0xFFDC2626)),
            SizedBox(width: 3),
            Text(
              'EMERGENCY SOS',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: Color(0xFFDC2626),
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      );
    }

    if (job.isScheduledBooking) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2E1065) : const Color(0xFFEDE9FE),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: isDark ? const Color(0xFF6D28D9) : const Color(0xFFDDD6FE),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.schedule_rounded,
              size: 11,
              color: isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED),
            ),
            const SizedBox(width: 3),
            Text(
              'SCHEDULED',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED),
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF172554) : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: isDark ? const Color(0xFF1D4ED8) : const Color(0xFFBFDBFE),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.handyman_outlined,
            size: 11,
            color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
          ),
          const SizedBox(width: 3),
          Text(
            'STANDARD',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}


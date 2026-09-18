import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/navigation/screen_refresh.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../services/webrtc_call_service.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/l10n/category_localizer.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../../core/utils/toast_utils.dart';
import '../../../../shared/models/models.dart';
import '../../../bookings/data/bookings_api_repository.dart';
import '../cubit/active_job_cubit.dart';
import '../widgets/worker_sos_sheet.dart';

class WorkerActiveJobPage extends StatefulWidget {
  const WorkerActiveJobPage({super.key});

  @override
  State<WorkerActiveJobPage> createState() => _WorkerActiveJobPageState();
}

class _WorkerActiveJobPageState extends State<WorkerActiveJobPage> {
  Timer? _reviewNavTimer;
  bool _reviewNavScheduled = false;
  bool _startingNav = false;

  @override
  void initState() {
    super.initState();
    context.read<ActiveJobCubit>().load();
  }

  @override
  void dispose() {
    _reviewNavTimer?.cancel();
    super.dispose();
  }

  Future<void> _startNavigate(String bookingId) async {
    if (_startingNav) return;
    _startingNav = true;
    try {
      await BookingsApiRepository().startNavigation(bookingId);
    } catch (e) {
      debugPrint('startNavigation on swipe failed: $e');
      if (mounted) {
        ToastUtils.showToast(
          context: context,
          message: 'Could not notify customer — open map & start GPS anyway',
        );
      }
    }
    if (!mounted) return;
    await context.push('${RouteNames.workerNavigation}?bookingId=$bookingId');
    _startingNav = false;
  }

  void _scheduleReviewNavigation(String bookingId) {
    if (_reviewNavScheduled) return;
    _reviewNavScheduled = true;
    _reviewNavTimer?.cancel();
    _reviewNavTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      context.goRefreshing(RouteNames.workerRatingPath(bookingId));
    });
  }

  void _openFinalBilling(BuildContext context, String bookingId) {
    final state = context.read<ActiveJobCubit>().state;
    final raw = (state.job?.rawStatus ?? '').toUpperCase();
    if (state.status == ActiveJobStatus.awaitingPayment ||
        state.status == ActiveJobStatus.paymentReceived ||
        raw == 'PAYMENT_PENDING' ||
        raw == 'COMPLETED' ||
        raw == 'PAYMENT_PAID') {
      ToastUtils.showToast(
        context: context,
        message: 'Payment already requested — waiting for customer',
      );
      return;
    }
    context.push('${RouteNames.workerAddParts}?bookingId=$bookingId');
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ActiveJobCubit, ActiveJobState>(
      listenWhen: (previous, current) =>
          previous.status != current.status || previous.error != current.error,
      listener: (context, state) {
        // Navigation / billing overlays sit above this page — don't steal route.
        if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
        if (state.status == ActiveJobStatus.loaded && state.job == null) {
          context.goRefreshing(RouteNames.workerDashboard);
        } else if (state.status == ActiveJobStatus.paymentReceived &&
            state.job != null) {
          _scheduleReviewNavigation(state.job!.id);
        } else if (state.error != null && state.error!.isNotEmpty) {
          ToastUtils.showError(context: context, message: state.error!);
        }
      },
      builder: (context, state) {
        if (state.status == ActiveJobStatus.loading && state.job == null) {
          return const AppScaffold(
            title: 'Active Job',
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final job = state.job;
        if (job == null) {
          return AppScaffold(
            title: 'Active Job',
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.work_off_outlined,
                        size: 54,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No Active Job',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You do not have any ongoing booking right now.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).hintColor,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => context.go(RouteNames.workerDashboard),
                      icon: const Icon(Icons.dashboard_rounded),
                      label: const Text('Back to Dashboard'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final rawStatus = job.rawStatus ?? '';

        return AppScaffold(
          title: 'Active Job',
          padding: EdgeInsets.zero,
          actions: [
            IconButton(
              tooltip: 'SOS',
              icon: const Icon(Icons.sos_rounded, color: Colors.red),
              onPressed: () => WorkerSosSheet.show(context, bookingId: job.id),
            ),
          ],
          body: Column(
            children: [
              _buildStatusBanner(rawStatus, state.status),
              Expanded(
                child: AppRefreshIndicator(
                  onRefresh: () => context.read<ActiveJobCubit>().load(),
                  child: ListView(
                    physics: appRefreshScrollPhysics,
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildServiceCard(job, context),
                      const SizedBox(height: 16),
                      _buildCustomerCard(job, context),
                      if (job.problemDescription != null &&
                          job.problemDescription!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildProblemDescriptionCard(job, context),
                      ],
                      if (job.problemPhotos.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildProblemPhotos(job),
                      ],
                      const SizedBox(height: 16),
                      _buildInvoiceCard(job, context),
                      const SizedBox(height: 32),
                      _buildBottomAction(rawStatus, job, context, state),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusBanner(String rawStatus, ActiveJobStatus status) {
    Color bgColor = AppColors.primary100;
    Color textColor = AppColors.primary;
    String text = 'Worker Accepted — Head to customer';

    if (status == ActiveJobStatus.paymentReceived ||
        rawStatus == 'PAYMENT_PAID' ||
        rawStatus == 'COMPLETED') {
      bgColor = AppColors.success.withValues(alpha: 0.1);
      textColor = AppColors.success;
      text = 'Payment received — opening review…';
    } else if (rawStatus == 'ARRIVED') {
      bgColor = AppColors.warning.withValues(alpha: 0.1);
      textColor = AppColors.warning;
      text = 'Arrived — Estimate or start work';
    } else if (rawStatus == 'ESTIMATION_GIVEN' ||
        rawStatus == 'ESTIMATION_SUBMITTED') {
      bgColor = AppColors.warning.withValues(alpha: 0.1);
      textColor = AppColors.warning;
      text = 'Waiting for customer to accept estimation';
    } else if (rawStatus == 'READY_TO_START') {
      bgColor = AppColors.primary100;
      textColor = AppColors.primary;
      text = 'Customer accepted — ready to start';
    } else if (rawStatus == 'IN_PROGRESS') {
      bgColor = AppColors.success.withValues(alpha: 0.1);
      textColor = AppColors.success;
      text = 'Job In Progress — Working';
    } else if (rawStatus == 'PAYMENT_PENDING' ||
        status == ActiveJobStatus.awaitingPayment) {
      bgColor = const Color(0xFFFFFBEB);
      textColor = const Color(0xFFD97706);
      text = 'Awaiting customer payment';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: bgColor,
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildServiceCard(dynamic job, BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (job.serviceImage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  job.serviceImage!,
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    height: 120,
                    child: Icon(Icons.image_not_supported),
                  ),
                ),
              ),
            ),
          Text(
            job.title,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (job.serviceCategory != null)
            Text(
              localizeCategory(job.serviceCategory, context.l10n.locale),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }

  Widget _buildCustomerCard(dynamic job, BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Customer',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundImage: job.customerAvatar != null
                    ? NetworkImage(job.customerAvatar!)
                    : null,
                child: job.customerAvatar == null
                    ? Text(job.customerName[0].toUpperCase())
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.customerName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      job.address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 18,
                  color: Color(0xFF16A34A),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Encrypted Audio Call',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF16A34A),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.call, color: Color(0xFF16A34A)),
                  onPressed: () => _makeWebRTCCall(job),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _makeWebRTCCall(dynamic job) async {
    final bookingId = job.id as String?;
    if (bookingId == null || bookingId.isEmpty) {
      ToastUtils.showToast(
        context: context,
        message: 'Booking ID not available',
      );
      return;
    }

    final customerName = job.customerName as String? ?? 'Customer';

    context.push(
      RouteNames.call,
      extra: {
        'bookingId': bookingId,
        'peerName': customerName,
        'peerRole': 'customer',
        'peerAvatar': job.customerAvatar as String?,
        'serviceTitle': job.title,
      },
    );

    final success = await WebRTCCallService.instance.startCall(
      bookingId: job.id,
      expectedPeerName: customerName,
      expectedPeerRole: 'customer',
      expectedPeerAvatar: job.customerAvatar as String?,
      expectedServiceTitle: job.title,
    );

    if (!success && mounted) {
      ToastUtils.showToast(context: context, message: 'Could not connect call');
    }
  }

  Widget _buildProblemDescriptionCard(dynamic job, BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Problem Description',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(job.problemDescription ?? ''),
        ],
      ),
    );
  }

  Widget _buildProblemPhotos(dynamic job) {
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: job.problemPhotos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              job.problemPhotos[index],
              width: 80,
              height: 80,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 80,
                height: 80,
                color: Colors.grey[200],
                child: const Icon(Icons.broken_image),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInvoiceCard(dynamic job, BuildContext context) {
    final WorkerJob j = job as WorkerJob;
    final platform = j.platformFee ?? j.invoice?.platformFee ?? 0.0;
    final base = j.baseServiceFee ?? j.invoice?.baseServiceFee;
    final extras = j.extraPartsTotal ?? j.invoice?.extraPartsTotal;
    final payout = j.workerPayout;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Payout',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (base != null && base > 0) ...[
            _buildPriceRow('Base fee', base),
            const SizedBox(height: 8),
          ],
          if (extras != null && extras > 0) ...[
            _buildPriceRow('Extra parts', extras),
            const SizedBox(height: 8),
          ],
          if (platform > 0) ...[
            _buildPriceRow('Platform fee (deducted)', -platform),
            const SizedBox(height: 8),
          ],
          const Divider(),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Your payout',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Text(
                '₹${payout.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPriceRow(String label, double amount) {
    final isDeduction = amount < 0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary)),
        Text(
          isDeduction
              ? '-₹${amount.abs().toStringAsFixed(0)}'
              : '₹${amount.toStringAsFixed(0)}',
          style: TextStyle(
            color: isDeduction ? const Color(0xFFDC2626) : null,
            fontWeight: isDeduction ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomAction(
    String rawStatus,
    dynamic job,
    BuildContext context,
    ActiveJobState state,
  ) {
    if (state.status == ActiveJobStatus.paymentReceived ||
        rawStatus == 'PAYMENT_PAID' ||
        (rawStatus == 'COMPLETED' && job.invoice?.paymentStatus == 'PAID')) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFBBF7D0)),
        ),
        child: const Column(
          children: [
            Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 40),
            SizedBox(height: 12),
            Text(
              'Payment Received!',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Color(0xFF166534),
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              'Taking you to the review screen in 3 seconds…',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF15803D),
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (rawStatus == 'APPROVED' || rawStatus == 'ACCEPTED') {
      return SwipeActionButton(
        label: 'Swipe to Navigate',
        onCompleted: () => _startNavigate(job.id),
      );
    }

    if (rawStatus == 'ARRIVED') {
      return Column(
        children: [
          PrimaryButton(
            label: 'Create Rough Estimation',
            onPressed: () async {
              final submitted = await context.push<bool>(
                '${RouteNames.workerPriceEstimation}?bookingId=${job.id}',
              );
              if (submitted == true && context.mounted) {
                context.read<ActiveJobCubit>().load();
              }
            },
          ),
          const SizedBox(height: 12),
          SecondaryButton(
            label: 'Start Work (skip estimation)',
            onPressed: () => context.read<ActiveJobCubit>().startJob(),
          ),
        ],
      );
    }

    if (rawStatus == 'ESTIMATION_GIVEN' ||
        rawStatus == 'ESTIMATION_SUBMITTED') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: const Column(
          children: [
            Icon(Icons.hourglass_top_rounded, color: Color(0xFFD97706)),
            SizedBox(height: 8),
            Text(
              'Rough estimation sent',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFFB45309),
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Waiting for customer to accept…',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFB45309), fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (rawStatus == 'READY_TO_START') {
      return SwipeActionButton(
        label: 'Swipe to Start Work',
        onCompleted: () => context.read<ActiveJobCubit>().startJob(),
      );
    }

    if (rawStatus == 'IN_PROGRESS' &&
        state.status != ActiveJobStatus.awaitingPayment &&
        state.status != ActiveJobStatus.paymentReceived) {
      return Column(
        children: [
          Text(
            'Job started at ${job.jobStartedAt != null ? job.jobStartedAt!.toLocal().toString().split('.').first : 'Just now'}',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          SwipeActionButton(
            label: 'Swipe — Work Complete & Bill',
            onCompleted: () => _openFinalBilling(context, job.id),
          ),
        ],
      );
    }

    if (rawStatus == 'PAYMENT_PENDING' ||
        state.status == ActiveJobStatus.awaitingPayment) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: const Column(
          children: [
            Icon(Icons.hourglass_top, color: Color(0xFFD97706), size: 36),
            SizedBox(height: 12),
            Text(
              'Awaiting Customer Payment',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 17,
                color: Color(0xFF92400E),
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              'Customer has been asked to pay.\nThis screen updates automatically when payment is received.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFFB45309),
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return const SizedBox();
  }
}

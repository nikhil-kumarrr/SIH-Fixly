import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/router/route_names.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/navigation/screen_refresh.dart';
import '../../../../core/utils/toast_utils.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../../shared/models/models.dart';
import '../../../bookings/data/bookings_api_repository.dart';
import '../cubit/booking_flow_cubit.dart';

class CustomerEstimationReviewPage extends StatefulWidget {
  const CustomerEstimationReviewPage({super.key, required this.bookingId});

  final String bookingId;

  @override
  State<CustomerEstimationReviewPage> createState() =>
      _CustomerEstimationReviewPageState();
}

class _CustomerEstimationReviewPageState
    extends State<CustomerEstimationReviewPage> {
  bool _isLoading = false;
  Booking? _booking;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      if (widget.bookingId.isNotEmpty) {
        context.read<BookingFlowCubit>().listenToSocketUpdates(widget.bookingId);
      }
    } catch (_) {}

    try {
      final booking = await BookingsApiRepository().getById(
        widget.bookingId,
        forceNetwork: true,
      );
      if (!mounted) return;
      try {
        context.read<BookingFlowCubit>().refreshBooking(widget.bookingId);
      } catch (_) {}
      setState(() {
        _booking = booking;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _acceptEstimation() async {
    setState(() => _isLoading = true);
    try {
      await BookingsApiRepository().acceptEstimation(widget.bookingId);
      if (!mounted) return;
      ToastUtils.showSuccess(
        context: context,
        message: 'Estimation accepted — worker can start',
      );
      try {
        context.read<BookingFlowCubit>().refreshBooking(widget.bookingId);
      } catch (_) {}
      context.goRefreshing(RouteNames.bookingDetailPath(widget.bookingId));
    } catch (e) {
      if (!mounted) return;
      ToastUtils.showError(context: context, message: e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _rejectEstimation() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject estimation?'),
        content: const Text(
          'Rejecting cancels this booking. Base service fee may still apply.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Go back'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Reject & cancel',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await BookingsApiRepository().cancel(widget.bookingId);
      if (!mounted) return;
      ToastUtils.showSuccess(context: context, message: 'Booking cancelled');
      context.goRefreshing(RouteNames.customerOrders);
    } catch (e) {
      if (!mounted) return;
      ToastUtils.showError(context: context, message: e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_loading) {
      return const AppScaffold(
        title: 'Rough Estimation',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final booking = _booking ?? context.watch<BookingFlowCubit>().state.booking;
    if (_error != null || booking == null) {
      return AppScaffold(
        title: 'Rough Estimation',
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error ?? 'Estimation not available yet'),
                const SizedBox(height: 16),
                PrimaryButton(label: 'Retry', onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _bootstrap();
                }),
              ],
            ),
          ),
        ),
      );
    }

    final est = booking.workerEstimation;
    final base = (est != null && est.lockedBaseFee > 0)
        ? est.lockedBaseFee
        : (booking.invoice?.baseServiceFee ??
            booking.baseServiceFee ??
            booking.estimatedPrice);
    final parts = est?.partsEstimate ?? booking.extraPartsTotal ?? 0;
    final serviceCharge = est?.serviceCharge ?? 0;
    final platform = booking.platformFee ?? booking.invoice?.platformFee ?? 0;
    final total = est != null && est.estimatedTotal > 0
        ? est.estimatedTotal + platform
        : (booking.totalAmount ?? (base + parts + serviceCharge + platform));

    return AppScaffold(
      title: 'Rough Estimation',
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF14532D).withValues(alpha: 0.35)
                    : const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.receipt_long_rounded,
                      color: Color(0xFF059669)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Worker sent a rough price update',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF065F46),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Review parts / extra work charges before work starts. Base price stays.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF047857),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              booking.serviceTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (booking.workerName != null) ...[
              const SizedBox(height: 4),
              Text(
                'From ${booking.workerName}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                children: [
                  _Row(label: 'Base service price (locked)', amount: base),
                  const SizedBox(height: 12),
                  _Row(label: '+ Parts / materials', amount: parts),
                  const SizedBox(height: 12),
                  _Row(
                    label: '+ Service charge (extra work)',
                    amount: serviceCharge,
                  ),
                  if (platform > 0) ...[
                    const SizedBox(height: 12),
                    _Row(label: 'Platform fee', amount: platform),
                  ],
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Divider(height: 1),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Estimated total',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '₹${total.toStringAsFixed(0)}',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (est?.notes != null && est!.notes!.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Worker note',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(est.notes!, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 28),
            PrimaryButton(
              label: 'Accept estimation',
              loading: _isLoading,
              onPressed: _isLoading ? null : _acceptEstimation,
            ),
            const SizedBox(height: 12),
            SecondaryButton(
              label: 'Reject & cancel booking',
              onPressed: _isLoading ? null : _rejectEstimation,
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.amount});

  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ),
        Text(
          amount > 0 ? '₹${amount.toStringAsFixed(0)}' : '—',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

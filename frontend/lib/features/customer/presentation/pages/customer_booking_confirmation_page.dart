import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/navigation/screen_refresh.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../../shared/models/models.dart';
import '../cubit/booking_flow_cubit.dart';
import '../cubit/tracking_cubit.dart';

class CustomerBookingConfirmationPage extends StatefulWidget {
  const CustomerBookingConfirmationPage({super.key});

  @override
  State<CustomerBookingConfirmationPage> createState() =>
      _CustomerBookingConfirmationPageState();
}

class _CustomerBookingConfirmationPageState
    extends State<CustomerBookingConfirmationPage> {
  static const _redirectSecondsTotal = 3;

  Timer? _redirectTimer;
  bool _accepted = false;
  bool _redirectStarted = false;
  int _redirectSeconds = _redirectSecondsTotal;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cubit = context.read<BookingFlowCubit>();
      final id = cubit.state.booking?.id;
      if (id != null && id.isNotEmpty) {
        cubit.listenToSocketUpdates(id);
        cubit.refreshBooking(id);
      }
      _maybeStartAcceptedFlow(cubit.state);
    });
  }

  @override
  void dispose() {
    _redirectTimer?.cancel();
    super.dispose();
  }

  bool _isWorkerApproved(BookingFlowState state) {
    final raw = (state.booking?.rawStatus ?? '').toUpperCase();
    return raw == 'APPROVED' ||
        raw == 'ACCEPTED' ||
        state.step == BookingStatus.accepted;
  }

  void _maybeStartAcceptedFlow(BookingFlowState state) {
    if (_redirectStarted || !_isWorkerApproved(state)) return;
    _redirectStarted = true;
    setState(() {
      _accepted = true;
      _redirectSeconds = _redirectSecondsTotal;
    });
    _redirectTimer?.cancel();
    _redirectTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_redirectSeconds <= 1) {
        timer.cancel();
        _goToOrderHistory();
        return;
      }
      setState(() => _redirectSeconds -= 1);
    });
  }

  void _goToOrderHistory() {
    if (!mounted) return;
    context.read<BookingFlowCubit>().reset();
    context.read<TrackingCubit>().reset();
    context.goRefreshing(RouteNames.customerOrders);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<BookingFlowCubit, BookingFlowState>(
      listenWhen: (previous, current) =>
          previous.step != current.step ||
          previous.booking?.rawStatus != current.booking?.rawStatus,
      listener: (context, state) => _maybeStartAcceptedFlow(state),
      child: BlocBuilder<BookingFlowCubit, BookingFlowState>(
        builder: (context, state) {
          final accepted = _accepted || _isWorkerApproved(state);

          return AppScaffold(
            title: accepted ? 'Booking Accepted' : 'Order Placed',
            body: Column(
              children: [
                if (accepted)
                  Material(
                    color: const Color(0xFF059669),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Worker accepted! Redirecting to order history in $_redirectSeconds…',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ).animate().slideY(begin: -1, duration: 280.ms),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 24),
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: accepted
                                ? const Color(0xFFD1FAE5)
                                : const Color(0xFFEFF6FF),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            accepted
                                ? Icons.check_circle_rounded
                                : Icons.assignment_turned_in_rounded,
                            size: 56,
                            color: accepted
                                ? const Color(0xFF059669)
                                : AppColors.primary,
                          ),
                        ).animate().scale(
                          begin: const Offset(0.3, 0.3),
                          duration: 600.ms,
                          curve: Curves.elasticOut,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          accepted
                              ? 'Booking Accepted'
                              : 'Booking Order Placed',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: accepted
                                ? const Color(0xFFD1FAE5)
                                : const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: accepted
                                  ? const Color(0xFFA7F3D0)
                                  : const Color(0xFFFDE68A),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!accepted)
                                const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(
                                      Color(0xFFD97706),
                                    ),
                                  ),
                                )
                              else
                                const Icon(
                                  Icons.done_all_rounded,
                                  size: 16,
                                  color: Color(0xFF047857),
                                ),
                              const SizedBox(width: 8),
                              Text(
                                accepted
                                    ? 'Accepted'
                                    : 'Waiting for worker acceptance',
                                style: TextStyle(
                                  color: accepted
                                      ? const Color(0xFF047857)
                                      : const Color(0xFFB45309),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            accepted
                                ? 'Your worker accepted this booking. Taking you to order history…'
                                : 'Your service request has been created and sent to the worker.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AppColors.outline),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 28),
                        AppCard(
                          child: Column(
                            children: [
                              _DetailRow(
                                label: 'Service',
                                value: state.service?.title ?? 'Service',
                              ),
                              _DetailRow(
                                label: 'Worker',
                                value: state.booking?.workerName ??
                                    'Assigned worker',
                              ),
                              if (state.address != null)
                                _DetailRow(
                                  label: 'Address',
                                  value: state.address!,
                                ),
                              _DetailRow(
                                label: 'Estimated amount',
                                value: '₹${state.displayPrice.toInt()}',
                              ),
                              _DetailRow(
                                label: 'Booking ID',
                                value: state.booking?.id ??
                                    'B-${DateTime.now().millisecondsSinceEpoch}',
                              ),
                              if (state.booking?.arrivalOtp != null)
                                _DetailRow(
                                  label: 'Arrival OTP',
                                  value: state.booking!.arrivalOtp!,
                                  valueColor: AppColors.accent,
                                ),
                              _DetailRow(
                                label: 'Status',
                                value: accepted
                                    ? 'Accepted'
                                    : 'Waiting for worker acceptance',
                                valueColor: accepted
                                    ? const Color(0xFF059669)
                                    : const Color(0xFFD97706),
                              ),
                            ],
                          ),
                        ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1),
                        const SizedBox(height: 32),
                        PrimaryButton(
                          label: 'Order History',
                          onPressed: _goToOrderHistory,
                        ),
                        const SizedBox(height: 12),
                        SecondaryButton(
                          label: 'Home Dashboard',
                          onPressed: () {
                            _redirectTimer?.cancel();
                            context.read<BookingFlowCubit>().reset();
                            context.read<TrackingCubit>().reset();
                            context.go(RouteNames.customerHome);
                          },
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.outline),
          ),
          Flexible(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: valueColor,
                  ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

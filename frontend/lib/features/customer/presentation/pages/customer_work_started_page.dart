import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/navigation/screen_refresh.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../../shared/models/models.dart';
import '../cubit/booking_flow_cubit.dart';

class CustomerWorkStartedPage extends StatefulWidget {
  const CustomerWorkStartedPage({super.key});

  @override
  State<CustomerWorkStartedPage> createState() => _CustomerWorkStartedPageState();
}

class _CustomerWorkStartedPageState extends State<CustomerWorkStartedPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = context.read<BookingFlowCubit>().state.booking?.id;
      if (id != null && id.isNotEmpty) {
        context.read<BookingFlowCubit>().listenToSocketUpdates(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<BookingFlowCubit, BookingFlowState>(
      listenWhen: (previous, current) =>
          previous.step != current.step ||
          previous.booking?.rawStatus != current.booking?.rawStatus ||
          previous.booking?.paymentStatus != current.booking?.paymentStatus,
      listener: (context, state) {
        if (state.step == BookingStatus.paid || state.booking?.paymentStatus == 'PAID') {
          final id = state.booking?.id;
          if (id != null && id.isNotEmpty) {
            context.goRefreshing(RouteNames.customerRatingPath(id));
          } else {
            context.goRefreshing(RouteNames.customerRating);
          }
        }
      },
      child: AppScaffold(
        title: context.l10n.workInProgress,
        body: BlocBuilder<BookingFlowCubit, BookingFlowState>(
          builder: (context, state) {
            final booking = state.booking;
            final isAwaitingPayment = booking?.rawStatus == 'PAYMENT_PENDING' ||
                booking?.status == BookingStatus.completed;
            final isPaid = booking?.status == BookingStatus.paid ||
                booking?.paymentStatus == 'PAID';

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const StepProgressHeader(
                    currentStep: 4,
                    totalSteps: 5,
                    title: 'Work in progress',
                  ),
                  Center(
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: AppColors.tertiary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.construction,
                        size: 48,
                        color: AppColors.tertiary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '${state.booking?.workerName ?? "Worker"} is working on your service',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.service?.title ?? 'Service in progress',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: AppColors.outline),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  AppCard(
                    child: Column(
                      children: [
                        const _StatusRow(label: 'Worker arrived', done: true),
                        _StatusRow(
                          label: isAwaitingPayment
                              ? 'Work completed'
                              : 'Service is in progress',
                          done: true,
                          active: !isAwaitingPayment,
                        ),
                        _StatusRow(
                          label: isAwaitingPayment
                              ? 'Payment required to complete'
                              : 'Pay securely with Razorpay to complete',
                          done: isPaid,
                          active: isAwaitingPayment,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  AppCard(
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: AppColors.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            isAwaitingPayment
                                ? 'Worker has finished the job! Please proceed to pay with Razorpay.'
                                : 'Pay now when the work is done. The job completes after a successful Razorpay payment.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (isPaid)
                    PrimaryButton(
                      label: 'Rate & Review Specialist',
                      onPressed: () {
                        final id = booking?.id;
                        if (id != null && id.isNotEmpty) {
                          context.goRefreshing(RouteNames.customerRatingPath(id));
                        } else {
                          context.goRefreshing(RouteNames.customerRating);
                        }
                      },
                    )
                  else if (isAwaitingPayment)
                    PrimaryButton(
                      label: 'Pay Now (₹${(booking?.totalPrice ?? booking?.estimatedPrice ?? 0).toStringAsFixed(0)})',
                      onPressed: () => context.push(
                        '${RouteNames.customerPayment}?bookingId=${booking?.id ?? ''}&amount=${booking?.totalPrice ?? 0}',
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: const Text(
                        'The service is currently in progress. You cannot make a payment while the worker is actively working. Please wait until the worker completes the service.',
                        style: TextStyle(
                          color: Color(0xFFB45309),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.done,
    this.active = false,
  });

  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            color: done
                ? (active ? AppColors.accent : AppColors.primary)
                : context.hairline,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                color: active ? context.ink : context.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

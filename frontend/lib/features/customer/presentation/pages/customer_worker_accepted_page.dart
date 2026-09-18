import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/navigation/screen_refresh.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/utils/rating_format.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../../shared/models/models.dart';
import '../cubit/booking_flow_cubit.dart';

class CustomerWorkerAcceptedPage extends StatefulWidget {
  const CustomerWorkerAcceptedPage({super.key});

  @override
  State<CustomerWorkerAcceptedPage> createState() =>
      _CustomerWorkerAcceptedPageState();
}

class _CustomerWorkerAcceptedPageState extends State<CustomerWorkerAcceptedPage> {
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
        final raw = state.booking?.rawStatus;
        if (state.step == BookingStatus.arrived ||
            raw == 'ARRIVED' ||
            raw == 'ESTIMATION_GIVEN' ||
            raw == 'READY_TO_START') {
          context.pushReplacement(RouteNames.customerWorkerArrived);
        } else if (raw == 'IN_PROGRESS' || state.step == BookingStatus.inProgress) {
          context.pushReplacement(RouteNames.customerWorkStarted);
        } else if (state.step == BookingStatus.paid || state.booking?.paymentStatus == 'PAID') {
          final id = state.booking?.id;
          if (id != null && id.isNotEmpty) {
            context.goRefreshing(RouteNames.customerRatingPath(id));
          } else {
            context.goRefreshing(RouteNames.customerRating);
          }
        }
      },
      child: AppScaffold(
        title: 'Worker Assigned',
        body: BlocBuilder<BookingFlowCubit, BookingFlowState>(
          builder: (context, state) {
            final booking = state.booking;
            final workerName = booking?.workerName ?? 'Worker';
            final workerId = booking?.workerId;
            final arrivalOtp = booking?.arrivalOtp ?? '----';
            final digits = arrivalOtp.padRight(4, '-').substring(0, 4).split('');
            final isAwaitingPayment = booking?.rawStatus == 'PAYMENT_PENDING' ||
                booking?.status == BookingStatus.completed;
            final isPaid = booking?.status == BookingStatus.paid ||
                booking?.paymentStatus == 'PAID';

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const StepProgressHeader(
                    currentStep: 3,
                    totalSteps: 5,
                    title: 'Worker Assigned',
                  ),
                  const SizedBox(height: 32),
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6CF8BB).withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      size: 48,
                      color: Color(0xFF006C49),
                    ),
                  ).animate().scale(
                        begin: const Offset(0.5, 0.5),
                        duration: 600.ms,
                        curve: Curves.elasticOut,
                      ),
                  const SizedBox(height: 24),
                  Text(
                    'Worker Found!',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$workerName accepted your booking',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.outline,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  
                  // HIGH-TRUST OTP CARD
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF4FF),
                      border: Border.all(color: const Color(0xFFB4C5FF)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.shield_outlined, color: Color(0xFF2563EB)),
                            SizedBox(width: 8),
                            Text(
                              'Start Job OTP',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0B1C30),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: digits.map((digit) {
                            return Container(
                              width: 52,
                              height: 60,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(
                                  color: const Color(0xFF2563EB),
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  digit,
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2563EB),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Share code only after worker arrives at site',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Worker Credential Card
                  GestureDetector(
                    onTap: () {
                      if (workerId != null) {
                        context.push('/customer/worker/$workerId');
                      }
                    },
                    child: AppCard(
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 32,
                            backgroundColor: const Color(0xFFEFF4FF),
                            backgroundImage: booking?.workerAvatar != null
                                ? NetworkImage(booking!.workerAvatar!)
                                : null,
                            child: booking?.workerAvatar == null
                                ? Text(
                                    workerName.isNotEmpty ? workerName[0] : 'W',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2563EB),
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  workerName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Text(
                                  'Verified Fixly Specialist',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.star, size: 16, color: Colors.amber),
                                    const SizedBox(width: 4),
                                    Text(
                                      booking?.workerRating != null &&
                                              booking!.workerRating! > 0
                                          ? '${formatRating(booking.workerRating)} ★'
                                          : 'New',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.phone_outlined),
                            color: const Color(0xFF2563EB),
                            onPressed: () {
                              // Call action
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  const Text(
                    'Your worker is on the way',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF0B1C30),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  if (isPaid) ...[
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
                    ),
                  ] else if (isAwaitingPayment) ...[
                    PrimaryButton(
                      label: 'Pay Now (₹${(booking?.totalPrice ?? booking?.estimatedPrice ?? 0).toStringAsFixed(0)})',
                      onPressed: () => context.push(RouteNames.customerPayment),
                    ),
                  ] else ...[
                    PrimaryButton(
                      label: 'Track Worker Live',
                      onPressed: () {
                        if (booking?.id != null) {
                          context.push('${RouteNames.customerTracking}?bookingId=${booking!.id}');
                        } else {
                          context.push(RouteNames.customerTracking);
                        }
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  SecondaryButton(
                    label: 'Need Help?',
                    onPressed: () => context.push(RouteNames.sharedSupportChat),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

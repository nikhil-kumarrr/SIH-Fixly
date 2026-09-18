import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/navigation/screen_refresh.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../../shared/models/models.dart';
import '../cubit/booking_flow_cubit.dart';

class CustomerWorkerArrivedPage extends StatefulWidget {
  const CustomerWorkerArrivedPage({super.key});

  @override
  State<CustomerWorkerArrivedPage> createState() =>
      _CustomerWorkerArrivedPageState();
}

class _CustomerWorkerArrivedPageState extends State<CustomerWorkerArrivedPage> {
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
        if (state.booking?.rawStatus == 'IN_PROGRESS' ||
            state.step == BookingStatus.inProgress) {
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
        title: 'Worker Arrived',
        body: BlocBuilder<BookingFlowCubit, BookingFlowState>(
          builder: (context, state) {
            final booking = state.booking;
            final workerName = booking?.workerName ?? 'Worker';
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
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: Color(0xFFDBE1FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.handshake_outlined,
                      size: 40,
                      color: Color(0xFF004AC6),
                    ),
                  ).animate().fadeIn(duration: 600.ms),
                  const SizedBox(height: 24),
                  const Text(
                    'Worker Has Arrived!',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your worker is at your location. Share the OTP to authorize work to begin.',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  
                  // OTP Display
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: digits.map((digit) {
                      return Container(
                        width: 64,
                        height: 64,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: const Color(0xFF2563EB),
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            digit,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0B1C30),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 32),
                  
                  // Worker micro-card
                  AppCard(
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: const Color(0xFFEFF4FF),
                          backgroundImage: booking?.workerAvatar != null
                              ? NetworkImage(booking!.workerAvatar!)
                              : null,
                          child: booking?.workerAvatar == null
                              ? Text(
                                  workerName.isNotEmpty ? workerName[0] : 'W',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2563EB),
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                workerName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              if (booking?.serviceTitle != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  booking!.serviceTitle,
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Aadhaar Verified',
                            style: TextStyle(
                              fontSize: 10,
                              color: Color(0xFF2E7D32),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Safety info banner
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF4FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: Color(0xFF2563EB), size: 20),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Do not share the code until the worker is physically present at your location',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF0B1C30),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  
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
                      label: 'View Live Location Map',
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
                    label: 'Worker Not Arrived?',
                    onPressed: () => context.push(RouteNames.sharedSupportChat),
                  ),
                  const SizedBox(height: 16),
                  
                  const Text(
                    'Waiting for worker to enter OTP...',
                    style: TextStyle(
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey,
                    ),
                  ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 0.5, end: 1),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

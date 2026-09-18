import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/navigation/screen_refresh.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/l10n/category_localizer.dart';
import '../../../../shared/models/models.dart';
import '../cubit/booking_flow_cubit.dart';

class CustomerFindingWorkerPage extends StatefulWidget {
  const CustomerFindingWorkerPage({super.key});

  @override
  State<CustomerFindingWorkerPage> createState() =>
      _CustomerFindingWorkerPageState();
}

class _CustomerFindingWorkerPageState extends State<CustomerFindingWorkerPage> {
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _startSearch();
  }
  
  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _startSearch() async {
    final cubit = context.read<BookingFlowCubit>();
    await cubit.searchWorker();
    final bookingId = cubit.state.booking?.id;
    if (bookingId != null && bookingId.isNotEmpty) {
      cubit.listenToSocketUpdates(bookingId);
    }

    // Polling as fallback if socket misses accept event
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      cubit.workerAccepted();
    });
  }

  void _handleCancel() {
    // Add cancel API if needed, then pop
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<BookingFlowCubit, BookingFlowState>(
      listenWhen: (previous, current) => previous.step != current.step,
      listener: (context, state) {
        if (state.step == BookingStatus.accepted) {
          ScreenRefresh.mark(RouteNames.customerWorkerAccepted);
          context.pushReplacement(RouteNames.customerWorkerAccepted);
        } else if (state.step == BookingStatus.arrived) {
          ScreenRefresh.mark(RouteNames.customerWorkerArrived);
          context.pushReplacement(RouteNames.customerWorkerArrived);
        } else if (state.step == BookingStatus.inProgress) {
          ScreenRefresh.mark(RouteNames.customerWorkStarted);
          context.pushReplacement(RouteNames.customerWorkStarted);
        }
      },
      child: AppScaffold(
        title: 'Finding Your Pro',
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildRadarHero(),
                const SizedBox(height: 32),
                Text(
                  'Matching You with Nearby Pros...',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0B1C30),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Scanning verified workers within 5km',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF434655),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF4FF),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF2563EB),
                          shape: BoxShape.circle,
                        ),
                      ).animate(onPlay: (c) => c.repeat()).fade(duration: 800.ms),
                      const SizedBox(width: 8),
                      const Text(
                        'Scanning nearby workers...',
                        style: TextStyle(
                          color: Color(0xFF2563EB),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                BlocBuilder<BookingFlowCubit, BookingFlowState>(
                  builder: (context, state) {
                    final booking = state.booking;
                    if (booking == null) return const SizedBox();
                    return AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (booking.serviceTitle.isNotEmpty)
                            Text(
                              booking.serviceTitle,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          if (booking.serviceCategory != null)
                            Text(
                              localizeCategory(
                                booking.serviceCategory,
                                context.l10n.locale,
                              ),
                              style: const TextStyle(color: Colors.grey),
                            ),
                          const SizedBox(height: 8),
                          if (booking.address != null) ...[
                            const Row(
                              children: [
                                Icon(Icons.location_on_outlined, size: 16, color: Colors.grey),
                                SizedBox(width: 4),
                                Text('Location', style: TextStyle(color: Colors.grey)),
                              ],
                            ),
                            Text(booking.address!, maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 8),
                          ],
                          const Row(
                            children: [
                              Icon(Icons.timer_outlined, size: 16, color: Colors.grey),
                              SizedBox(width: 4),
                              Text('Avg response ~15 mins', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 32),
                OutlinedButton(
                  onPressed: _handleCancel,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: const Text('Cancel Request'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'No cancellation fee while searching',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRadarHero() {
    return Stack(
      alignment: Alignment.center,
      children: [
        _buildPulseCircle(220, 0.08, 0),
        _buildPulseCircle(160, 0.15, 200),
        _buildPulseCircle(120, 0.25, 400),
        Container(
          width: 96,
          height: 96,
          decoration: const BoxDecoration(
            color: Color(0xFFDBE1FF),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Icon(
              Icons.location_searching_rounded,
              size: 40,
              color: Color(0xFF2563EB),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPulseCircle(double size, double opacity, int delayMs) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF2563EB).withValues(alpha: opacity),
        shape: BoxShape.circle,
      ),
    )
        .animate(onPlay: (c) => c.repeat())
        .scale(
          begin: const Offset(0.5, 0.5),
          end: const Offset(1.2, 1.2),
          duration: 1500.ms,
          delay: delayMs.ms,
        )
        .fade(begin: 1, end: 0, duration: 1500.ms, delay: delayMs.ms);
  }
}

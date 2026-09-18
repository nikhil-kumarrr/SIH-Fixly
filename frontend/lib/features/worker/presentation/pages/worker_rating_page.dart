import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/router/route_names.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../core/navigation/screen_refresh.dart';
import '../../../../core/utils/toast_utils.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../bookings/data/bookings_api_repository.dart';
import '../cubit/active_job_cubit.dart';

class WorkerRatingPage extends StatefulWidget {
  const WorkerRatingPage({super.key, required this.bookingId, this.customerId});

  final String bookingId;
  final String? customerId;

  @override
  State<WorkerRatingPage> createState() => _WorkerRatingPageState();
}

class _WorkerRatingPageState extends State<WorkerRatingPage> {
  int _rating = 5;
  final TextEditingController _commentCtrl = TextEditingController();
  final Set<String> _selectedTraits = {};
  String? _resolvedCustomerId;
  String? _customerName;
  String? _customerAvatar;

  final List<String> _traits = [
    '👍 Polite & Respectful',
    '🏠 Clean & Accessible Site',
    '📝 Accurate Work Description',
    '⏰ Present on Time',
    '💰 Fair Expectations',
    '⚡ Quick Approval',
  ];

  @override
  void initState() {
    super.initState();
    _resolvedCustomerId = widget.customerId;
    unawaited(_loadBookingMeta());
  }

  Future<void> _loadBookingMeta() async {
    try {
      final booking =
          await BookingsApiRepository().getById(widget.bookingId, forceNetwork: true);
      if (!mounted) return;
      setState(() {
        _resolvedCustomerId =
            (widget.customerId != null && widget.customerId!.isNotEmpty)
                ? widget.customerId
                : booking.customerId;
        _customerName = booking.customerName;
        _customerAvatar = booking.customerAvatar;
      });
    } catch (_) {
      // Keep route/cubit customer id if fetch fails.
    }
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_rating == 0) {
      ToastUtils.showToast(context: context, message: 'Please select a star rating');
      return;
    }

    final cId = _resolvedCustomerId ?? widget.customerId ?? '';
    if (cId.isEmpty) {
      ToastUtils.showToast(
        context: context,
        message: 'Customer details missing — cannot submit review',
      );
      return;
    }

    context.read<ActiveJobCubit>().submitWorkerReview(
      bookingId: widget.bookingId,
      customerId: cId,
      rating: _rating,
      comment: _commentCtrl.text.trim(),
      traits: _selectedTraits.toList(),
    );
  }

  String _ratingLabel(int r) {
    switch (r) {
      case 1:
        return '1 / 5 - Poor Experience';
      case 2:
        return '2 / 5 - Below Average';
      case 3:
        return '3 / 5 - Good & Decent';
      case 4:
        return '4 / 5 - Very Good';
      case 5:
        return '5 / 5 - Excellent Customer!';
      default:
        return 'Tap stars to rate';
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ActiveJobCubit>().state;
    final job = state.job;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final customerName = (_customerName != null && _customerName!.isNotEmpty)
        ? _customerName!
        : (job?.customerName ?? 'Customer');
    final customerAvatar = (_customerAvatar != null && _customerAvatar!.isNotEmpty)
        ? _customerAvatar
        : job?.customerAvatar;

    return PopScope(
      canPop: false,
      child: BlocListener<ActiveJobCubit, ActiveJobState>(
        listener: (context, state) {
          if (state.status == ActiveJobStatus.reviewSubmitted) {
            ToastUtils.showSuccess(
              context: context,
              message: 'Review submitted! Great work on completing this job.',
            );
            context.goRefreshing(RouteNames.workerJobDetailPath(widget.bookingId));
          } else if (state.status == ActiveJobStatus.failure) {
            ToastUtils.showError(
              context: context,
              message: state.error ?? 'Failed to submit review',
            );
          }
        },
        child: AppScaffold(
          title: 'Rate Customer & Finish',
          showBack: false,
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                        backgroundImage: (customerAvatar != null && customerAvatar.isNotEmpty)
                            ? NetworkImage(customerAvatar)
                            : null,
                        child: (customerAvatar == null || customerAvatar.isEmpty)
                            ? Text(
                                customerName.isNotEmpty
                                    ? customerName[0].toUpperCase()
                                    : 'C',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.check_circle, color: Color(0xFF10B981), size: 14),
                                SizedBox(width: 4),
                                Text(
                                  'Work Complete',
                                  style: TextStyle(
                                    color: Color(0xFF10B981),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              customerName,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              job?.title ?? 'Service Booking',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).hintColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'How was your experience?',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (index) {
                          final star = index + 1;
                          return IconButton(
                            iconSize: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            icon: Icon(
                              star <= _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                              color: const Color(0xFFF59E0B),
                            ),
                            onPressed: () => setState(() => _rating = star),
                          );
                        }),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _ratingLabel(_rating),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFD97706),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                const Text(
                  'Compliments & Traits (Optional)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _traits.map((trait) {
                    final isSelected = _selectedTraits.contains(trait);
                    return FilterChip(
                      label: Text(trait),
                      selected: isSelected,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? AppColors.primary : null,
                      ),
                      selectedColor: AppColors.primary.withValues(alpha: 0.12),
                      checkmarkColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedTraits.add(trait);
                          } else {
                            _selectedTraits.remove(trait);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                Row(
                  children: [
                    const Text(
                      'Review Description',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '(Optional)',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _commentCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText:
                        'Share notes about site conditions, customer cooperation, or remarks...',
                    hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                ElevatedButton(
                  onPressed: state.status == ActiveJobStatus.loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    elevation: 3,
                  ),
                  child: state.status == ActiveJobStatus.loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Submit Review & Finish',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

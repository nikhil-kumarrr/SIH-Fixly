import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../../shared/models/models.dart';
import '../../../bookings/data/bookings_api_repository.dart';
import '../cubit/active_job_cubit.dart';
import '../../../../core/utils/toast_utils.dart';
import '../../../../core/network/api_exception.dart';

class WorkerOtpEntryPage extends StatefulWidget {
  const WorkerOtpEntryPage({super.key, required this.bookingId});

  final String bookingId;

  @override
  State<WorkerOtpEntryPage> createState() => _WorkerOtpEntryPageState();
}

class _WorkerOtpEntryPageState extends State<WorkerOtpEntryPage> {
  WorkerJob? _job;
  bool _isLoading = true;
  String? _error;

  final List<TextEditingController> _controllers = List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(4, (_) => FocusNode());

  @override
  void initState() {
    super.initState();
    _loadJob();
  }

  Future<void> _loadJob() async {
    try {
      final job = await BookingsApiRepository().workerJobById(widget.bookingId);
      setState(() {
        _job = job;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = ApiException.fromError(e);
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _onDigitEntered(int index, String value) {
    if (value.isNotEmpty) {
      if (index < 3) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
      }
    } else {
      if (index > 0) {
        _focusNodes[index - 1].requestFocus();
      }
    }
    setState(() {}); // update button state
  }

  String get _otp => _controllers.map((c) => c.text).join();

  void _submitOtp() {
    context.read<ActiveJobCubit>().verifyArrivalOtp(otp: _otp);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ActiveJobCubit, ActiveJobState>(
      listener: (context, state) {
        if (state.status == ActiveJobStatus.loaded ||
            state.status == ActiveJobStatus.inProgress) {
          final raw = state.job?.rawStatus;
          if (raw == 'ARRIVED' ||
              raw == 'IN_PROGRESS' ||
              raw == 'READY_TO_START' ||
              raw == 'ESTIMATION_GIVEN') {
            context.go(RouteNames.workerActiveJob);
          }
        } else if (state.status == ActiveJobStatus.failure) {
          ToastUtils.showToast(context: context, message: state.error ?? 'Failed to verify OTP');
        }
      },
      child: AppScaffold(
        title: 'Arrival OTP',
        showBack: true,
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 32),
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.verified_user_outlined, size: 64, color: AppColors.primary),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Enter Customer OTP',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Ask the customer for their 4-digit security code',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 32),
                      AppCard(
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundImage: _job!.customerAvatar != null ? NetworkImage(_job!.customerAvatar!) : null,
                              child: _job!.customerAvatar == null ? Text(_job!.customerName[0].toUpperCase()) : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_job!.customerName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  Text(
                                    _job!.address,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(4, (index) {
                          return SizedBox(
                            width: 56,
                            height: 64,
                            child: TextField(
                              controller: _controllers[index],
                              focusNode: _focusNodes[index],
                              keyboardType: TextInputType.number,
                              maxLength: 1,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.primary),
                              decoration: InputDecoration(
                                counterText: '',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: AppColors.primary, width: 2),
                                ),
                              ),
                              onChanged: (val) => _onDigitEntered(index, val),
                            ),
                          );
                        }),
                      ),
                      const Spacer(),
                      SwipeActionButton(
                        label: 'Swipe to Confirm Arrival',
                        enabled: _otp.length == 4,
                        onCompleted: _submitOtp,
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
      ),
    );
  }
}

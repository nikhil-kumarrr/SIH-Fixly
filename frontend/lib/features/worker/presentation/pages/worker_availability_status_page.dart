import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/toast_utils.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../workers/data/workers_api_repository.dart';
import '../cubit/worker_dashboard_cubit.dart';

class WorkerAvailabilityStatusPage extends StatefulWidget {
  const WorkerAvailabilityStatusPage({super.key});

  @override
  State<WorkerAvailabilityStatusPage> createState() =>
      _WorkerAvailabilityStatusPageState();
}

class _WorkerAvailabilityStatusPageState
    extends State<WorkerAvailabilityStatusPage> {
  final _repo = WorkersApiRepository();
  final _dayLabels = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final Set<int> _selectedDays = {1, 2, 3, 4, 5};
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 18, minute: 0);
  bool _loadingSchedule = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    context.read<WorkerDashboardCubit>().load();
    _loadSchedule();
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _loadSchedule() async {
    try {
      final data = await _repo.fetchAvailability();
      final schedule = data['availabilitySchedule'];
      if (schedule is Map) {
        final days = schedule['days'];
        if (days is List && days.isNotEmpty) {
          _selectedDays
            ..clear()
            ..addAll(days.map((e) => (e as num).toInt()));
        }
        final start = schedule['startTime']?.toString();
        final end = schedule['endTime']?.toString();
        if (start != null && start.contains(':')) {
          final p = start.split(':');
          _start = TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
        }
        if (end != null && end.contains(':')) {
          final p = end.split(':');
          _end = TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingSchedule = false);
  }

  Future<void> _saveSchedule() async {
    if (_selectedDays.isEmpty) {
      ToastUtils.showToast(
        context: context,
        message: 'Select at least one day',
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _repo.updateAvailabilitySchedule(
        days: _selectedDays.toList()..sort(),
        startTime: _fmt(_start),
        endTime: _fmt(_end),
      );
      if (mounted) {
        ToastUtils.showSuccess(context: context, message: 'Schedule saved');
      }
    } on ApiException catch (e) {
      if (mounted) {
        ToastUtils.showError(context: context, message: e.message);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _start : _end,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WorkerDashboardCubit, WorkerDashboardState>(
      builder: (context, state) {
        return AppScaffold(
          title: context.l10n.availabilityStatus,
          body: AppRefreshIndicator(
            onRefresh: () async {
              await context.read<WorkerDashboardCubit>().load();
              await _loadSchedule();
            },
            child: ListView(
              physics: appRefreshScrollPhysics,
              padding: const EdgeInsets.all(16),
              children: [
                AppCard(
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: state.isAvailable
                              ? AppColors.success
                              : AppColors.outline,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              state.isAvailable ? 'Online' : 'Offline',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              state.isAvailable
                                  ? 'Receiving nearby job requests'
                                  : 'Not receiving job requests',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: state.isAvailable,
                        activeTrackColor:
                            AppColors.success.withValues(alpha: 0.4),
                        thumbColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? AppColors.success
                              : null,
                        ),
                        onChanged: (_) => context
                            .read<WorkerDashboardCubit>()
                            .toggleAvailability(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Weekly schedule',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (_loadingSchedule)
                  const AppCard(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(7, (i) {
                      final dayNum = i + 1;
                      final selected = _selectedDays.contains(dayNum);
                      return FilterChip(
                        label: Text(_dayLabels[i]),
                        selected: selected,
                        onSelected: (v) {
                          setState(() {
                            if (v) {
                              _selectedDays.add(dayNum);
                            } else {
                              _selectedDays.remove(dayNum);
                            }
                          });
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  AppCard(
                    child: Column(
                      children: [
                        ListTile(
                          title: const Text('Start'),
                          trailing: Text(_fmt(_start)),
                          onTap: () => _pickTime(isStart: true),
                        ),
                        ListTile(
                          title: const Text('End'),
                          trailing: Text(_fmt(_end)),
                          onTap: () => _pickTime(isStart: false),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    label: _saving ? 'Saving…' : 'Save schedule',
                    onPressed: _saving ? null : _saveSchedule,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

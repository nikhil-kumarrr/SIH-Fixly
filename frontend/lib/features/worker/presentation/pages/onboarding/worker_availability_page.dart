import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/router/route_names.dart';
import '../../../../../app/theme/theme_x.dart';
import '../../../../../core/network/api_exception.dart';
import '../../../../../core/utils/toast_utils.dart';
import '../../../../../core/widgets/core_widgets.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../workers/data/workers_api_repository.dart';

class WorkerAvailabilityPage extends StatefulWidget {
  const WorkerAvailabilityPage({super.key});

  @override
  State<WorkerAvailabilityPage> createState() => _WorkerAvailabilityPageState();
}

class _WorkerAvailabilityPageState extends State<WorkerAvailabilityPage> {
  final _repo = WorkersApiRepository();
  final _dayLabels = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  /// Backend uses 0=Sun … 6=Sat in some places; we store Mon=1 … Sun=0 JS-style.
  /// Match workerController: days as numbers; use Mon–Sun as 1–7 then map to 0–6 Sun-first.
  final Set<int> _selectedDays = {1, 2, 3, 4, 5}; // Mon–Fri (1=Mon … 7=Sun)
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 18, minute: 0);
  bool _saving = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _load() async {
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
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveAndContinue() async {
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
      if (!mounted) return;
      context.go(RouteNames.workerDashboard);
    } on ApiException catch (e) {
      if (mounted) {
        ToastUtils.showError(context: context, message: e.message);
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.showError(
          context: context,
          message: ApiException.fromError(e),
        );
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
    return AppScaffold(
      title: context.l10n.availability,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'When can you take jobs?',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(7, (i) {
                    // UI index 0=Mon … 6=Sun → day number 1–7
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
                const SizedBox(height: 16),
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
                const SizedBox(height: 16),
                Text(
                  'You can change availability anytime from the dashboard.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.muted,
                      ),
                ),
                const Spacer(),
                PrimaryButton(
                  label: _saving ? 'Saving…' : 'Save & go to dashboard',
                  onPressed: _saving ? null : _saveAndContinue,
                ),
              ],
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/router/route_names.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../../core/utils/toast_utils.dart';
import '../../../auth/presentation/cubit/app_session_cubit.dart';
import '../../../worker/presentation/widgets/worker_sos_sheet.dart';
import '../cubit/sos_cubit.dart';

class SosPage extends StatelessWidget {
  const SosPage({super.key, this.activeBookingId});

  final String? activeBookingId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => SosCubit()..loadContacts(),
      child: _SosPageView(activeBookingId: activeBookingId),
    );
  }
}

class _SosPageView extends StatelessWidget {
  const _SosPageView({this.activeBookingId});

  final String? activeBookingId;

  Future<void> _dialNumber(String number) async {
    final url = Uri.parse('tel:$number');
    if (!await launchUrl(url)) {
      debugPrint('Could not launch $url');
    }
  }

  void _showBookingSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => BlocProvider.value(
        value: context.read<SosCubit>(),
        child: const _EmergencyBookingSheet(),
      ),
    );
  }

  IconData _getIconForContact(String type) {
    switch (type) {
      case 'police':
        return Icons.local_police;
      case 'ambulance':
        return Icons.medical_services;
      case 'fire':
        return Icons.local_fire_department;
      case 'women':
        return Icons.pregnant_woman;
      default:
        return Icons.phone;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Emergency SOS',
      body: BlocConsumer<SosCubit, SosState>(
        listener: (context, state) {
          if (state.error.isNotEmpty) {
            ToastUtils.showToast(context: context, message: state.error);
          }
          if (state.successBookingId != null) {
            ToastUtils.showToast(
              context: context,
              message: 'Emergency broadcast successful!',
            );
            context.go(
              '${RouteNames.customerTracking}?bookingId=${state.successBookingId}',
            );
          }
        },
        builder: (context, state) {
          if (state.isLoadingContacts) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.red),
            );
          }

          if (state.isBroadcasting) {
            return _buildPulsingAnimation(context);
          }

          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              const Text(
                'Emergency Contacts',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: state.contacts.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 1.2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemBuilder: (context, index) {
                  final contact = state.contacts[index];
                  return _buildContactCard(
                    context,
                    contact['name'] ?? '',
                    contact['number'] ?? '',
                    _getIconForContact(contact['icon'] ?? ''),
                  );
                },
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.shade700,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 48,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 12),
                    Builder(
                      builder: (ctx) {
                        final isWorker =
                            ctx.watch<AppSessionCubit>().state.role == 'worker';
                        return Column(
                          children: [
                            Text(
                              isWorker
                                  ? 'Worker Safety Support'
                                  : 'Need Immediate Help?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isWorker
                                  ? 'Helplines + in-job SOS alert to customer / federation.'
                                  : 'Broadcast emergency booking. Platform SOS surcharge applies — not worker-set.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              onPressed: isWorker
                                  ? () => WorkerSosSheet.show(
                                        context,
                                        bookingId: activeBookingId,
                                      )
                                  : () => _showBookingSheet(context),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.red,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.full,
                                  ),
                                ),
                              ),
                              child: Text(
                                isWorker
                                    ? 'Open Worker Safety Helplines'
                                    : 'Create Emergency Booking',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContactCard(
    BuildContext context,
    String title,
    String number,
    IconData icon,
  ) {
    return AppCard(
      child: InkWell(
        onTap: () => _dialNumber(number),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 36, color: Colors.red),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                number,
                style: TextStyle(
                  color: Theme.of(context).hintColor,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPulsingAnimation(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Colors.red),
          const SizedBox(height: 32),
          const Text(
            'Broadcasting Emergency...',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            'Alerting nearby verified workers',
            style: TextStyle(color: Theme.of(context).hintColor),
          ),
        ],
      ),
    );
  }
}

class _EmergencyBookingSheet extends StatefulWidget {
  const _EmergencyBookingSheet();

  @override
  State<_EmergencyBookingSheet> createState() => _EmergencyBookingSheetState();
}

class _EmergencyBookingSheetState extends State<_EmergencyBookingSheet> {
  final _descController = TextEditingController();
  String? _serviceId;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<SosCubit>();
    _serviceId = cubit.state.selectedServiceId;
  }

  Future<void> _submit() async {
    final desc = _descController.text.trim();
    final serviceId = _serviceId ?? context.read<SosCubit>().state.selectedServiceId;
    if (desc.isEmpty) {
      ToastUtils.showToast(
        context: context,
        message: 'Please describe the issue',
      );
      return;
    }
    if (serviceId == null || serviceId.isEmpty) {
      ToastUtils.showToast(
        context: context,
        message: 'No service available. Try again later.',
      );
      return;
    }

    final ok = await context.read<SosCubit>().broadcastEmergencyBooking(
          serviceId: serviceId,
          description: desc,
        );
    if (ok && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return BlocBuilder<SosCubit, SosState>(
      builder: (context, state) {
        final services = state.services;
        final selected = _serviceId ?? state.selectedServiceId;

        return Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Emergency Booking',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'SOS surcharge set by platform settings, not by workers.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).hintColor,
                ),
              ),
              const SizedBox(height: 16),
              if (services.isEmpty)
                const Text('Loading services…')
              else
                DropdownButtonFormField<String>(
                  value: selected != null &&
                          services.any((s) => s.id == selected)
                      ? selected
                      : services.first.id,
                  items: services
                      .map(
                        (s) => DropdownMenuItem(
                          value: s.id,
                          child: Text(
                            '${s.title} (₹${s.priceFrom.toStringAsFixed(0)})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _serviceId = v);
                    context.read<SosCubit>().selectService(v);
                  },
                  decoration: const InputDecoration(labelText: 'Service'),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _descController,
                decoration: const InputDecoration(
                  labelText: 'Describe the emergency',
                  hintText: 'Water pipe burst, short circuit...',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              if (state.isLoadingEstimate)
                const LinearProgressIndicator(color: Colors.red)
              else if (state.estimateTotalMin != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Est. total: ₹${state.estimateTotalMin!.toStringAsFixed(0)}'
                        '${state.estimateTotalMax != null && state.estimateTotalMax != state.estimateTotalMin ? ' – ₹${state.estimateTotalMax!.toStringAsFixed(0)}' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (state.urgentFee != null && state.urgentFee! > 0)
                        Text(
                          'Includes SOS surcharge ₹${state.urgentFee!.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).hintColor,
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: state.isBroadcasting ? 'Broadcasting…' : 'Broadcast Now',
                onPressed: state.isBroadcasting ? null : _submit,
              ),
            ],
          ),
        );
      },
    );
  }
}

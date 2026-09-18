import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/app_radius.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/toast_utils.dart';
import '../../../bookings/data/bookings_api_repository.dart';

class WorkerSosSheet extends StatelessWidget {
  const WorkerSosSheet({super.key, this.bookingId});

  final String? bookingId;

  static void show(BuildContext context, {String? bookingId}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WorkerSosSheet(bookingId: bookingId),
    );
  }

  Future<void> _call(BuildContext context, String number, String label) async {
    final uri = Uri.parse('tel:$number');
    try {
      final launched = await launchUrl(uri);
      if (!launched && context.mounted) {
        ToastUtils.showError(
          context: context,
          message: 'Could not place call to $label ($number)',
        );
      }
    } catch (_) {
      if (context.mounted) {
        ToastUtils.showError(
          context: context,
          message: 'Unable to open phone dialer for $number',
        );
      }
    }
  }

  Future<void> _broadcastDistress(BuildContext context) async {
    final id = bookingId?.trim();
    if (id == null || id.isEmpty) {
      ToastUtils.showError(
        context: context,
        message: 'Open SOS from an active job to alert the customer.',
      );
      return;
    }
    try {
      await BookingsApiRepository().triggerSos(id);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ToastUtils.showSuccess(
        context: context,
        message: 'SOS alert sent to customer / booking room.',
      );
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ToastUtils.showError(context: context, message: e.message);
    } catch (e) {
      if (!context.mounted) return;
      ToastUtils.showError(
        context: context,
        message: ApiException.fromError(e),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasJob = bookingId != null && bookingId!.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.3),
            blurRadius: 30,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.health_and_safety_rounded,
                  color: Colors.red,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Worker Safety & SOS',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    Text(
                      hasJob
                          ? 'In-job alert + national helplines'
                          : 'Helplines — open from active job for in-app SOS',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _EmergencyCard(
                  title: 'National Emergency',
                  subtitle: 'Police, Fire, Ambulance',
                  number: '112',
                  icon: Icons.emergency_rounded,
                  color: const Color(0xFFDC2626),
                  onTap: () => _call(context, '112', 'National Emergency 112'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _EmergencyCard(
                  title: 'Police Control',
                  subtitle: 'Immediate safety assistance',
                  number: '100',
                  icon: Icons.local_police_rounded,
                  color: const Color(0xFF2563EB),
                  onTap: () => _call(context, '100', 'Police 100'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _EmergencyCard(
                  title: 'Medical Ambulance',
                  subtitle: 'Injury / Health distress',
                  number: '108',
                  icon: Icons.medical_services_rounded,
                  color: const Color(0xFF059669),
                  onTap: () => _call(context, '108', 'Ambulance 108'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _EmergencyCard(
                  title: 'Federation Safety Cell',
                  subtitle: 'Worker Cooperative Desk',
                  number: '18002001122',
                  icon: Icons.support_agent_rounded,
                  color: const Color(0xFF7C3AED),
                  onTap: () =>
                      _call(context, '18002001122', 'Federation Safety Cell'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _broadcastDistress(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              elevation: 4,
            ),
            icon: const Icon(Icons.broadcast_on_personal_rounded),
            label: Text(
              hasJob
                  ? 'Send In-Job SOS Alert'
                  : 'Broadcast GPS Distress (needs active job)',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmergencyCard extends StatelessWidget {
  const _EmergencyCard({
    required this.title,
    required this.subtitle,
    required this.number,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String number;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 24),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    number,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isDark ? Colors.white : Colors.black87,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).hintColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

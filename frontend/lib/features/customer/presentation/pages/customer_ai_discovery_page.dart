import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../../shared/models/models.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../home/data/home_api_repository.dart';
import '../../../../core/network/api_exception.dart';

class CustomerAiDiscoveryPage extends StatefulWidget {
  const CustomerAiDiscoveryPage({super.key});

  @override
  State<CustomerAiDiscoveryPage> createState() =>
      _CustomerAiDiscoveryPageState();
}

class _CustomerAiDiscoveryPageState extends State<CustomerAiDiscoveryPage> {
  late final Future<List<ServiceItem>> _future =
      HomeApiRepository().fetchAllServices();

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: context.l10n.aiDiscovery,
      body: FutureBuilder<List<ServiceItem>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text(ApiException.fromError(snap.error!)));
          }
          final services = snap.data ?? const [];

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary.withValues(alpha: 0.15),
                        AppColors.aiBackground,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.auto_awesome,
                              color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text(
                            'AI Recommendations',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Based on your needs, we found these top matches',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ...services.asMap().entries.map(
                      (entry) => _DiscoveryCard(
                        service: entry.value,
                        rank: entry.key + 1,
                        onTap: () => context.push(
                          '/customer/service/${entry.value.id}',
                        ),
                        onWorkers: () =>
                            context.push(RouteNames.customerAiWorkers),
                      ),
                    ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'View Matched Workers',
                  onPressed: () => context.push(RouteNames.customerAiWorkers),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DiscoveryCard extends StatelessWidget {
  const _DiscoveryCard({
    required this.service,
    required this.rank,
    required this.onTap,
    required this.onWorkers,
  });

  final ServiceItem service;
  final int rank;
  final VoidCallback onTap;
  final VoidCallback onWorkers;

  @override
  Widget build(BuildContext context) {
    final matchPercent = 95 - (rank * 5);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accent50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '#$rank Match',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '$matchPercent% match',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              service.title,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              service.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('₹${service.priceFrom.toInt()}+'),
                const Spacer(),
                TextButton(
                  onPressed: onWorkers,
                  child: const Text('See workers'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../../shared/models/models.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/l10n/category_localizer.dart';
import '../../../workers/data/workers_api_repository.dart';

class CustomerAiWorkersPage extends StatefulWidget {
  const CustomerAiWorkersPage({super.key});

  @override
  State<CustomerAiWorkersPage> createState() => _CustomerAiWorkersPageState();
}

class _CustomerAiWorkersPageState extends State<CustomerAiWorkersPage> {
  late final Future<List<WorkerProfile>> _future =
      WorkersApiRepository().fetchNearby();

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: context.l10n.aiMatchedWorkers,
      body: FutureBuilder<List<WorkerProfile>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Text(snap.error.toString()),
            );
          }
          final workers = snap.data ?? const [];
          if (workers.isEmpty) {
            return Center(
              child: Text(
                'No workers nearby yet',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.outline,
                    ),
              ),
            );
          }
          return ListView.builder(
            itemCount: workers.length,
            itemBuilder: (context, index) {
              final worker = workers[index];
              final matchScore = 98 - (index * 4);
              return _AiWorkerTile(
                worker: worker,
                matchScore: matchScore,
                onTap: () => context.push('/customer/worker/${worker.id}'),
              ).appListEnter(
                context,
                index: index,
                id: worker.id,
              );
            },
          );
        },
      ),
    );
  }
}

class _AiWorkerTile extends StatelessWidget {
  const _AiWorkerTile({
    required this.worker,
    required this.matchScore,
    required this.onTap,
  });

  final WorkerProfile worker;
  final int matchScore;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: onTap,
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  child: Text(
                    worker.name.isNotEmpty ? worker.name[0] : 'W',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                if (worker.insured)
                  const Positioned(
                    right: 0,
                    bottom: 0,
                    child: Icon(
                      Icons.verified,
                      size: 16,
                      color: AppColors.accent,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    worker.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    worker.skills.isEmpty
                        ? 'Skilled worker'
                        : localizeCategoryList(
                            worker.skills, context.l10n.locale)
                          .join(' • '),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.star,
                          size: 14, color: AppColors.tertiary),
                      Text(' ${worker.rating}'),
                      const SizedBox(width: 8),
                      Text('${worker.jobsCompleted} jobs'),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$matchScore%',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Text('match', style: TextStyle(fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/l10n/category_localizer.dart';
import '../../../../core/network/api_config.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../../shared/models/models.dart';
import '../../../workers/data/workers_api_repository.dart';

class CustomerWorkersPage extends StatefulWidget {
  const CustomerWorkersPage({super.key});

  @override
  State<CustomerWorkersPage> createState() => _CustomerWorkersPageState();
}

class _CustomerWorkersPageState extends State<CustomerWorkersPage> {
  late Future<List<WorkerProfile>> _future =
      WorkersApiRepository().fetchNearby();

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: context.l10n.availableWorkers,
      body: FutureBuilder<List<WorkerProfile>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(snap.error.toString()),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    label: 'Retry',
                    onPressed: () => setState(() {
                      _future = WorkersApiRepository().fetchNearby();
                    }),
                  ),
                ],
              ),
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
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${workers.length} verified workers nearby',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.outline,
                    ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: workers.length,
                  itemBuilder: (context, index) {
                    final worker = workers[index];
                    return _WorkerListTile(
                      worker: worker,
                      onTap: () =>
                          context.push('/customer/worker/${worker.id}'),
                    ).appListEnter(
                      context,
                      index: index,
                      id: worker.id,
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WorkerListTile extends StatelessWidget {
  const _WorkerListTile({
    required this.worker,
    required this.onTap,
  });

  final WorkerProfile worker;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: onTap,
        child: Row(
          children: [
            _WorkerAvatar(worker: worker),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    worker.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    worker.skills.isEmpty
                        ? 'Skilled worker'
                        : localizeCategoryList(
                            worker.skills.take(3), context.l10n.locale)
                          .join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star, size: 16, color: AppColors.accent),
                      Text(' ${worker.rating}'),
                      const SizedBox(width: 12),
                      Text('${worker.jobsCompleted} jobs'),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class _WorkerAvatar extends StatelessWidget {
  const _WorkerAvatar({required this.worker});

  final WorkerProfile worker;

  @override
  Widget build(BuildContext context) {
    final avatar = worker.avatarUrl?.trim();
    Widget imageWidget;

    if (avatar != null && avatar.isNotEmpty) {
      if (avatar.startsWith('data:image')) {
        try {
          final commaIndex = avatar.indexOf(',');
          final base64String =
              commaIndex != -1 ? avatar.substring(commaIndex + 1) : avatar;
          final bytes = base64Decode(base64String);
          imageWidget = Image.memory(
            bytes,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _fallback(),
          );
        } catch (_) {
          imageWidget = _fallback();
        }
      } else {
        final fullUrl = avatar.startsWith('http')
            ? avatar
            : '${ApiConfig.baseUrl}${avatar.startsWith('/') ? '' : '/'}$avatar';
        imageWidget = Image.network(
          fullUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _fallback(),
        );
      }
    } else {
      imageWidget = _fallback();
    }

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: imageWidget,
      ),
    );
  }

  Widget _fallback() {
    final initial = worker.name.trim().isNotEmpty
        ? worker.name.trim()[0].toUpperCase()
        : 'W';
    return Container(
      color: AppColors.primary.withValues(alpha: 0.1),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

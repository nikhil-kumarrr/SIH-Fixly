import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/theme_x.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../payments/data/payments_api_repository.dart';
import '../../../../core/network/api_exception.dart';

class CustomerPaymentsPage extends StatefulWidget {
  const CustomerPaymentsPage({super.key});

  @override
  State<CustomerPaymentsPage> createState() => _CustomerPaymentsPageState();
}

class _CustomerPaymentsPageState extends State<CustomerPaymentsPage> {
  final _payments = PaymentsApiRepository();
  late Future<WalletSnapshot> _future;

  @override
  void initState() {
    super.initState();
    _future = _payments.walletHistory();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _payments.walletHistory();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('d MMM yyyy, hh:mm a');
    return AppScaffold(
      title: 'Payment history',
      showBack: true,
      body: AppRefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<WalletSnapshot>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return ListView(
                physics: appRefreshScrollPhysics,
                children: const [
                  SizedBox(height: 120),
                  Center(child: CircularProgressIndicator()),
                ],
              );
            }
            if (snap.hasError) {
              final scheme = Theme.of(context).colorScheme;
              return ListView(
                physics: appRefreshScrollPhysics,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 40,
                ),
                children: [
                  SizedBox(height: MediaQuery.sizeOf(context).height * 0.15),
                  Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: scheme.error.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.error_outline_rounded,
                        size: 40,
                        color: scheme.error,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Text(
                      'Failed to load payment history',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      ApiException.fromError(snap.error!),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                    ),
                  ),
                ],
              );
            }
            final data = snap.data!;
            final history = data.history;
            if (history.isEmpty) {
              return ListView(
                physics: appRefreshScrollPhysics,
                padding: const EdgeInsets.all(24),
                children: [
                  SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
                  Icon(
                    Icons.payments_outlined,
                    size: 64,
                    color: context.scheme.outline,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No payments yet',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              );
            }
            return ListView.separated(
              physics: appRefreshScrollPhysics,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: history.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total spent',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: context.muted),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₹${data.totalEarnings.toStringAsFixed(0)}',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: context.scheme.primary,
                              ),
                        ),
                      ],
                    ),
                  );
                }
                final tx = history[index - 1];
                final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
                final payId = (tx['transactionId'] ?? '').toString();
                final desc = (tx['description'] ?? 'Razorpay payment')
                    .toString();
                final status = (tx['status'] ?? '').toString();
                final created = DateTime.tryParse(
                  tx['createdAt']?.toString() ?? '',
                );
                return AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              desc,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Text(
                            '₹${amount.toStringAsFixed(0)}',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      if (payId.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Razorpay ID: $payId',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: context.muted),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (status.isNotEmpty) status,
                          if (created != null) dateFormat.format(created),
                        ].join(' • '),
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: context.muted),
                      ),
                    ],
                  ),
                ).appListEnter(context, index: index, id: payId);
              },
            );
          },
        ),
      ),
    );
  }
}

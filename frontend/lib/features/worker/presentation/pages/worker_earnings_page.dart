import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/theme_x.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../payments/data/payments_api_repository.dart';
import '../../../../core/network/api_exception.dart';

class WorkerEarningsPage extends StatefulWidget {
  const WorkerEarningsPage({super.key});

  @override
  State<WorkerEarningsPage> createState() => _WorkerEarningsPageState();
}

class _WorkerEarningsPageState extends State<WorkerEarningsPage> {
  final _payments = PaymentsApiRepository();

  bool _loading = true;
  String? _error;

  // View toggle: 0 = Simple, 1 = Advanced Analytics
  int _selectedView = 0;

  // Analytics filter: '7D' (Last 7 Days), '30D' (This Month), 'ALL' (All Time)
  String _analyticsPeriod = '7D';

  double _today = 0;
  double _thisWeek = 0;
  double _thisMonth = 0;
  double _totalEarned = 0;
  int _completedJobs = 0;
  List<Map<String, dynamic>> _txs = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await _payments.workerEarningsSummary();
      final wallet = await _payments.workerWallet();
      if (!mounted) return;

      setState(() {
        _today = (summary['today'] as num?)?.toDouble() ?? 0;
        _thisWeek = (summary['thisWeek'] as num?)?.toDouble() ?? 0;
        _thisMonth = (summary['thisMonth'] as num?)?.toDouble() ?? 0;
        _totalEarned = (summary['totalEarned'] as num?)?.toDouble() ??
            (summary['totalEarnings'] as num?)?.toDouble() ??
            0;
        _completedJobs = (summary['completedJobs'] as num?)?.toInt() ?? 0;
        _txs = wallet.history;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiException.fromError(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final scheme = context.scheme;
    final primaryColor = scheme.primary;

    return AppScaffold(
      title: context.l10n.earnings,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : AppRefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: appRefreshScrollPhysics,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    children: [
                      // View mode toggle switch (Simple vs Advanced)
                      _buildViewSwitcher(primaryColor, isDark),

                      const SizedBox(height: 16),

                      if (_selectedView == 0)
                        ..._buildSimpleView(context, isDark, primaryColor)
                      else
                        ..._buildAdvancedView(context, isDark, primaryColor),
                    ],
                  ),
                ),
    );
  }

  // View Switcher (Simple vs Advanced Analytics)
  Widget _buildViewSwitcher(Color primaryColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ViewTabButton(
              title: 'Simple View',
              icon: Icons.dashboard_outlined,
              isSelected: _selectedView == 0,
              primaryColor: primaryColor,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _selectedView = 0);
              },
            ),
          ),
          Expanded(
            child: _ViewTabButton(
              title: 'Advanced Analytics',
              icon: Icons.auto_graph_rounded,
              isSelected: _selectedView == 1,
              primaryColor: primaryColor,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _selectedView = 1);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // SIMPLE VIEW
  // ==========================================
  List<Widget> _buildSimpleView(
    BuildContext context,
    bool isDark,
    Color primaryColor,
  ) {
    return [
      // Hero Today's Earnings
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1E3A8A),
              primaryColor,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: primaryColor.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Today's Earnings",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    DateFormat('d MMM yyyy').format(DateTime.now()),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '₹${_today.toStringAsFixed(0)}',
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildHeroStatPill(
                    label: 'This Week',
                    value: '₹${_thisWeek.toStringAsFixed(0)}',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildHeroStatPill(
                    label: 'This Month',
                    value: '₹${_monthFormatted()}',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),

      const SizedBox(height: 16),

      // Summary Cards Grid
      Row(
        children: [
          Expanded(
            child: _buildMetricCard(
              title: 'Total Lifetime',
              value: '₹${_totalEarned.toStringAsFixed(0)}',
              subtitle: 'All-time gross',
              icon: Icons.account_balance_wallet_outlined,
              isDark: isDark,
              primaryColor: primaryColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildMetricCard(
              title: 'Jobs Done',
              value: '$_completedJobs',
              subtitle: _completedJobs > 0
                  ? 'Avg ₹${(_totalEarned / _completedJobs).round()}/job'
                  : 'No jobs yet',
              icon: Icons.assignment_turned_in_outlined,
              isDark: isDark,
              primaryColor: primaryColor,
            ),
          ),
        ],
      ),

      const SizedBox(height: 20),

      // Recent Transactions Title
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Recent Payouts & Bookings',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          Text(
            '${_txs.length} total',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : const Color(0xFF64748B),
            ),
          ),
        ],
      ),

      const SizedBox(height: 10),

      if (_txs.isEmpty)
        _buildEmptyState(isDark)
      else
        ..._txs.take(15).map((tx) => _buildSimpleTransactionTile(tx, isDark, primaryColor)),
    ];
  }

  String _monthFormatted() {
    return _thisMonth.toStringAsFixed(0);
  }

  Widget _buildHeroStatPill({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required bool isDark,
    required Color primaryColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white60 : const Color(0xFF64748B),
                ),
              ),
              Icon(icon, size: 16, color: primaryColor),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleTransactionTile(
    Map<String, dynamic> tx,
    bool isDark,
    Color primaryColor,
  ) {
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
    final isCredit = (tx['type'] ?? 'CREDIT').toString().toUpperCase() != 'DEBIT';
    final sign = isCredit ? '+' : '-';
    final color = isCredit ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final desc = (tx['description'] ?? tx['status'] ?? 'Service Booking').toString();
    final dateRaw = tx['createdAt']?.toString();
    final date = dateRaw != null ? DateTime.tryParse(dateRaw) : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
              color: color,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  desc,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (date != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('d MMM, hh:mm a').format(date),
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            '$sign₹${amount.abs().toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // ADVANCED ANALYTICS VIEW (WITH FL_CHART)
  // ==========================================
  List<Widget> _buildAdvancedView(
    BuildContext context,
    bool isDark,
    Color primaryColor,
  ) {
    final analyticsData = _computeAnalyticsData();

    return [
      // Time Period Filter
      _buildAnalyticsPeriodFilter(primaryColor, isDark),

      const SizedBox(height: 16),

      // Interactive Earnings Bar Chart
      _buildEarningsChartCard(analyticsData, isDark, primaryColor),

      const SizedBox(height: 16),

      // Commission & Fair Deductions Breakdown Card
      _buildCommissionBreakdownCard(isDark, primaryColor),

      const SizedBox(height: 16),

      // Bookings & Earnings Ledger Breakdown
      _buildBookingsLedger(isDark, primaryColor),
    ];
  }

  Widget _buildAnalyticsPeriodFilter(Color primaryColor, bool isDark) {
    final options = [
      {'key': '7D', 'label': 'Last 7 Days'},
      {'key': '30D', 'label': 'This Month'},
      {'key': 'ALL', 'label': 'All Time'},
    ];

    return Row(
      children: options.map((opt) {
        final isSelected = _analyticsPeriod == opt['key'];
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _analyticsPeriod = opt['key']!);
            },
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected
                    ? primaryColor
                    : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected
                      ? primaryColor
                      : (isDark ? Colors.white12 : const Color(0xFFCBD5E1)),
                ),
              ),
              child: Text(
                opt['label']!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.white70 : const Color(0xFF475569)),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  List<_DayEarning> _computeAnalyticsData() {
    final now = DateTime.now();
    final List<_DayEarning> days = [];

    if (_analyticsPeriod == '7D') {
      for (int i = 6; i >= 0; i--) {
        final d = now.subtract(Duration(days: i));
        final dayLabel = DateFormat('E').format(d); // Mon, Tue, etc.
        double amount = 0;

        for (final tx in _txs) {
          final raw = tx['createdAt']?.toString();
          if (raw != null) {
            final txDate = DateTime.tryParse(raw);
            if (txDate != null &&
                txDate.year == d.year &&
                txDate.month == d.month &&
                txDate.day == d.day) {
              final val = (tx['amount'] as num?)?.toDouble() ?? 0;
              final isCredit = (tx['type'] ?? 'CREDIT').toString().toUpperCase() != 'DEBIT';
              if (isCredit) amount += val;
            }
          }
        }
        days.add(_DayEarning(label: dayLabel, amount: amount));
      }
    } else {
      // 4 weekly blocks
      for (int i = 3; i >= 0; i--) {
        final weekStart = now.subtract(Duration(days: (i + 1) * 7));
        final weekEnd = now.subtract(Duration(days: i * 7));
        double amount = 0;

        for (final tx in _txs) {
          final raw = tx['createdAt']?.toString();
          if (raw != null) {
            final txDate = DateTime.tryParse(raw);
            if (txDate != null &&
                txDate.isAfter(weekStart) &&
                txDate.isBefore(weekEnd.add(const Duration(days: 1)))) {
              final val = (tx['amount'] as num?)?.toDouble() ?? 0;
              final isCredit = (tx['type'] ?? 'CREDIT').toString().toUpperCase() != 'DEBIT';
              if (isCredit) amount += val;
            }
          }
        }
        days.add(_DayEarning(label: 'Wk ${4 - i}', amount: amount));
      }
    }

    return days;
  }

  // Earnings Bar Chart with fl_chart
  Widget _buildEarningsChartCard(
    List<_DayEarning> data,
    bool isDark,
    Color primaryColor,
  ) {
    double maxVal = 100;
    for (final d in data) {
      if (d.amount > maxVal) maxVal = d.amount;
    }
    maxVal = (maxVal * 1.25).ceilToDouble();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Earnings Trend',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _analyticsPeriod == '7D'
                        ? 'Daily revenue over the last 7 days'
                        : 'Weekly earnings breakdown',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white54 : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              Icon(Icons.bar_chart_rounded, color: primaryColor),
            ],
          ),

          const SizedBox(height: 24),

          // FL Chart Container
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxVal,
                minY: 0,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final item = data[group.x.toInt()];
                      return BarTooltipItem(
                        '${item.label}\n₹${item.amount.toStringAsFixed(0)}',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      getTitlesWidget: (value, meta) {
                        if (value == 0 || value == maxVal || value == (maxVal / 2).roundToDouble()) {
                          return Text(
                            '₹${value >= 1000 ? '${(value / 1000).toStringAsFixed(1)}k' : value.toInt()}',
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx >= 0 && idx < data.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              data[idx].label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white70 : const Color(0xFF475569),
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxVal / 3,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: data.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final item = entry.value;
                  return BarChartGroupData(
                    x: idx,
                    barRods: [
                      BarChartRodData(
                        toY: item.amount,
                        gradient: LinearGradient(
                          colors: [
                            primaryColor,
                            primaryColor.withValues(alpha: 0.75),
                          ],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                        width: 18,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Commission & Deductions Breakdown Card
  Widget _buildCommissionBreakdownCard(bool isDark, Color primaryColor) {
    final grossTotal = _totalEarned > 0 ? _totalEarned / 0.975 : 0;
    final platformFee = grossTotal * 0.02;
    final welfareFund = grossTotal * 0.005;
    final netTakeHome = _totalEarned;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pie_chart_outline_rounded, size: 18, color: primaryColor),
              const SizedBox(width: 8),
              Text(
                'Fair Share & Deductions Breakdown',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Cooperative worker payout guarantee: 97.5% net take-home',
            style: TextStyle(
              fontSize: 11.5,
              color: isDark ? Colors.white54 : const Color(0xFF64748B),
            ),
          ),

          const SizedBox(height: 16),

          // Visual horizontal multi-bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  Expanded(
                    flex: 975,
                    child: Container(color: const Color(0xFF10B981)),
                  ),
                  Expanded(
                    flex: 20,
                    child: Container(color: primaryColor),
                  ),
                  Expanded(
                    flex: 5,
                    child: Container(color: Colors.amber.shade700),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Line items
          _buildDeductionRow(
            dotColor: const Color(0xFF10B981),
            label: 'Net Worker Payout (Take-Home)',
            percentage: '97.5%',
            amount: '₹${netTakeHome.toStringAsFixed(0)}',
            isDark: isDark,
            isBold: true,
          ),
          const SizedBox(height: 8),
          _buildDeductionRow(
            dotColor: primaryColor,
            label: 'Fixly Platform Tech Fee',
            percentage: '2.0%',
            amount: '₹${platformFee.toStringAsFixed(0)}',
            isDark: isDark,
          ),
          const SizedBox(height: 8),
          _buildDeductionRow(
            dotColor: Colors.amber.shade700,
            label: 'e-Shram Worker Welfare Fund',
            percentage: '0.5%',
            amount: '₹${welfareFund.toStringAsFixed(0)}',
            isDark: isDark,
          ),

          const SizedBox(height: 14),
          Divider(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0), height: 1),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Gross Customer Booking Value',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : const Color(0xFF475569),
                ),
              ),
              Text(
                '₹${grossTotal.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeductionRow({
    required Color dotColor,
    required String label,
    required String percentage,
    required String amount,
    required bool isDark,
    bool isBold = false,
  }) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
              color: isBold
                  ? (isDark ? Colors.white : const Color(0xFF0F172A))
                  : (isDark ? Colors.white70 : const Color(0xFF475569)),
            ),
          ),
        ),
        Text(
          percentage,
          style: TextStyle(
            fontSize: 11.5,
            color: isDark ? Colors.white54 : const Color(0xFF64748B),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          amount,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            color: isBold ? const Color(0xFF10B981) : null,
          ),
        ),
      ],
    );
  }

  // Bookings Ledger
  Widget _buildBookingsLedger(bool isDark, Color primaryColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Booking Payout Ledger',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 10),
        if (_txs.isEmpty)
          _buildEmptyState(isDark)
        else
          ..._txs.map((tx) => _buildLedgerTile(tx, isDark, primaryColor)),
      ],
    );
  }

  Widget _buildLedgerTile(
    Map<String, dynamic> tx,
    bool isDark,
    Color primaryColor,
  ) {
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
    final isCredit = (tx['type'] ?? 'CREDIT').toString().toUpperCase() != 'DEBIT';
    final desc = (tx['description'] ?? tx['status'] ?? 'Customer Booking').toString();
    final dateRaw = tx['createdAt']?.toString();
    final date = dateRaw != null ? DateTime.tryParse(dateRaw) : null;
    final txId = (tx['transactionId'] ?? tx['id'] ?? '').toString();

    final gross = isCredit ? (amount / 0.975) : amount;
    final fee = isCredit ? (gross * 0.02) : 0.0;
    final welfare = isCredit ? (gross * 0.005) : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  desc,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                isCredit
                    ? '+₹${amount.toStringAsFixed(0)}'
                    : '-₹${amount.abs().toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: isCredit ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                date != null ? DateFormat('d MMM yyyy • hh:mm a').format(date) : '',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white54 : const Color(0xFF64748B),
                ),
              ),
              if (txId.isNotEmpty)
                Text(
                  'ID: ${txId.length > 12 ? txId.substring(0, 12) : txId}',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
            ],
          ),
          if (isCredit) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Gross: ₹${gross.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    ),
                  ),
                  Text(
                    'Platform: -₹${fee.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    ),
                  ),
                  Text(
                    'Welfare: -₹${welfare.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 40,
              color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
            ),
            const SizedBox(height: 10),
            Text(
              'No earnings yet',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : const Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'As you complete customer jobs, your earnings & analytics will appear here.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : const Color(0xFF64748B),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewTabButton extends StatelessWidget {
  const _ViewTabButton({
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.primaryColor,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool isSelected;
  final Color primaryColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : Colors.grey.shade600,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayEarning {
  const _DayEarning({required this.label, required this.amount});

  final String label;
  final double amount;
}

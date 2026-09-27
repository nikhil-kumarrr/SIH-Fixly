import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../auth/data/auth_api_repository.dart';
import '../../../workers/data/workers_api_repository.dart';
import '../../../../core/network/api_exception.dart';

class WorkerReliabilityPage extends StatefulWidget {
  const WorkerReliabilityPage({super.key});

  @override
  State<WorkerReliabilityPage> createState() => _WorkerReliabilityPageState();
}

class _WorkerReliabilityPageState extends State<WorkerReliabilityPage> {
  final _auth = AuthApiRepository();
  final _workers = WorkersApiRepository();
  bool _loading = true;
  String? _error;

  int _score = 0;
  int _onTime = 0;
  int _completion = 0;
  double _rating = 0;
  int _completedJobs = 0;
  int _customerFeedback = 0;
  int _cancellationRate = 100;

  // Selected tab: 0 = Overview & Metrics, 1 = Score Rules & Factors, 2 = Partner Tiers & Benefits
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final user = await _auth.fetchMe();
      final data = await _workers.fetchReliability(user.id);
      if (!mounted) return;
      setState(() {
        _score = (data['score'] as num?)?.toInt() ?? 0;
        _onTime = (data['onTimeArrival'] as num?)?.toInt() ?? 0;
        _completion = (data['completionRate'] as num?)?.toInt() ?? 0;
        _rating = (data['rating'] as num?)?.toDouble() ?? 0.0;
        _completedJobs = (data['completedJobs'] as num?)?.toInt() ?? 0;
        _customerFeedback = (data['customerFeedback'] as num?)?.toInt() ?? 0;
        _cancellationRate = (data['cancellationRate'] as num?)?.toInt() ?? 100;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiException.fromError(e);
        _loading = false;
      });
    }
  }

  Color _getScoreColor() {
    if (_score >= 90) return const Color(0xFF10B981); // Emerald
    if (_score >= 75) return AppColors.primary; // Royal Blue
    if (_score >= 60) return const Color(0xFFF59E0B); // Amber
    return const Color(0xFFEF4444); // Red
  }

  String _getTierName() {
    if (_score >= 90) return 'Elite Partner';
    if (_score >= 75) return 'Good Standing';
    if (_score >= 60) return 'Needs Improvement';
    return 'Critical Standing';
  }

  IconData _getTierIcon() {
    if (_score >= 90) return Icons.workspace_premium_rounded;
    if (_score >= 75) return Icons.verified_rounded;
    if (_score >= 60) return Icons.warning_amber_rounded;
    return Icons.error_outline_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return AppScaffold(
      title: context.l10n.reliabilityScore,
      showBack: true,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : AppRefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: appRefreshScrollPhysics,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: _error != null
                    ? SizedBox(
                        height: 360,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.cloud_off_rounded,
                                size: 48,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 14),
                              ),
                              const SizedBox(height: 16),
                              FilledButton.tonalIcon(
                                onPressed: () {
                                  setState(() => _loading = true);
                                  _load();
                                },
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1. Hero Score & Standing Card
                          _buildHeroScoreCard(isDark, primaryColor),

                          const SizedBox(height: 16),

                          // 2. Segmented Navigation Tabs
                          _buildSegmentedTabSelector(isDark, primaryColor),

                          const SizedBox(height: 16),

                          // 3. Tab Content
                          if (_selectedTab == 0)
                            _buildOverviewAndMetricsTab(isDark, primaryColor)
                          else if (_selectedTab == 1)
                            _buildRulesAndFactorsTab(isDark, primaryColor)
                          else
                            _buildTiersAndPerksTab(isDark, primaryColor),

                          const SizedBox(height: 32),
                        ],
                      ),
              ),
            ),
    );
  }

  // -------------------------------------------------------------
  // 1. HERO SCORE & TIER CARD
  // -------------------------------------------------------------
  Widget _buildHeroScoreCard(bool isDark, Color primaryColor) {
    final scoreColor = _getScoreColor();
    final tierName = _getTierName();
    final tierIcon = _getTierIcon();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Circular score gauge
              SizedBox(
                width: 110,
                height: 110,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 110,
                      height: 110,
                      child: CircularProgressIndicator(
                        value: (_score / 100).clamp(0.0, 1.0),
                        strokeWidth: 9,
                        strokeCap: StrokeCap.round,
                        backgroundColor: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFE2E8F0),
                        color: scoreColor,
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$_score%',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          'Overall',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white54 : const Color(0xFF64748B),
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 20),

              // Status and tier details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: scoreColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: scoreColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(tierIcon, size: 14, color: scoreColor),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              tierName.toUpperCase(),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: scoreColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _score >= 90
                          ? 'Priority Job Matching Active'
                          : _score >= 75
                              ? 'Standard Dispatch Standing'
                              : _score >= 60
                                  ? 'Dispatch Priority Reduced'
                                  : 'Account Needs Attention',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _score >= 75
                          ? 'You are receiving direct job requests in your 10 km service radius.'
                          : 'Complete upcoming jobs on time to restore your Elite partner status.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: isDark ? Colors.white60 : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),

          // Bottom Quick Snapshot Chips
          Row(
            children: [
              _buildQuickStatPill(
                icon: Icons.check_circle_outline_rounded,
                label: '$_completedJobs Done',
                color: const Color(0xFF10B981),
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _buildQuickStatPill(
                icon: Icons.star_rounded,
                label: '${_rating.toStringAsFixed(1)} Rating',
                color: const Color(0xFFF59E0B),
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _buildQuickStatPill(
                icon: Icons.timer_outlined,
                label: '$_onTime% On-Time',
                color: primaryColor,
                isDark: isDark,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStatPill({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : const Color(0xFF334155),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // 2. SEGMENTED NAVIGATION TABS
  // -------------------------------------------------------------
  Widget _buildSegmentedTabSelector(bool isDark, Color primaryColor) {
    final tabs = [
      {'title': 'Metrics', 'icon': Icons.bar_chart_rounded},
      {'title': 'How It Works', 'icon': Icons.rule_folder_outlined},
      {'title': 'Tiers & Perks', 'icon': Icons.military_tech_outlined},
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: List.generate(tabs.length, (index) {
          final isSelected = _selectedTab == index;
          final tab = tabs[index];
          return Expanded(
            child: InkWell(
              onTap: () => setState(() => _selectedTab = index),
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isDark ? primaryColor : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      tab['icon'] as IconData,
                      size: 14,
                      color: isSelected
                          ? (isDark ? Colors.white : primaryColor)
                          : (isDark ? Colors.white54 : const Color(0xFF64748B)),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        tab['title'] as String,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected
                              ? (isDark ? Colors.white : primaryColor)
                              : (isDark ? Colors.white60 : const Color(0xFF64748B)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 1: OVERVIEW & PERFORMANCE METRICS
  // -------------------------------------------------------------
  Widget _buildOverviewAndMetricsTab(bool isDark, Color primaryColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Title
        Text(
          'Core Performance Factors',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 10),

        // 4 Grid Metric Cards
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                title: 'On-Time Arrival',
                value: '$_onTime%',
                benchmark: 'Target > 90%',
                icon: Icons.timer_outlined,
                color: const Color(0xFF2563EB),
                percent: (_onTime / 100).clamp(0.0, 1.0),
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricTile(
                title: 'Job Completion',
                value: '$_completion%',
                benchmark: 'Target > 95%',
                icon: Icons.task_alt_rounded,
                color: const Color(0xFF10B981),
                percent: (_completion / 100).clamp(0.0, 1.0),
                isDark: isDark,
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                title: 'Customer Rating',
                value: '${_rating.toStringAsFixed(1)} ★',
                benchmark: 'Benchmark 4.5+ ★',
                icon: Icons.star_rounded,
                color: const Color(0xFFF59E0B),
                percent: (_rating / 5.0).clamp(0.0, 1.0),
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricTile(
                title: 'Non-Cancellation',
                value: '$_cancellationRate%',
                benchmark: 'Target > 95%',
                icon: Icons.shield_outlined,
                color: const Color(0xFF8B5CF6),
                percent: (_cancellationRate / 100).clamp(0.0, 1.0),
                isDark: isDark,
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Formula Calculation Weightage Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
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
                    'Score Calculation Weightage',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildWeightageRow('Job Completion Rate', '40%', const Color(0xFF10B981), isDark),
              const SizedBox(height: 8),
              _buildWeightageRow(
                _customerFeedback > 0
                    ? 'Customer Reviews & Ratings ($_customerFeedback% Positive)'
                    : 'Customer Reviews & Ratings',
                '35%',
                const Color(0xFFF59E0B),
                isDark,
              ),
              const SizedBox(height: 8),
              _buildWeightageRow('Non-Cancellation & On-Time', '25%', primaryColor, isDark),
              const SizedBox(height: 12),
              Text(
                'The composite reliability index updates automatically upon completion of every booking and verified customer rating.',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  color: isDark ? Colors.white54 : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Quick Tips Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? const Color(0xFF10B981).withValues(alpha: 0.3)
                  : const Color(0xFFBBF7D0),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lightbulb_outline_rounded,
                  size: 18,
                  color: Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How to Maintain an Elite Score',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark ? const Color(0xFF86EFAC) : const Color(0xFF166534),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Always mark your availability toggle to "Offline" when taking a break. Rejecting requests while online will not harm your score, but cancelling accepted bookings will.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: isDark ? Colors.white70 : const Color(0xFF14532D),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required String benchmark,
    required IconData icon,
    required Color color,
    required double percent,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
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
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  benchmark,
                  textAlign: TextAlign.end,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 5,
              backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeightageRow(String factor, String weight, Color color, bool isDark) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            factor,
            style: TextStyle(
              fontSize: 12.5,
              color: isDark ? Colors.white70 : const Color(0xFF334155),
            ),
          ),
        ),
        Text(
          weight,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------
  // TAB 2: RULES, INCREASE & DECREASE FACTORS (TERMS & CONDITIONS)
  // -------------------------------------------------------------
  Widget _buildRulesAndFactorsTab(bool isDark, Color primaryColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. How Score Increases Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
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
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.trending_up_rounded,
                      size: 18,
                      color: Color(0xFF10B981),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'How Your Score Increases',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          'Earn points by delivering consistent quality service',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark ? Colors.white54 : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildFactorItem(
                icon: Icons.check_circle_rounded,
                iconColor: const Color(0xFF10B981),
                title: 'Completing Accepted Bookings (+0.5% – +1.0%)',
                description:
                    'Every successfully finished job confirmed by customer OTP directly boosts your completion index.',
                isDark: isDark,
              ),
              const SizedBox(height: 12),
              _buildFactorItem(
                icon: Icons.timer_outlined,
                iconColor: const Color(0xFF10B981),
                title: 'On-Time Arrival (+Punctuality)',
                description:
                    'Reaching customer doorsteps within your estimated arrival time maintains a 100% on-time record.',
                isDark: isDark,
              ),
              const SizedBox(height: 12),
              _buildFactorItem(
                icon: Icons.star_rounded,
                iconColor: const Color(0xFF10B981),
                title: '5-Star Customer Ratings (+35% Weight)',
                description:
                    'High ratings for courteous behavior, cleanliness, and honest pricing raise your composite score.',
                isDark: isDark,
              ),
              const SizedBox(height: 12),
              _buildFactorItem(
                icon: Icons.flash_on_rounded,
                iconColor: const Color(0xFF10B981),
                title: 'Fast Acceptance of Urgent SOS Jobs',
                description:
                    'Accepting emergency dispatch requests within 30 seconds yields responsiveness bonuses.',
                isDark: isDark,
              ),
              const SizedBox(height: 12),
              _buildFactorItem(
                icon: Icons.local_fire_department_rounded,
                iconColor: const Color(0xFF10B981),
                title: '10-Job Completion Streaks',
                description:
                    'Completing 10 consecutive jobs without any worker cancellation activates reliability score shields.',
                isDark: isDark,
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 2. What Decreases Your Score Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
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
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.trending_down_rounded,
                      size: 18,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'What Decreases Your Score',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          'Penalties applied for reliability violations',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark ? Colors.white54 : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildFactorItem(
                icon: Icons.cancel_outlined,
                iconColor: const Color(0xFFEF4444),
                title: 'Worker-Initiated Cancellation (-3% to -5%)',
                description:
                    'Cancelling a booking after you have accepted it causes distress to the customer and reduces your score.',
                isDark: isDark,
              ),
              const SizedBox(height: 12),
              _buildFactorItem(
                icon: Icons.person_off_outlined,
                iconColor: const Color(0xFFEF4444),
                title: 'No-Show Without Notice (-10% Severe)',
                description:
                    'Failing to arrive at a confirmed booking without prior notification incurs a 10% penalty and temporary dispatch cooldown.',
                isDark: isDark,
              ),
              const SizedBox(height: 12),
              _buildFactorItem(
                icon: Icons.more_time_rounded,
                iconColor: const Color(0xFFF59E0B),
                title: 'Late Arrivals Over 20 Mins (-Punctuality)',
                description:
                    'Arriving significantly past your arrival estimate without updating the customer in chat degrades on-time metrics.',
                isDark: isDark,
              ),
              const SizedBox(height: 12),
              _buildFactorItem(
                icon: Icons.report_problem_outlined,
                iconColor: const Color(0xFFEF4444),
                title: 'Customer Escalations & Bad Ratings',
                description:
                    'Ratings below 3 stars or verified disputes regarding unfinished work or pricing violations heavily degrade customer score.',
                isDark: isDark,
              ),
              const SizedBox(height: 12),
              _buildFactorItem(
                icon: Icons.notifications_paused_outlined,
                iconColor: const Color(0xFFF59E0B),
                title: 'Repeated Alert Timeouts While Online',
                description:
                    'Letting multiple job alerts ring out without responding while marked "Available" temporarily lowers search rank.',
                isDark: isDark,
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 3. Fair Appeal Terms & Protection
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? primaryColor.withValues(alpha: 0.3)
                  : const Color(0xFFBFDBFE),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.verified_user_rounded, size: 18, color: primaryColor),
                  const SizedBox(width: 8),
                  Text(
                    'Worker Protection & Appeal Rights',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF1E40AF),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'You are never penalized for factors beyond your control. If a booking was cancelled because:\n'
                '• The customer was unreachable for 15+ minutes\n'
                '• The customer provided an incorrect or unsafe address\n'
                '• The scope of work differed drastically from request\n\n'
                'Submit an appeal via Support within 48 hours with proof to automatically restore any deducted score points.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: isDark ? Colors.white70 : const Color(0xFF1E3A8A),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFactorItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 14, color: iconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  color: isDark ? Colors.white60 : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------
  // TAB 3: PARTNER TIERS & BENEFITS GUIDE
  // -------------------------------------------------------------
  Widget _buildTiersAndPerksTab(bool isDark, Color primaryColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Fixly Partner Tiers & Privileges',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Higher reliability unlocks priority dispatch matching and faster payouts.',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white54 : const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 14),

        // Tier 1: Elite Partner
        _buildTierCard(
          tierName: 'Elite Partner',
          scoreRange: '90% – 100%',
          color: const Color(0xFF10B981),
          icon: Icons.workspace_premium_rounded,
          isCurrent: _score >= 90,
          benefits: [
            'Immediate priority broadcast for emergency & scheduled jobs within 10 km.',
            'Verified "Elite Worker" gold badge displayed on customer booking cards.',
            'Access to high-budget commercial and cooperative enterprise projects.',
            'Instant, zero-fee withdrawals straight to your linked UPI ID.',
          ],
          isDark: isDark,
        ),

        const SizedBox(height: 12),

        // Tier 2: Good Standing
        _buildTierCard(
          tierName: 'Good Standing',
          scoreRange: '75% – 89%',
          color: AppColors.primary,
          icon: Icons.verified_rounded,
          isCurrent: _score >= 75 && _score < 90,
          benefits: [
            'Standard job broadcast matching across all service categories.',
            'Full access to daily job feed and active booking notifications.',
            'Standard withdrawal processing via UPI and IMPS bank transfer.',
          ],
          isDark: isDark,
        ),

        const SizedBox(height: 12),

        // Tier 3: Needs Improvement
        _buildTierCard(
          tierName: 'Needs Improvement',
          scoreRange: '60% – 74%',
          color: const Color(0xFFF59E0B),
          icon: Icons.warning_amber_rounded,
          isCurrent: _score >= 60 && _score < 75,
          benefits: [
            'Secondary dispatch priority behind Elite and Good Standing partners.',
            'Score Restoration: Complete 5 consecutive jobs on time to re-enter Good Standing.',
            'Emergency broadcast matching temporarily restricted.',
          ],
          isDark: isDark,
        ),

        const SizedBox(height: 12),

        // Tier 4: Critical Standing
        _buildTierCard(
          tierName: 'Critical Standing',
          scoreRange: 'Below 60%',
          color: const Color(0xFFEF4444),
          icon: Icons.error_outline_rounded,
          isCurrent: _score < 60,
          benefits: [
            'Auto-dispatch matching paused to protect customer experience.',
            'Mandatory quality refresher and phone support check-in required.',
            'Unfair penalties can be appealed through Help & Support.',
          ],
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildTierCard({
    required String tierName,
    required String scoreRange,
    required Color color,
    required IconData icon,
    required bool isCurrent,
    required List<String> benefits,
    required bool isDark,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent
              ? color
              : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          width: isCurrent ? 1.8 : 1,
        ),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.12),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 18, color: color),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tierName,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        scoreRange,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    'YOUR TIER',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: color,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          ...benefits.map(
            (benefit) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 13,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      benefit,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: isDark ? Colors.white70 : const Color(0xFF475569),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

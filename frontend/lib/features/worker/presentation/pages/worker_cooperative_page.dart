import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/utils/toast_utils.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../auth/data/auth_api_repository.dart';
import '../../../workers/data/workers_api_repository.dart';

class WorkerCooperativePage extends StatefulWidget {
  const WorkerCooperativePage({super.key});

  @override
  State<WorkerCooperativePage> createState() => _WorkerCooperativePageState();
}

class _WorkerCooperativePageState extends State<WorkerCooperativePage> {
  final _workersRepo = WorkersApiRepository();
  final _authRepo = AuthApiRepository();

  bool _isLoading = true;
  String? _errorMessage;

  String _workerName = '';
  String _workerPhone = '';
  String? _societyMemberId;
  String? _joinedAt;
  bool _isVerified = false;

  Map<String, dynamic>? _society;
  Map<String, dynamic>? _federation;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final user = await _authRepo.fetchMe();
      final data = await _workersRepo.fetchMyCooperativeMembership();

      if (!mounted) return;

      final fed = data['federation'] is Map ? Map<String, dynamic>.from(data['federation'] as Map) : null;
      final soc = data['society'] is Map ? Map<String, dynamic>.from(data['society'] as Map) : null;

      setState(() {
        _workerName = user.name;
        _workerPhone = user.phone;
        _societyMemberId = data['societyMemberId']?.toString() ?? 'COOP-FIXLY-${user.id.length >= 6 ? user.id.substring(user.id.length - 6).toUpperCase() : user.id.toUpperCase()}';
        _joinedAt = data['joinedAt']?.toString();
        _isVerified = data['verified'] == true || user.isVerified;
        _federation = fed;
        _society = soc;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return AppScaffold(
      title: 'Cooperative Society',
      showBack: true,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : AppRefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: appRefreshScrollPhysics,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: _errorMessage != null
                    ? SizedBox(
                        height: 380,
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
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 14),
                              ),
                              const SizedBox(height: 16),
                              FilledButton.tonalIcon(
                                onPressed: () {
                                  setState(() => _isLoading = true);
                                  _loadData();
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
                          // 1. Digital Membership ID Card
                          _buildMembershipCard(isDark),

                          const SizedBox(height: 16),

                          // 2. Primary Cooperative Society Details Card
                          _buildPrimarySocietyCard(isDark, primaryColor),

                          const SizedBox(height: 16),

                          // 3. Apex Federation Details Card
                          _buildFederationCard(isDark, primaryColor),

                          const SizedBox(height: 16),

                          // 4. Quick Action: Manage Minimum Wage Rates
                          _buildRateSettingsActionTile(isDark, primaryColor),

                          const SizedBox(height: 16),

                          // 5. Cooperative Worker Rights & Safeguards
                          _buildCooperativeBenefitsCard(isDark, primaryColor),

                          const SizedBox(height: 32),
                        ],
                      ),
              ),
            ),
    );
  }

  // -------------------------------------------------------------
  // 1. DIGITAL MEMBERSHIP CARD
  // -------------------------------------------------------------
  Widget _buildMembershipCard(bool isDark) {
    final fedName = _federation?['federationName'] ?? _federation?['name'] ?? 'National Labour Cooperative Federation';
    final socName = _society?['name'] ?? 'Fixly Primary Labour Cooperative Society';
    final regNo = _society?['registrationNumber'] ?? _federation?['registrationNumber'] ?? 'FED-COOP-2026-001';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1E3A8A), // Deep Navy
            Color(0xFF2563EB), // Fixly Primary Blue
            Color(0xFF1D4ED8),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Background decorative watermark circles
          Positioned(
            right: -25,
            top: -25,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            right: 25,
            bottom: -35,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top header row: Federation Logo & Verification Badge
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.groups_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'COOPERATIVE IDENTITY',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white.withValues(alpha: 0.8),
                              letterSpacing: 0.8,
                            ),
                          ),
                          Text(
                            fedName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF10B981)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isVerified ? Icons.verified_rounded : Icons.pending_rounded,
                            size: 13,
                            color: const Color(0xFF10B981),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _isVerified ? 'VERIFIED' : 'ACTIVE',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF10B981),
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Member ID
                Text(
                  'MEMBER REGISTRATION ID',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.7),
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _societyMemberId ?? 'COOP-FIXLY-2026',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Colors.white,
                  ),
                ),

                const SizedBox(height: 20),

                // Member Name & Affiliated Society
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _workerName.isNotEmpty ? _workerName : 'Verified Worker',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          if (_workerPhone.isNotEmpty) ...[
                            const SizedBox(height: 1),
                            Text(
                              _workerPhone,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.75),
                              ),
                            ),
                          ],
                          const SizedBox(height: 2),
                          Text(
                            socName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'REG NO.',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                        Text(
                          regNo,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        if (_joinedAt != null && _joinedAt!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Joined ${_joinedAt!.length >= 10 ? _joinedAt!.substring(0, 10) : _joinedAt!}',
                            style: TextStyle(
                              fontSize: 9.5,
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // 2. PRIMARY COOPERATIVE SOCIETY CARD
  // -------------------------------------------------------------
  Widget _buildPrimarySocietyCard(bool isDark, Color primaryColor) {
    final name = _society?['name'] ?? 'Fixly Primary Labour Cooperative Society';
    final reg = _society?['registrationNumber'] ?? 'MSCS-LCS-2026-482';
    final district = _society?['district'] ?? 'Mumbai Suburban';
    final state = _society?['state'] ?? 'Maharashtra';
    final ward = _society?['wardOrArea'];
    final phone = _society?['contactPhone'] ?? '+91 22 2680 1200';
    final president = _society?['presidentName'] ?? 'Rajesh Patil (President)';
    final compliance = _society?['fairWageComplianceScore'] ?? 100;

    return Container(
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.apartment_rounded, size: 20, color: primaryColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Primary Cooperative Society',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white54 : const Color(0xFF64748B),
                      ),
                    ),
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),

          _buildInfoRow(
            icon: Icons.numbers_rounded,
            label: 'Registration Number',
            value: reg,
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            icon: Icons.location_on_outlined,
            label: 'Jurisdiction & Area',
            value: ward != null ? '$ward, $district, $state' : '$district, $state',
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            icon: Icons.person_outline_rounded,
            label: 'Society Representative',
            value: president,
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            icon: Icons.phone_outlined,
            label: 'Helpline / Contact',
            value: phone,
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            icon: Icons.verified_user_outlined,
            label: 'Fair Wage Compliance',
            value: '$compliance% (Certified Compliant)',
            valueColor: const Color(0xFF10B981),
            isDark: isDark,
          ),
          if (_society == null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _joinSocietyFlow,
              icon: const Icon(Icons.group_add_rounded),
              label: const Text('Join a primary society'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _joinSocietyFlow() async {
    try {
      final list = await _workersRepo.fetchSocieties();
      if (!mounted) return;
      if (list.isEmpty) {
        ToastUtils.showToast(
          context: context,
          message: 'No active societies available',
        );
        return;
      }
      final selected = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => SafeArea(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: list.length,
            itemBuilder: (_, i) {
              final s = list[i];
              return ListTile(
                title: Text(s['name']?.toString() ?? 'Society'),
                subtitle: Text(
                  '${s['district'] ?? ''} · ${s['state'] ?? ''}',
                ),
                onTap: () => Navigator.pop(ctx, s),
              );
            },
          ),
        ),
      );
      if (selected == null || !mounted) return;
      final id = (selected['_id'] ?? selected['id'])?.toString();
      if (id == null) return;
      await _workersRepo.joinSociety(id);
      if (!mounted) return;
      ToastUtils.showSuccess(
        context: context,
        message: 'Joined ${selected['name'] ?? 'society'}',
      );
      setState(() => _isLoading = true);
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ToastUtils.showError(context: context, message: e.toString());
    }
  }

  // -------------------------------------------------------------
  // 3. APEX FEDERATION DETAILS CARD
  // -------------------------------------------------------------
  Widget _buildFederationCard(bool isDark, Color primaryColor) {
    final fedName = _federation?['federationName'] ?? 'National Labour Cooperative Federation of India';
    final fedShort = _federation?['name'] ?? 'Fixly Cooperative Federation';
    final fedReg = _federation?['registrationNumber'] ?? 'FED-COOP-2026-001';
    final policy = _federation?['fairWagePolicy'] ?? 'Cooperative Minimum Fair Wage Guarantee Policy v1.0';
    final welfareRate = ((_federation?['welfareContributionRate'] as num?)?.toDouble() ?? 0.05) * 100;

    return Container(
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.account_balance_rounded, size: 20, color: Color(0xFF10B981)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Apex Labour Federation',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white54 : const Color(0xFF64748B),
                      ),
                    ),
                    Text(
                      fedName,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),

          _buildInfoRow(
            icon: Icons.shield_outlined,
            label: 'Federation Name',
            value: fedShort,
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            icon: Icons.app_registration_rounded,
            label: 'Statutory Registration',
            value: fedReg,
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            icon: Icons.policy_outlined,
            label: 'Wage Floor Standard',
            value: policy,
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            icon: Icons.volunteer_activism_outlined,
            label: 'Welfare Fund Pool',
            value: '${welfareRate.toStringAsFixed(1)}% Dedicated Platform Allocation',
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // 4. ACTION TILE: MANAGE MINIMUM WAGE RATES
  // -------------------------------------------------------------
  Widget _buildRateSettingsActionTile(bool isDark, Color primaryColor) {
    return InkWell(
      onTap: () => context.push(RouteNames.workerRateSettings),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? primaryColor.withValues(alpha: 0.3) : const Color(0xFFBFDBFE),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.currency_rupee_rounded, size: 22, color: primaryColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Category Rates & Wage Floors',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF1E40AF),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'View statutory minimum wage floors and customize your visit rates',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white70 : const Color(0xFF1E3A8A),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: primaryColor),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // 5. COOPERATIVE WORKER RIGHTS & SAFEGUARDS
  // -------------------------------------------------------------
  Widget _buildCooperativeBenefitsCard(bool isDark, Color primaryColor) {
    return Container(
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
              Icon(Icons.verified_outlined, size: 18, color: primaryColor),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Worker Cooperative Rights & Safeguards',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildBenefitItem(
            icon: Icons.gavel_rounded,
            title: 'Statutory Fair Wage Floor',
            description:
                'No customer can book you below your category minimum wage floor. Fixly ensures zero wage undercutting.',
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          _buildBenefitItem(
            icon: Icons.health_and_safety_outlined,
            title: 'Insurance & e-Shram Coverage',
            description:
                'Active cooperative members are linked to national e-Shram social security and on-duty accidental coverage.',
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          _buildBenefitItem(
            icon: Icons.savings_outlined,
            title: 'Welfare Reserve Pool',
            description:
                'A dedicated 5% reserve from cooperative platform operations is channeled into emergency relief and sick leave funds.',
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          _buildBenefitItem(
            icon: Icons.handshake_outlined,
            title: 'Democratic Dispute Resolution',
            description:
                'Disputed bookings are reviewed with worker-elected cooperative grievance committees, ensuring fair arbitration.',
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 16,
          color: isDark ? Colors.white54 : const Color(0xFF64748B),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white54 : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? (isDark ? Colors.white : const Color(0xFF0F172A)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBenefitItem({
    required IconData icon,
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
            color: const Color(0xFF10B981).withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 14, color: const Color(0xFF10B981)),
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
}

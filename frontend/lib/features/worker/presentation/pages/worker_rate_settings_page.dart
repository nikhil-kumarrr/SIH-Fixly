import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/l10n/category_localizer.dart';
import '../../../../core/utils/toast_utils.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../shared/presentation/cubit/profile_cubit.dart';
import '../../../workers/data/workers_api_repository.dart';

class WorkerRateSettingsPage extends StatefulWidget {
  const WorkerRateSettingsPage({super.key});

  @override
  State<WorkerRateSettingsPage> createState() => _WorkerRateSettingsPageState();
}

class _CategoryRateItem {
  _CategoryRateItem({
    required this.category,
    required this.currentRate,
    required this.minimumFloor,
    required this.controller,
  });

  final String category;
  final double currentRate;
  final double minimumFloor;
  final TextEditingController controller;
}

class _WorkerRateSettingsPageState extends State<WorkerRateSettingsPage> {
  final _workersRepo = WorkersApiRepository();

  bool _isLoading = true;
  bool _isSaving = false;

  String _federationName = 'National Labour Cooperative Federation';
  String _federationRegNo = 'FED-COOP-2026-001';
  String _fairWagePolicy = 'Cooperative Minimum Fair Wage Guarantee Policy v1.0';

  final List<_CategoryRateItem> _items = [];

  @override
  void initState() {
    super.initState();
    _loadRates();
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadRates() async {
    try {
      final res = await _workersRepo.fetchWorkerRates();
      if (!mounted) return;

      final fed = res['federation'] is Map ? Map<String, dynamic>.from(res['federation'] as Map) : null;
      final rawCategories = res['categories'] is List ? (res['categories'] as List) : [];

      // Dispose existing controllers before resetting
      for (final item in _items) {
        item.controller.dispose();
      }
      _items.clear();

      if (rawCategories.isNotEmpty) {
        for (final raw in rawCategories) {
          if (raw is Map) {
            final cat = (raw['category'] ?? raw['name'] ?? 'General').toString();
            final rate = (raw['rate'] as num?)?.toDouble() ?? 300.0;
            final floor = (raw['minimumFloor'] as num?)?.toDouble() ?? 300.0;
            final initialRate = rate < floor ? floor : rate;

            final ctrl = TextEditingController(text: initialRate.toStringAsFixed(0));
            ctrl.addListener(() {
              if (mounted) setState(() {});
            });

            _items.add(
              _CategoryRateItem(
                category: cat,
                currentRate: initialRate,
                minimumFloor: floor,
                controller: ctrl,
              ),
            );
          }
        }
      } else {
        // Fallback to profile categories if empty
        final profile = context.read<ProfileCubit>().state;
        final cats = profile.categories.isNotEmpty
            ? profile.categories
            : (profile.category.isNotEmpty ? [profile.category] : ['Plumbing']);
        final defaultRate = profile.hourlyRate > 0 ? profile.hourlyRate : 350.0;

        for (final cat in cats) {
          final floor = _getFallbackFloor(cat);
          final initialRate = defaultRate < floor ? floor : defaultRate;
          final ctrl = TextEditingController(text: initialRate.toStringAsFixed(0));
          ctrl.addListener(() {
            if (mounted) setState(() {});
          });

          _items.add(
            _CategoryRateItem(
              category: cat,
              currentRate: initialRate,
              minimumFloor: floor,
              controller: ctrl,
            ),
          );
        }
      }

      setState(() {
        if (fed != null) {
          _federationName = fed['federationName']?.toString() ?? fed['name']?.toString() ?? _federationName;
          _federationRegNo = fed['registrationNumber']?.toString() ?? _federationRegNo;
          _fairWagePolicy = fed['fairWagePolicy']?.toString() ?? _fairWagePolicy;
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // If API fails, try local profile fallback
      _fallbackToLocalProfile(e.toString());
    }
  }

  double _getFallbackFloor(String category) {
    final cat = category.toLowerCase();
    if (cat.contains('plumb')) return 350.0;
    if (cat.contains('electr')) return 400.0;
    if (cat.contains('carpent')) return 400.0;
    if (cat.contains('clean')) return 250.0;
    if (cat.contains('paint')) return 350.0;
    if (cat.contains('appliance') || cat.contains('ac') || cat.contains('repair')) return 350.0;
    if (cat.contains('garden')) return 250.0;
    return 300.0;
  }

  void _fallbackToLocalProfile(String err) {
    final profile = context.read<ProfileCubit>().state;
    final cats = profile.categories.isNotEmpty
        ? profile.categories
        : (profile.category.isNotEmpty ? [profile.category] : ['Plumbing', 'Electrical']);
    final defaultRate = profile.hourlyRate > 0 ? profile.hourlyRate : 350.0;

    for (final item in _items) {
      item.controller.dispose();
    }
    _items.clear();

    for (final cat in cats) {
      final floor = _getFallbackFloor(cat);
      final initialRate = defaultRate < floor ? floor : defaultRate;
      final ctrl = TextEditingController(text: initialRate.toStringAsFixed(0));
      ctrl.addListener(() {
        if (mounted) setState(() {});
      });

      _items.add(
        _CategoryRateItem(
          category: cat,
          currentRate: initialRate,
          minimumFloor: floor,
          controller: ctrl,
        ),
      );
    }

    setState(() {
      _isLoading = false;
    });
  }

  IconData _getCategoryIcon(String category) {
    final cat = category.toLowerCase();
    if (cat.contains('plumb')) return Icons.plumbing_rounded;
    if (cat.contains('electr')) return Icons.bolt_rounded;
    if (cat.contains('carpent')) return Icons.handyman_rounded;
    if (cat.contains('clean')) return Icons.cleaning_services_rounded;
    if (cat.contains('paint')) return Icons.format_paint_rounded;
    if (cat.contains('appliance') || cat.contains('ac')) return Icons.ac_unit_rounded;
    if (cat.contains('garden')) return Icons.yard_rounded;
    return Icons.build_rounded;
  }

  void _adjustRate(_CategoryRateItem item, double delta) {
    final current = double.tryParse(item.controller.text) ?? item.minimumFloor;
    final updated = (current + delta).clamp(item.minimumFloor, 5000.0);
    item.controller.text = updated.toStringAsFixed(0);
  }

  void _resetToFloor(_CategoryRateItem item) {
    item.controller.text = item.minimumFloor.toStringAsFixed(0);
  }

  Future<void> _save() async {
    // 1. Validation: ensure no rate is below federation floor
    for (final item in _items) {
      final rate = double.tryParse(item.controller.text.trim()) ?? 0.0;
      if (rate < item.minimumFloor) {
        ToastUtils.showError(
          context: context,
          message: '${item.category} rate cannot be below federation floor of ₹${item.minimumFloor.toStringAsFixed(0)}',
        );
        return;
      }
    }

    setState(() => _isSaving = true);
    try {
      final payload = _items.map((item) {
        final rate = double.tryParse(item.controller.text.trim()) ?? item.minimumFloor;
        return {
          'category': item.category,
          'rate': rate,
        };
      }).toList();

      await _workersRepo.updateWorkerRates(payload);

      if (mounted) {
        ToastUtils.showSuccess(
          context: context,
          message: 'Category base rates saved successfully',
        );
        context.read<ProfileCubit>().load();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.showError(context: context, message: e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return AppScaffold(
      title: 'Rate Settings',
      showBack: true,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: AppRefreshIndicator(
                    onRefresh: _loadRates,
                    child: ListView(
                      physics: appRefreshScrollPhysics,
                      padding: const EdgeInsets.all(16),
                      children: [
                        // 1. Federation Affiliation & Statutory Wage Floor Card
                        _buildFederationBanner(isDark, primaryColor),

                        const SizedBox(height: 16),

                        // Section Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Your Category Rates',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: primaryColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${_items.length} ${_items.length == 1 ? "Category" : "Categories"} Active',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: primaryColor,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        // 2. List of Category Rate Cards
                        if (_items.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(24),
                            alignment: Alignment.center,
                            child: const Text('No categories assigned to your profile.'),
                          )
                        else
                          ..._items.map((item) => _buildCategoryRateCard(item, isDark, primaryColor)),

                        const SizedBox(height: 16),

                        // 3. Informational Notice
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.verified_user_outlined,
                                size: 18,
                                color: isDark ? Colors.white70 : const Color(0xFF64748B),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Customers cannot book services below your configured base price. Fixly automatically checks that every booking meets your rate and statutory federation wage floors.',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    height: 1.4,
                                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Bottom Save Action Container
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    border: Border(
                      top: BorderSide(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      ),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: PrimaryButton(
                      label: 'Save Category Rates',
                      loading: _isSaving,
                      onPressed: _save,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // -------------------------------------------------------------
  // 1. FEDERATION BANNER CARD
  // -------------------------------------------------------------
  Widget _buildFederationBanner(bool isDark, Color primaryColor) {
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
                child: Icon(Icons.account_balance_rounded, size: 20, color: primaryColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _federationName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'AFFILIATED',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Registration: $_federationRegNo',
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

          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),

          Row(
            children: [
              const Icon(Icons.gavel_rounded, size: 15, color: Color(0xFF10B981)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Statutory Fair Wage Guarantee Protected',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFF86EFAC) : const Color(0xFF166534),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Under cooperative bylaws, base rates for each category cannot be set below the federation minimum wage floor.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: isDark ? Colors.white60 : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // 2. CATEGORY RATE EDIT CARD
  // -------------------------------------------------------------
  Widget _buildCategoryRateCard(_CategoryRateItem item, bool isDark, Color primaryColor) {
    final inputVal = double.tryParse(item.controller.text.trim()) ?? 0.0;
    final isBelowFloor = inputVal < item.minimumFloor;
    final categoryIcon = _getCategoryIcon(item.category);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isBelowFloor
              ? const Color(0xFFEF4444)
              : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          width: isBelowFloor ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Icon + Name + Federation Floor Pill
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(categoryIcon, size: 18, color: primaryColor),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    localizeCategory(item.category, context.l10n.locale),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shield_outlined, size: 12, color: Color(0xFF10B981)),
                    const SizedBox(width: 4),
                    Text(
                      'Floor: ₹${item.minimumFloor.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Rate Input Field
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: item.controller,
                  keyboardType: const TextInputType.numberWithOptions(decimal: false),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isBelowFloor
                        ? const Color(0xFFEF4444)
                        : (isDark ? Colors.white : const Color(0xFF0F172A)),
                  ),
                  decoration: InputDecoration(
                    prefixIcon: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(Icons.currency_rupee_rounded, size: 20),
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                    suffixText: '/ visit base',
                    suffixStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white54 : const Color(0xFF64748B),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isBelowFloor
                            ? const Color(0xFFEF4444)
                            : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isBelowFloor
                            ? const Color(0xFFEF4444)
                            : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isBelowFloor ? const Color(0xFFEF4444) : primaryColor,
                        width: 1.6,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Quick Increment / Adjustment Chips
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  _buildQuickAdjustChip('+₹50', () => _adjustRate(item, 50), isDark, primaryColor),
                  const SizedBox(width: 6),
                  _buildQuickAdjustChip('+₹100', () => _adjustRate(item, 100), isDark, primaryColor),
                  const SizedBox(width: 6),
                  _buildQuickAdjustChip('Reset to Floor', () => _resetToFloor(item), isDark, primaryColor),
                ],
              ),
            ],
          ),

          // Inline Floor Warning Error Message
          if (isBelowFloor) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.error_outline_rounded, size: 14, color: Color(0xFFEF4444)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Cannot be below federation minimum floor of ₹${item.minimumFloor.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickAdjustChip(
    String label,
    VoidCallback onTap,
    bool isDark,
    Color primaryColor,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }
}

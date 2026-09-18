import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/utils/toast_utils.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../../shared/models/models.dart';
import '../../../bookings/data/bookings_api_repository.dart';

class WorkerPriceEstimationPage extends StatefulWidget {
  const WorkerPriceEstimationPage({super.key, required this.bookingId});

  final String bookingId;

  @override
  State<WorkerPriceEstimationPage> createState() =>
      _WorkerPriceEstimationPageState();
}

class _WorkerPriceEstimationPageState extends State<WorkerPriceEstimationPage> {
  final _partsController = TextEditingController();
  final _serviceChargeController = TextEditingController();
  final _notesController = TextEditingController();

  bool _loadingBooking = true;
  bool _submitting = false;
  Booking? _booking;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _partsController.addListener(_onChanged);
    _serviceChargeController.addListener(_onChanged);
    _loadBooking();
  }

  @override
  void dispose() {
    _partsController.dispose();
    _serviceChargeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadBooking() async {
    try {
      final booking = await BookingsApiRepository().getById(
        widget.bookingId,
        forceNetwork: true,
      );
      if (!mounted) return;
      setState(() {
        _booking = booking;
        _loadingBooking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loadingBooking = false;
      });
    }
  }

  double get _basePrice {
    final b = _booking;
    if (b == null) return 0;
    // Always the booked base — never editable / never from add-ons.
    final invoiceBase = b.invoice?.baseServiceFee ?? 0;
    if (invoiceBase > 0) return invoiceBase;
    final fee = b.baseServiceFee ?? 0;
    if (fee > 0) return fee;
    return b.estimatedPrice;
  }

  double get _parts => double.tryParse(_partsController.text.trim()) ?? 0;
  double get _serviceCharge =>
      double.tryParse(_serviceChargeController.text.trim()) ?? 0;
  double get _total => _basePrice + _parts + _serviceCharge;

  Future<void> _submit() async {
    if (_parts < 0 || _serviceCharge < 0) {
      ToastUtils.showError(
        context: context,
        message: 'Amounts cannot be negative',
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await BookingsApiRepository().submitPriceEstimation(
        widget.bookingId,
        parts: _partsController.text.trim().isEmpty ? 0 : _parts,
        serviceCharge:
            _serviceChargeController.text.trim().isEmpty ? 0 : _serviceCharge,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );
      if (!mounted) return;
      ToastUtils.showSuccess(
        context: context,
        message: 'Rough estimation sent to customer',
      );
      // Do NOT load() a local cubit here — page pop disposes it (emit-after-close).
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go(RouteNames.workerActiveJob);
      }
    } catch (e) {
      if (!mounted) return;
      ToastUtils.showError(context: context, message: e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_loadingBooking) {
      return const AppScaffold(
        title: 'Rough Estimation',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null || _booking == null) {
      return AppScaffold(
        title: 'Rough Estimation',
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_loadError ?? 'Booking not found'),
                const SizedBox(height: 16),
                PrimaryButton(label: 'Retry', onPressed: () {
                  setState(() {
                    _loadingBooking = true;
                    _loadError = null;
                  });
                  _loadBooking();
                }),
              ],
            ),
          ),
        ),
      );
    }

    return AppScaffold(
      title: 'Rough Estimation',
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFF0F9FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _booking!.serviceTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Base price is locked from booking. You only add parts and optional extra-work charge.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Locked base price — not editable
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0F172A)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Base service price',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Fixed — cannot be changed',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '₹${_basePrice.toStringAsFixed(0)}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Add-ons (optional)',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            _AmountField(
              label: 'Parts cost',
              hint: 'Spares / materials',
              controller: _partsController,
              icon: Icons.build_circle_outlined,
            ),
            const SizedBox(height: 14),
            _AmountField(
              label: 'Service charge (extra work)',
              hint: 'Extra work beyond base job',
              controller: _serviceChargeController,
              icon: Icons.handyman_outlined,
            ),
            const SizedBox(height: 14),
            AppTextField(
              label: 'Notes for customer (optional)',
              controller: _notesController,
              maxLines: 3,
              keyboardType: TextInputType.multiline,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                children: [
                  _BreakdownRow(
                    label: 'Base (locked)',
                    value: _basePrice,
                    muted: true,
                  ),
                  const SizedBox(height: 10),
                  _BreakdownRow(label: '+ Parts', value: _parts),
                  const SizedBox(height: 10),
                  _BreakdownRow(
                    label: '+ Service charge',
                    value: _serviceCharge,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Divider(height: 1),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'New estimated total',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '₹${_total.toStringAsFixed(0)}',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            PrimaryButton(
              label: 'Send to customer',
              loading: _submitting,
              onPressed: _submitting ? null : _submit,
            ),
            const SizedBox(height: 12),
            SecondaryButton(
              label: 'Cancel',
              onPressed: _submitting ? null : () => context.pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.icon,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: label,
      hint: hint,
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      prefixIcon: Icon(icon, size: 20),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.label,
    required this.value,
    this.muted = false,
  });

  final String label;
  final double value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: muted
                  ? theme.colorScheme.onSurface.withValues(alpha: 0.55)
                  : null,
            ),
          ),
        ),
        Text(
          value > 0 || muted
              ? '₹${value.toStringAsFixed(0)}'
              : '—',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

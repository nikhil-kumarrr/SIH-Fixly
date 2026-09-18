import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/router/route_names.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/navigation/screen_refresh.dart';
import '../../../../core/utils/toast_utils.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../../shared/models/models.dart';
import '../../../bookings/data/bookings_api_repository.dart';

class _BillingPart {
  _BillingPart({
    required this.title,
    required this.unitPrice,
    this.quantity = 1,
  });

  String title;
  double unitPrice;
  int quantity;

  double get lineTotal => unitPrice * quantity;

  Map<String, dynamic> toApiJson() => {
        'title': title,
        'price': lineTotal,
        'unitPrice': unitPrice,
        'quantity': quantity,
      };
}

class WorkerAddPartsPage extends StatefulWidget {
  const WorkerAddPartsPage({super.key, required this.bookingId});

  final String bookingId;

  @override
  State<WorkerAddPartsPage> createState() => _WorkerAddPartsPageState();
}

class _WorkerAddPartsPageState extends State<WorkerAddPartsPage> {
  final _titleCtrl = TextEditingController();
  final _priceCtrl = TextEditingController(text: '50');
  final List<_BillingPart> _parts = [];
  final _bookings = BookingsApiRepository();

  bool _submitting = false;
  bool _loadingJob = true;
  Booking? _booking;
  int _draftQty = 1;

  @override
  void initState() {
    super.initState();
    _loadJob();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadJob() async {
    try {
      final booking = await _bookings.getById(
        widget.bookingId,
        forceNetwork: true,
      );
      if (!mounted) return;
      setState(() {
        _booking = booking;
        _loadingJob = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingJob = false);
    }
  }

  double get _draftUnitPrice =>
      double.tryParse(_priceCtrl.text.trim()) ?? 0;

  double get _partsTotal =>
      _parts.fold<double>(0, (sum, p) => sum + p.lineTotal);

  double get _baseFee {
    final b = _booking;
    if (b == null) return 0;
    if (b.workerEstimation != null && b.workerEstimation!.lockedBaseFee > 0) {
      return b.workerEstimation!.lockedBaseFee;
    }
    return b.invoice?.baseServiceFee ?? b.baseServiceFee ?? b.estimatedPrice;
  }

  double get _estimationParts =>
      _booking?.workerEstimation?.partsEstimate ?? 0;

  double get _serviceCharge =>
      _booking?.workerEstimation?.serviceCharge ?? 0;

  double get _platformFee =>
      _booking?.invoice?.platformFee ?? _booking?.platformFee ?? 0;

  double get _billParts {
    // Final parts replace rough-estimate parts once worker adds any.
    if (_parts.isNotEmpty) return _partsTotal;
    return _estimationParts;
  }

  double get _grandTotal =>
      _baseFee + _serviceCharge + _billParts + _platformFee;

  void _nudgePrice(int delta) {
    final next = (_draftUnitPrice + delta).clamp(0, 999999).toDouble();
    _priceCtrl.text = next == next.roundToDouble()
        ? next.toInt().toString()
        : next.toStringAsFixed(0);
    setState(() {});
  }

  void _nudgeQty(int delta) {
    setState(() => _draftQty = (_draftQty + delta).clamp(1, 99));
  }

  void _addPart() {
    final title = _titleCtrl.text.trim();
    final price = _draftUnitPrice;
    if (title.isEmpty) {
      ToastUtils.showToast(context: context, message: 'Enter part name');
      return;
    }
    if (price <= 0) {
      ToastUtils.showToast(context: context, message: 'Enter a valid price');
      return;
    }
    setState(() {
      _parts.add(
        _BillingPart(title: title, unitPrice: price, quantity: _draftQty),
      );
      _titleCtrl.clear();
      _priceCtrl.text = '50';
      _draftQty = 1;
    });
  }

  Future<void> _requestPayment() async {
    if (_submitting || widget.bookingId.isEmpty) return;
    setState(() => _submitting = true);
    try {
      final payload = _parts.map((p) => p.toApiJson()).toList();
      // Direct API — no throwaway ActiveJobCubit (emit-after-close crash).
      if (payload.isNotEmpty) {
        await _bookings.addParts(
          bookingId: widget.bookingId,
          extraItems: payload,
          replace: true,
        );
      }
      await _bookings.complete(widget.bookingId);
      if (!mounted) return;
      ToastUtils.showSuccess(
        context: context,
        message: 'Payment requested from customer',
      );
      context.goRefreshing(RouteNames.workerActiveJob);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ToastUtils.showError(context: context, message: e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AppScaffold(
      title: 'Final Billing',
      body: _loadingJob
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: [
                      _JobBanner(
                        title: _booking?.serviceTitle ?? 'Service',
                        customer: _booking?.customerName,
                        isDark: isDark,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Add parts used',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _AddPartCard(
                        titleCtrl: _titleCtrl,
                        priceCtrl: _priceCtrl,
                        qty: _draftQty,
                        enabled: !_submitting,
                        onPriceMinus: () => _nudgePrice(-10),
                        onPricePlus: () => _nudgePrice(10),
                        onQtyMinus: () => _nudgeQty(-1),
                        onQtyPlus: () => _nudgeQty(1),
                        onAdd: _addPart,
                        onPriceChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 16),
                      if (_parts.isEmpty)
                        _EmptyPartsHint(isDark: isDark)
                      else ...[
                        Text(
                          'Parts on this bill (${_parts.length})',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...List.generate(_parts.length, (i) {
                          final part = _parts[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _PartTile(
                              part: part,
                              enabled: !_submitting,
                              onQtyChanged: (q) => setState(() {
                                part.quantity = q.clamp(1, 99);
                              }),
                              onPriceNudge: (d) => setState(() {
                                part.unitPrice =
                                    (part.unitPrice + d).clamp(0, 999999);
                              }),
                              onRemove: () => setState(() {
                                _parts.removeAt(i);
                              }),
                            ),
                          );
                        }),
                      ],
                      const SizedBox(height: 8),
                      _BillSummary(
                        base: _baseFee,
                        estimationParts:
                            _parts.isEmpty ? _estimationParts : 0,
                        serviceCharge: _serviceCharge,
                        finalParts: _partsTotal,
                        platform: _platformFee,
                        total: _grandTotal,
                        isDark: isDark,
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_submitting)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else ...[
                          if (_parts.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                'Parts total ₹${_partsTotal.toStringAsFixed(0)} · Bill ₹${_grandTotal.toStringAsFixed(0)}',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.65),
                                ),
                              ),
                            ),
                          SecondaryButton(
                            label: _parts.isEmpty
                                ? 'Skip parts — request payment'
                                : 'Request payment without swipe',
                            onPressed: _requestPayment,
                          ),
                          const SizedBox(height: 10),
                          SwipeActionButton(
                            label: 'Swipe to request payment',
                            enabled: !_submitting,
                            onCompleted: _requestPayment,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _JobBanner extends StatelessWidget {
  const _JobBanner({
    required this.title,
    required this.isDark,
    this.customer,
  });

  final String title;
  final String? customer;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E3A8A), const Color(0xFF1E293B)]
              : [const Color(0xFFEFF6FF), const Color(0xFFDBEAFE)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.9),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.receipt_long_rounded,
                color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Final bill',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (customer != null && customer!.isNotEmpty)
                  Text(
                    'Customer · $customer',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddPartCard extends StatelessWidget {
  const _AddPartCard({
    required this.titleCtrl,
    required this.priceCtrl,
    required this.qty,
    required this.enabled,
    required this.onPriceMinus,
    required this.onPricePlus,
    required this.onQtyMinus,
    required this.onQtyPlus,
    required this.onAdd,
    required this.onPriceChanged,
  });

  final TextEditingController titleCtrl;
  final TextEditingController priceCtrl;
  final int qty;
  final bool enabled;
  final VoidCallback onPriceMinus;
  final VoidCallback onPricePlus;
  final VoidCallback onQtyMinus;
  final VoidCallback onQtyPlus;
  final VoidCallback onAdd;
  final ValueChanged<String> onPriceChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.45),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: titleCtrl,
            label: 'Part / material name',
            hint: 'e.g. PVC pipe, Switch board',
            enabled: enabled,
            prefixIcon: const Icon(Icons.build_circle_outlined, size: 20),
          ),
          const SizedBox(height: 14),
          Text(
            'Unit price (₹)',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _StepperRow(
            enabled: enabled,
            onMinus: onPriceMinus,
            onPlus: onPricePlus,
            minusLabel: '−₹10',
            plusLabel: '+₹10',
            child: SizedBox(
              width: 110,
              child: TextField(
                controller: priceCtrl,
                enabled: enabled,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                onChanged: onPriceChanged,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFF8FAFC),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Quantity',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _StepperRow(
            enabled: enabled,
            onMinus: onQtyMinus,
            onPlus: onQtyPlus,
            child: Container(
              width: 72,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0F172A)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$qty',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: enabled ? onAdd : null,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Add part to bill',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.enabled,
    required this.onMinus,
    required this.onPlus,
    required this.child,
    this.minusLabel,
    this.plusLabel,
  });

  final bool enabled;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final Widget child;
  final String? minusLabel;
  final String? plusLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StepButton(
          enabled: enabled,
          onTap: onMinus,
          icon: Icons.remove_rounded,
          label: minusLabel,
        ),
        const SizedBox(width: 12),
        child,
        const SizedBox(width: 12),
        _StepButton(
          enabled: enabled,
          onTap: onPlus,
          icon: Icons.add_rounded,
          label: plusLabel,
          filled: true,
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.enabled,
    required this.onTap,
    required this.icon,
    this.label,
    this.filled = false,
  });

  final bool enabled;
  final VoidCallback onTap;
  final IconData icon;
  final String? label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final bg = filled
        ? AppColors.primary
        : AppColors.primary.withValues(alpha: 0.1);
    final fg = filled ? Colors.white : AppColors.primary;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: label != null ? 12 : 0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: fg, size: 22),
                if (label != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    label!,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PartTile extends StatelessWidget {
  const _PartTile({
    required this.part,
    required this.enabled,
    required this.onQtyChanged,
    required this.onPriceNudge,
    required this.onRemove,
  });

  final _BillingPart part;
  final bool enabled;
  final ValueChanged<int> onQtyChanged;
  final ValueChanged<double> onPriceNudge;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.hardware_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  part.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: enabled ? onRemove : null,
                icon: const Icon(Icons.delete_outline_rounded,
                    color: AppColors.error),
                tooltip: 'Remove',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _MiniStepper(
                label: 'Qty',
                value: '${part.quantity}',
                enabled: enabled,
                onMinus: () => onQtyChanged(part.quantity - 1),
                onPlus: () => onQtyChanged(part.quantity + 1),
              ),
              const SizedBox(width: 10),
              _MiniStepper(
                label: '₹/unit',
                value: part.unitPrice.toStringAsFixed(0),
                enabled: enabled,
                onMinus: () => onPriceNudge(-10),
                onPlus: () => onPriceNudge(10),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '₹${part.lineTotal.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStepper extends StatelessWidget {
  const _MiniStepper({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final String value;
  final bool enabled;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TinyIconBtn(
                icon: Icons.remove,
                onTap: enabled ? onMinus : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              _TinyIconBtn(
                icon: Icons.add,
                onTap: enabled ? onPlus : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TinyIconBtn extends StatelessWidget {
  const _TinyIconBtn({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(icon, size: 18, color: AppColors.primary),
      ),
    );
  }
}

class _EmptyPartsHint extends StatelessWidget {
  const _EmptyPartsHint({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey.withValues(alpha: 0.2),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 36,
            color: Colors.grey.shade500,
          ),
          const SizedBox(height: 8),
          Text(
            'No extra parts yet',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add materials above, or skip and request payment.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BillSummary extends StatelessWidget {
  const _BillSummary({
    required this.base,
    required this.estimationParts,
    required this.serviceCharge,
    required this.finalParts,
    required this.platform,
    required this.total,
    required this.isDark,
  });

  final double base;
  final double estimationParts;
  final double serviceCharge;
  final double finalParts;
  final double platform;
  final double total;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Bill summary',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          _sumRow('Base service (locked)', base),
          if (estimationParts > 0) ...[
            const SizedBox(height: 8),
            _sumRow('Parts (rough estimate)', estimationParts),
          ],
          if (serviceCharge > 0) ...[
            const SizedBox(height: 8),
            _sumRow('Service charge (extra work)', serviceCharge),
          ],
          if (finalParts > 0) ...[
            const SizedBox(height: 8),
            _sumRow('Parts on this bill', finalParts),
          ],
          if (platform > 0) ...[
            const SizedBox(height: 8),
            _sumRow('Platform fee', platform),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Customer pays',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '₹${total.toStringAsFixed(0)}',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sumRow(String label, double amount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        Text(
          amount > 0 ? '₹${amount.toStringAsFixed(0)}' : '—',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

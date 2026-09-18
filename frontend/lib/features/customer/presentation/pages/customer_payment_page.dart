import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/route_names.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/navigation/screen_refresh.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/toast_utils.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../../shared/models/models.dart';
import '../../../bookings/data/bookings_api_repository.dart';
import '../../../home/data/home_api_repository.dart';
import '../cubit/booking_flow_cubit.dart';

class CustomerPaymentPage extends StatefulWidget {
  const CustomerPaymentPage({super.key, this.bookingId});

  final String? bookingId;

  @override
  State<CustomerPaymentPage> createState() => _CustomerPaymentPageState();
}

class _CustomerPaymentPageState extends State<CustomerPaymentPage> {
  final _couponController = TextEditingController();
  final _couponFocus = FocusNode();
  bool _applyingCoupon = false;
  String? _couponMessage;
  bool _couponMessageIsError = false;
  List<CouponBanner> _availableCoupons = const [];
  bool _loadingCoupons = true;

  static const _ctaBarHeight = 96.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cubit = context.read<BookingFlowCubit>();
      cubit.refreshBooking(widget.bookingId);
      final id = widget.bookingId ?? cubit.state.booking?.id;
      if (id != null && id.isNotEmpty) {
        cubit.listenToSocketUpdates(id);
      }
      _loadAvailableCoupons();
    });
  }

  Future<void> _loadAvailableCoupons() async {
    try {
      final banners = await HomeApiRepository().fetchBanners();
      if (!mounted) return;
      setState(() {
        _availableCoupons = banners
            .where((b) => b.isActive && b.code.trim().isNotEmpty)
            .toList();
        _loadingCoupons = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _availableCoupons = const [];
        _loadingCoupons = false;
      });
    }
  }

  @override
  void dispose() {
    _couponController.dispose();
    _couponFocus.dispose();
    super.dispose();
  }

  Future<void> _applyCoupon(Booking booking, {String? codeOverride}) async {
    final code = (codeOverride ?? _couponController.text).trim();
    if (code.isEmpty) {
      ToastUtils.showToast(context: context, message: 'Enter a coupon code');
      return;
    }
    setState(() {
      _applyingCoupon = true;
      _couponMessage = null;
      _couponMessageIsError = false;
      _couponController.text = code.toUpperCase();
    });
    try {
      final updated = await BookingsApiRepository().applyCoupon(
        bookingId: booking.id,
        couponCode: code,
        serviceTitle: booking.serviceTitle,
      );
      if (!mounted) return;
      context.read<BookingFlowCubit>().loadFromBooking(updated);
      final disc = updated.invoice?.couponDiscount ?? 0;
      setState(() {
        _couponMessage = disc > 0
            ? 'Saved ₹${disc.toInt()}. Applied after payment succeeds.'
            : 'Coupon applied';
        _couponMessageIsError = false;
      });
      ToastUtils.showToast(context: context, message: _couponMessage!);
      _couponFocus.unfocus();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _couponMessage = e.message;
        _couponMessageIsError = true;
      });
      ToastUtils.showToast(context: context, message: e.message);
    } catch (e) {
      if (!mounted) return;
      final msg = ApiException.fromError(e);
      setState(() {
        _couponMessage = msg;
        _couponMessageIsError = true;
      });
      ToastUtils.showToast(context: context, message: msg);
    } finally {
      if (mounted) setState(() => _applyingCoupon = false);
    }
  }

  Future<void> _removeCoupon(Booking booking) async {
    setState(() {
      _applyingCoupon = true;
      _couponMessage = null;
      _couponMessageIsError = false;
    });
    try {
      final updated = await BookingsApiRepository().removeCoupon(
        bookingId: booking.id,
        serviceTitle: booking.serviceTitle,
      );
      if (!mounted) return;
      context.read<BookingFlowCubit>().loadFromBooking(updated);
      _couponController.clear();
      setState(() {
        _couponMessage = 'Coupon removed';
        _couponMessageIsError = false;
      });
      ToastUtils.showToast(context: context, message: 'Coupon removed');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _couponMessage = e.message;
        _couponMessageIsError = true;
      });
      ToastUtils.showToast(context: context, message: e.message);
    } catch (e) {
      if (!mounted) return;
      final msg = ApiException.fromError(e);
      setState(() {
        _couponMessage = msg;
        _couponMessageIsError = true;
      });
      ToastUtils.showToast(context: context, message: msg);
    } finally {
      if (mounted) setState(() => _applyingCoupon = false);
    }
  }

  Future<void> _handlePay(double payableAmount) async {
    final cubit = context.read<BookingFlowCubit>();
    final booking = cubit.state.booking;
    final raw = (booking?.rawStatus ?? '').toUpperCase();
    if (booking?.status == BookingStatus.inProgress || raw == 'IN_PROGRESS') {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Payment unavailable'),
          content: const Text(
            'The service is currently in progress. You cannot make a payment while the worker is actively working. Please wait until the worker completes the service.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final success = await cubit.payWithRazorpay(
      bookingId: widget.bookingId,
      amountOverride: payableAmount,
    );
    if (!mounted) return;
    if (success) {
      final id = widget.bookingId ?? cubit.state.booking?.id;
      if (id != null && id.isNotEmpty) {
        context.goRefreshing(RouteNames.customerRatingPath(id));
      } else {
        context.goRefreshing(RouteNames.customerRating);
      }
      return;
    }
    final error = cubit.state.errorMessage;
    if (error != null && error.isNotEmpty) {
      final lower = error.toLowerCase();
      if (lower.contains('in progress') || lower.contains('actively working')) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Payment unavailable'),
            content: Text(error),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        ToastUtils.showError(context: context, message: error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return BlocListener<BookingFlowCubit, BookingFlowState>(
      listenWhen: (previous, current) =>
          previous.step != current.step ||
          previous.booking?.paymentStatus != current.booking?.paymentStatus,
      listener: (context, state) {
        if (state.step == BookingStatus.rating ||
            state.step == BookingStatus.paid ||
            state.booking?.paymentStatus == 'PAID') {
          final id = widget.bookingId ?? state.booking?.id;
          if (id != null && id.isNotEmpty) {
            context.goRefreshing(RouteNames.customerRatingPath(id));
          } else {
            context.goRefreshing(RouteNames.customerRating);
          }
        }
      },
      child: AppScaffold(
        title: 'Payment',
        showBack: true,
        padding: EdgeInsets.zero,
        onBack: () {
          if (context.canPop()) {
            context.pop();
          } else {
            final bId = widget.bookingId ??
                context.read<BookingFlowCubit>().state.booking?.id;
            if (bId != null && bId.isNotEmpty) {
              context.goRefreshing(RouteNames.bookingDetailPath(bId));
            } else {
              context.goRefreshing(RouteNames.customerHome);
            }
          }
        },
        body: BlocBuilder<BookingFlowCubit, BookingFlowState>(
          builder: (context, state) {
            final booking = state.booking;
            final extraPartsTotal = booking?.extraPartsTotal;
            final double extraParts =
                (extraPartsTotal != null && extraPartsTotal > 0)
                    ? extraPartsTotal
                    : (booking?.addOns.isNotEmpty ?? false
                        ? booking!.addOns.fold<double>(
                            0.0,
                            (s, a) => s + (a.price * a.quantity),
                          )
                        : 0.0);
            final double platform = booking?.platformFee ?? 0.0;
            final double urgent = booking?.urgentFee ?? 0.0;
            final double couponDisc = booking?.invoice?.couponDiscount ?? 0.0;
            final String? couponCode = booking?.invoice?.couponCode;
            final unpaid =
                (booking?.paymentStatus ?? '').toUpperCase() != 'PAID';

            final baseFee = booking?.baseServiceFee;
            final double baseServiceFee = (baseFee != null && baseFee > 0)
                ? baseFee
                : (booking?.estimatedPrice ?? 0.0);

            final double originalAmount =
                baseServiceFee + extraParts + platform + urgent;
            final bookingTotal = booking?.totalAmount;
            final invoiceTotal = booking?.invoice?.totalAmount;
            final double amount = (bookingTotal != null && bookingTotal > 0)
                ? bookingTotal
                : ((invoiceTotal != null && invoiceTotal > 0)
                    ? invoiceTotal
                    : (couponDisc > 0
                        ? (originalAmount - couponDisc)
                            .clamp(0.0, double.infinity)
                        : (originalAmount > 0
                            ? originalAmount
                            : state.displayPrice)));

            Widget content = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AmountHero(
                  amount: amount,
                  originalAmount: originalAmount,
                  couponDisc: couponDisc,
                  serviceTitle: booking?.serviceTitle,
                ),
                const SizedBox(height: 16),
                _InvoiceSection(
                  baseServiceFee: baseServiceFee,
                  platform: platform,
                  urgent: urgent,
                  extraParts: extraParts,
                  addOns: booking?.addOns ?? const [],
                  couponDisc: couponDisc,
                  couponCode: couponCode,
                  originalAmount: originalAmount,
                  amount: amount,
                ),
                if (booking != null && unpaid) ...[
                  const SizedBox(height: 16),
                  _CouponSection(
                    booking: booking,
                    couponDisc: couponDisc,
                    couponCode: couponCode,
                    applying: _applyingCoupon,
                    message: _couponMessage,
                    messageIsError: _couponMessageIsError,
                    controller: _couponController,
                    focusNode: _couponFocus,
                    loadingCoupons: _loadingCoupons,
                    availableCoupons: _availableCoupons,
                    onApply: () => _applyCoupon(booking),
                    onRemove: () => _removeCoupon(booking),
                    onSelectCoupon: (code) =>
                        _applyCoupon(booking, codeOverride: code),
                    onDeselectCoupon: () => _removeCoupon(booking),
                  ),
                ],
                const SizedBox(height: 20),
                const _TrustFooter(),
              ],
            );

            if (!reduceMotion) {
              content = content
                  .animate()
                  .fadeIn(duration: 220.ms)
                  .slideY(begin: 0.02, end: 0, duration: 220.ms);
            }

            return Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, _ctaBarHeight + 16),
                  child: content,
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _PayBar(
                    amount: amount,
                    loading: state.isLoading,
                    onPay: () => _handlePay(amount),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─── Amount hero ─────────────────────────────────────────────────────────────

class _AmountHero extends StatelessWidget {
  const _AmountHero({
    required this.amount,
    required this.originalAmount,
    required this.couponDisc,
    this.serviceTitle,
  });

  final double amount;
  final double originalAmount;
  final double couponDisc;
  final String? serviceTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSavings = couponDisc > 0 && originalAmount > amount;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: AppColors.primary50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary100),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 14,
                  color: Color(0xFF047857),
                ),
                SizedBox(width: 6),
                Text(
                  'Work completed · Pay to finish',
                  style: TextStyle(
                    color: Color(0xFF047857),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (serviceTitle != null && serviceTitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              serviceTitle!,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Amount to pay',
            style: theme.textTheme.labelLarge?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
          if (hasSavings)
            Text(
              '₹${originalAmount.toInt()}',
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.textMuted,
                decoration: TextDecoration.lineThrough,
                decorationColor: AppColors.textMuted,
              ),
            ),
          Text(
            '₹${amount.toInt()}',
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.primaryDark,
              height: 1.1,
            ),
          ),
          if (hasSavings) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: Text(
                'You save ₹${couponDisc.toInt()} with coupon',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF047857),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Invoice ─────────────────────────────────────────────────────────────────

class _InvoiceSection extends StatelessWidget {
  const _InvoiceSection({
    required this.baseServiceFee,
    required this.platform,
    required this.urgent,
    required this.extraParts,
    required this.addOns,
    required this.couponDisc,
    required this.couponCode,
    required this.originalAmount,
    required this.amount,
  });

  final double baseServiceFee;
  final double platform;
  final double urgent;
  final double extraParts;
  final List<BookingAddOn> addOns;
  final double couponDisc;
  final String? couponCode;
  final double originalAmount;
  final double amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.receipt_long_outlined,
                  size: 20,
                  color: AppColors.primaryDark,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Invoice breakdown',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (baseServiceFee > 0)
            _InvoiceRow('Base service fee', baseServiceFee),
          if (platform > 0) _InvoiceRow('Platform fee', platform),
          if (urgent > 0) _InvoiceRow('Urgent / SOS fee', urgent),
          if (extraParts > 0 || addOns.isNotEmpty) ...[
            _InvoiceRow('Extra parts & materials', extraParts),
            ...addOns.map(
              (part) => Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${part.title} × ${part.quantity}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Text(
                      '₹${(part.price * part.quantity).toInt()}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (couponDisc > 0) ...[
            const SizedBox(height: 4),
            Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 4),
            if (originalAmount > 0) _InvoiceRow('Subtotal', originalAmount),
            _InvoiceRow(
              'Coupon${(couponCode ?? '').isNotEmpty ? ' (${couponCode!.toUpperCase()})' : ''}',
              -couponDisc,
            ),
          ],
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: _InvoiceRow('Amount to pay', amount, isTotal: true),
          ),
        ],
      ),
    );
  }
}

// ─── Coupon ──────────────────────────────────────────────────────────────────

class _CouponSection extends StatelessWidget {
  const _CouponSection({
    required this.booking,
    required this.couponDisc,
    required this.couponCode,
    required this.applying,
    required this.message,
    required this.messageIsError,
    required this.controller,
    required this.focusNode,
    required this.loadingCoupons,
    required this.availableCoupons,
    required this.onApply,
    required this.onRemove,
    required this.onSelectCoupon,
    required this.onDeselectCoupon,
  });

  final Booking booking;
  final double couponDisc;
  final String? couponCode;
  final bool applying;
  final String? message;
  final bool messageIsError;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool loadingCoupons;
  final List<CouponBanner> availableCoupons;
  final VoidCallback onApply;
  final VoidCallback onRemove;
  final ValueChanged<String> onSelectCoupon;
  final VoidCallback onDeselectCoupon;

  bool get _hasApplied =>
      couponDisc > 0 && (couponCode ?? '').trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.local_offer_outlined,
                  size: 20,
                  color: Color(0xFF047857),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Coupons & offers',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_hasApplied) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 20,
                    color: Color(0xFF047857),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          couponCode!.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF047857),
                          ),
                        ),
                        Text(
                          '−₹${couponDisc.toInt()} off this bill',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF065F46),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: applying ? null : onRemove,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.error,
                      minimumSize: const Size(48, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text('Remove'),
                  ),
                ],
              ),
            ),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => onApply(),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                      LengthLimitingTextInputFormatter(24),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Coupon code',
                      hintText: 'e.g. FIXLY50',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: applying ? null : onApply,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(88, 48),
                      backgroundColor: AppColors.primary,
                    ),
                    child: applying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: messageIsError
                    ? AppColors.error
                    : const Color(0xFF047857),
              ),
            ),
          ],
          if (!_hasApplied) ...[
            const SizedBox(height: 16),
            Text(
              'Your coupons',
              style: theme.textTheme.labelLarge?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            if (loadingCoupons)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (availableCoupons.isEmpty)
              Text(
                'No coupons on your account right now.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textMuted,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: availableCoupons.map((c) {
                  final applied = (booking.invoice?.couponCode ?? '')
                          .toUpperCase() ==
                      c.code.toUpperCase();
                  return FilterChip(
                    selected: applied,
                    showCheckmark: false,
                    avatar: Icon(
                      applied
                          ? Icons.check_rounded
                          : Icons.local_offer_outlined,
                      size: 16,
                      color: applied ? Colors.white : AppColors.primaryDark,
                    ),
                    label: Text('${c.code} · ${c.discount}'),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: applied ? Colors.white : AppColors.textPrimary,
                    ),
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.primary50,
                    side: BorderSide(
                      color: applied ? AppColors.primary : AppColors.primary100,
                    ),
                    onSelected: applying
                        ? null
                        : (selected) {
                            if (applied && !selected) {
                              onDeselectCoupon();
                            } else if (!applied && selected) {
                              onSelectCoupon(c.code);
                            }
                          },
                  );
                }).toList(),
              ),
          ],
        ],
      ),
    );
  }
}

// ─── Trust + pay bar ─────────────────────────────────────────────────────────

class _TrustFooter extends StatelessWidget {
  const _TrustFooter();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_outline_rounded, color: AppColors.textMuted, size: 16),
        SizedBox(width: 6),
        Flexible(
          child: Text(
            'Secured by Razorpay · Fixly protects your payment',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _PayBar extends StatelessWidget {
  const _PayBar({
    required this.amount,
    required this.loading,
    required this.onPay,
  });

  final double amount;
  final bool loading;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Material(
      elevation: 8,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomInset.clamp(0, 12)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PrimaryButton(
              label: 'Pay ₹${amount.toInt()}',
              loading: loading,
              onPressed: loading ? null : onPay,
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow(this.label, this.amount, {this.isTotal = false});

  final String label;
  final double amount;
  final bool isTotal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: isTotal ? 0 : 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (isTotal
                      ? theme.textTheme.titleSmall
                      : theme.textTheme.bodyMedium)
                  ?.copyWith(
                fontWeight: isTotal ? FontWeight.w700 : FontWeight.w400,
                color: isTotal
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            amount < 0 ? '−₹${(-amount).toInt()}' : '₹${amount.toInt()}',
            style: (isTotal
                    ? theme.textTheme.titleSmall
                    : theme.textTheme.bodyMedium)
                ?.copyWith(
              fontWeight: FontWeight.w700,
              color: amount < 0
                  ? const Color(0xFF047857)
                  : (isTotal ? AppColors.primaryDark : AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

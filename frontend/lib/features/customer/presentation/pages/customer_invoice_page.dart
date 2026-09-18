import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../app/router/route_names.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/navigation/screen_refresh.dart';
import '../../../../core/utils/toast_utils.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../../shared/models/models.dart';
import '../../../bookings/data/bookings_api_repository.dart';
import '../../../payments/services/razorpay_checkout_service.dart';
import '../../../shared/presentation/cubit/support_cubit.dart';

class CustomerInvoicePage extends StatefulWidget {
  const CustomerInvoicePage({required this.bookingId, super.key});

  final String bookingId;

  @override
  State<CustomerInvoicePage> createState() => _CustomerInvoicePageState();
}

class _CustomerInvoicePageState extends State<CustomerInvoicePage>
    with RefreshWhenNavigatedTo {
  late Future<BookingInvoice> _invoice;

  @override
  List<String> get refreshRoutePaths => [RouteNames.customerInvoice];

  @override
  void onScreenRefresh() => _reload();

  @override
  void initState() {
    super.initState();
    _invoice = BookingsApiRepository().invoice(widget.bookingId);
  }

  void _reload() {
    setState(() {
      _invoice = BookingsApiRepository().invoice(widget.bookingId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Invoice',
      showBack: true,
      fallbackPath: RouteNames.customerOrders,
      onBack: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(RouteNames.customerOrders);
        }
      },
      body: FutureBuilder<BookingInvoice>(
        future: _invoice,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Text(snapshot.error?.toString() ?? 'Invoice unavailable'),
            );
          }
          return _InvoiceContent(
            invoice: snapshot.data!,
            onPaymentSuccess: _reload,
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main invoice content
// ─────────────────────────────────────────────────────────────────────────────

class _InvoiceContent extends StatefulWidget {
  const _InvoiceContent({
    required this.invoice,
    required this.onPaymentSuccess,
  });

  final BookingInvoice invoice;
  final VoidCallback onPaymentSuccess;

  @override
  State<_InvoiceContent> createState() => _InvoiceContentState();
}

class _InvoiceContentState extends State<_InvoiceContent> {
  final RazorpayCheckoutService _razorpay = RazorpayCheckoutService();
  bool _isPaying = false;
  bool _isDownloading = false;
  bool _isReporting = false;

  @override
  void dispose() {
    _razorpay.dispose();
    super.dispose();
  }

  void _closeInvoice() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    // Arrived via go() after rating — no stack to pop.
    context.go(RouteNames.customerOrders);
  }

  Future<void> _payWithRazorpay() async {
    final invoice = widget.invoice;
    if (invoice.totalAmount <= 0) {
      ToastUtils.showToast(context: context, message: 'Invalid payment amount');
      return;
    }

    setState(() => _isPaying = true);
    try {
      final verified = await _razorpay.processPayment(
        bookingId: invoice.bookingId,
        amountRupees: invoice.totalAmount,
        description: '${invoice.serviceName} invoice payment',
        customerName: invoice.customerName,
        phone: invoice.customerPhone,
      );

      if (!mounted) return;
      setState(() => _isPaying = false);

      if (verified) {
        ToastUtils.showToast(context: context, message: 'Payment successful!');
        widget.onPaymentSuccess();
      } else {
        ToastUtils.showToast(
          context: context,
          message: 'Payment verification failed',
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isPaying = false);
      ToastUtils.showToast(context: context, message: e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPaying = false);
      ToastUtils.showToast(
        context: context,
        message: ApiException.fromError(e),
      );
    }
  }

  // ── PDF generation & download ──
  Future<Uint8List> _buildPdf() async {
    final invoice = widget.invoice;
    final fmt = NumberFormat('#,##0', 'en_IN');
    final dateFmt = DateFormat('dd MMM yyyy, h:mm a');

    final logoBytes = await rootBundle.load('assets/app_name.png');
    final logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // ── Header ──
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Image(logoImage, height: 52),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'SERVICE INVOICE',
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey800,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: pw.BoxDecoration(
                          color: _pdfStatusColor(invoice.paymentStatus),
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.Text(
                          (invoice.paymentStatus ?? 'PENDING').replaceAll(
                            '_',
                            ' ',
                          ),
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              pw.SizedBox(height: 20),
              pw.Divider(color: PdfColors.grey300),
              pw.SizedBox(height: 16),

              // ── Booking Meta ──
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Bill To:',
                          style: pw.TextStyle(
                            fontSize: 10,
                            color: PdfColors.grey600,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          invoice.customerName ?? 'Customer',
                          style: pw.TextStyle(
                            fontSize: 13,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        if (invoice.customerPhone != null)
                          pw.Text(
                            invoice.customerPhone!,
                            style: const pw.TextStyle(fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Service By:',
                          style: pw.TextStyle(
                            fontSize: 10,
                            color: PdfColors.grey600,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          invoice.workerName ?? 'Fixly Professional',
                          style: pw.TextStyle(
                            fontSize: 13,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        if (invoice.workerPhone != null)
                          pw.Text(
                            invoice.workerPhone!,
                            style: const pw.TextStyle(fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        _pdfMetaRow(
                          'Booking ID:',
                          invoice.bookingId.length > 14
                              ? '...${invoice.bookingId.substring(invoice.bookingId.length - 14)}'
                              : invoice.bookingId,
                        ),
                        pw.SizedBox(height: 4),
                        if (invoice.jobStartedAt != null)
                          _pdfMetaRow(
                            'Started:',
                            dateFmt.format(invoice.jobStartedAt!.toLocal()),
                          ),
                        if (invoice.jobCompletedAt != null) ...[
                          pw.SizedBox(height: 4),
                          _pdfMetaRow(
                            'Completed:',
                            dateFmt.format(
                              invoice.jobCompletedAt!.toLocal(),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 24),

              // ── Line Items Table ──
              pw.Container(
                decoration: pw.BoxDecoration(
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                child: pw.Table(
                  columnWidths: const {
                    0: pw.FlexColumnWidth(4),
                    1: pw.FixedColumnWidth(60),
                    2: pw.FixedColumnWidth(80),
                    3: pw.FixedColumnWidth(90),
                  },
                  children: [
                    // Header row
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(
                        color: PdfColor.fromInt(0xFF2563EB),
                        borderRadius: pw.BorderRadius.only(
                          topLeft: pw.Radius.circular(6),
                          topRight: pw.Radius.circular(6),
                        ),
                      ),
                      children: [
                        _pdfTableHeader('Description'),
                        _pdfTableHeader('Qty', align: pw.TextAlign.center),
                        _pdfTableHeader('Rate', align: pw.TextAlign.right),
                        _pdfTableHeader('Amount', align: pw.TextAlign.right),
                      ],
                    ),
                    // Base service — no qty shown for service name
                    pw.TableRow(
                      children: [
                        _pdfTableCell(invoice.serviceName),
                        _pdfTableCell(''),
                        _pdfTableCell(
                          'Rs. ${fmt.format(invoice.baseServiceFee.toInt())}',
                          align: pw.TextAlign.right,
                        ),
                        _pdfTableCell(
                          'Rs. ${fmt.format(invoice.baseServiceFee.toInt())}',
                          align: pw.TextAlign.right,
                        ),
                      ],
                    ),
                    // Add-ons
                    for (final part in invoice.addOns)
                      pw.TableRow(
                        children: [
                          _pdfTableCell(part.title),
                          _pdfTableCell(
                            part.quantity.toString(),
                            align: pw.TextAlign.center,
                          ),
                          _pdfTableCell(
                            'Rs. ${fmt.format(part.price.toInt())}',
                            align: pw.TextAlign.right,
                          ),
                          _pdfTableCell(
                            'Rs. ${fmt.format((part.price * part.quantity).toInt())}',
                            align: pw.TextAlign.right,
                          ),
                        ],
                      ),
                  ],
                ),
              ),

              pw.SizedBox(height: 12),

              // ── Totals ──
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Container(
                  width: 220,
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  padding: const pw.EdgeInsets.all(12),
                  child: pw.Column(
                    children: [
                      _pdfTotalRow(
                        'Base Service Fee',
                        'Rs. ${fmt.format(invoice.baseServiceFee.toInt())}',
                      ),
                      if (invoice.extraPartsTotal > 0)
                        _pdfTotalRow(
                          'Extra Parts',
                          'Rs. ${fmt.format(invoice.extraPartsTotal.toInt())}',
                        ),
                      if (invoice.platformFee > 0)
                        _pdfTotalRow(
                          'Platform & Safety Fee',
                          'Rs. ${fmt.format(invoice.platformFee.toInt())}',
                        ),
                      if (invoice.urgentFee > 0)
                        _pdfTotalRow(
                          'Urgent Fee',
                          'Rs. ${fmt.format(invoice.urgentFee.toInt())}',
                        ),
                      if (invoice.couponDiscount > 0)
                        _pdfTotalRow(
                          'Coupon used (${invoice.couponCode ?? ''})',
                          '-Rs. ${fmt.format(invoice.couponDiscount.toInt())}',
                        ),
                      pw.Divider(color: PdfColors.grey400),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'TOTAL',
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          pw.Text(
                            'Rs. ${fmt.format(invoice.totalAmount.toInt())}',
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 14,
                              color: const PdfColor.fromInt(0xFF2563EB),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              pw.SizedBox(height: 20),

              // ── Payment info ──
              if (invoice.paymentMethod != null || invoice.transactionId != null)
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Payment Details',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      if (invoice.paymentMethod != null)
                        _pdfMetaRow('Method:', invoice.paymentMethod!),
                      if (invoice.transactionId != null &&
                          invoice.transactionId!.isNotEmpty)
                        _pdfMetaRow('Razorpay ID:', invoice.transactionId!),
                    ],
                  ),
                ),

              pw.Spacer(),

              // ── Footer ──
              pw.Divider(color: PdfColors.grey300),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text(
                  'Thank you for choosing Fixly - India\'s trusted home service platform.',
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey500,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  Future<void> _downloadPdf() async {
    setState(() => _isDownloading = true);
    try {
      final bytes = await _buildPdf();
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'Fixly_Invoice_${widget.invoice.bookingId.substring(widget.invoice.bookingId.length > 8 ? widget.invoice.bookingId.length - 8 : 0)}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ToastUtils.showToast(
        context: context,
        message: 'Could not generate PDF: ${e.toString()}',
      );
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  // ── Navigate to support chat pre-filled with booking ID ──
  Future<void> _reportIssue() async {
    final invoice = widget.invoice;
    setState(() => _isReporting = true);

    try {
      // Pre-fill a message in the support cubit (best effort)
      final msg =
          '🔖 Report for Booking: ${invoice.bookingId}\n'
          '📋 Service: ${invoice.serviceName}\n'
          '💰 Amount: ₹${invoice.totalAmount.toInt()}\n'
          '━━━━━━━━━━━━━━━━━━━━\n'
          'Please describe the issue you are facing with this booking:';

      if (!mounted) return;

      // If SupportCubit is already in the tree, try to pre-seed the message
      try {
        final cubit = context.read<SupportCubit>();
        await cubit.sendMessage(msg);
      } catch (_) {
        // SupportCubit might not be in scope here — that's fine
      }

      if (!mounted) return;
      context.push(RouteNames.sharedSupportChat);
    } finally {
      if (mounted) setState(() => _isReporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invoice = widget.invoice;
    final theme = Theme.of(context);
    final isPaid = invoice.paymentStatus == 'PAID';
    final fmt = NumberFormat('#,##0', 'en_IN');
    final dateFmt = DateFormat('dd MMM yyyy');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // ─── Invoice Header Card ───────────────────────────────────────
        _InvoiceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Branding + status
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.asset(
                    'assets/app_name.png',
                    height: 48,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'SERVICE INVOICE',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  _StatusBadge(status: invoice.paymentStatus ?? 'PENDING'),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: 16),

              // Service name
              Text(
                invoice.serviceName,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.tag_rounded,
                    size: 13,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      invoice.bookingId,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Customer & Worker row
              Row(
                children: [
                  Expanded(
                    child: _PersonTile(
                      icon: Icons.account_circle_outlined,
                      label: 'Customer',
                      name: invoice.customerName ?? 'Customer',
                      sub: invoice.customerPhone,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PersonTile(
                      icon: Icons.engineering_outlined,
                      label: 'Professional',
                      name: invoice.workerName ?? 'Fixly Pro',
                      sub: invoice.workerPhone,
                    ),
                  ),
                ],
              ),

              if (invoice.jobStartedAt != null ||
                  invoice.jobCompletedAt != null) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (invoice.jobStartedAt != null)
                      _MetaPill(
                        icon: Icons.play_circle_outline_rounded,
                        label:
                            'Started ${dateFmt.format(invoice.jobStartedAt!.toLocal())}',
                        color: Colors.orange,
                      ),
                    if (invoice.jobCompletedAt != null)
                      _MetaPill(
                        icon: Icons.check_circle_outline_rounded,
                        label:
                            'Done ${dateFmt.format(invoice.jobCompletedAt!.toLocal())}',
                        color: AppColors.success,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 14),

        // ─── Line Items Table ──────────────────────────────────────────
        _InvoiceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Service Breakdown',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),

              // Table header
              _TableHeader(),

              const SizedBox(height: 8),

              // Base service line — no qty shown for a service
              _LineItem(
                description: invoice.serviceName,
                rate: invoice.baseServiceFee,
                amount: invoice.baseServiceFee,
                showQty: false,
              ),

              // Add-on parts
              for (final part in invoice.addOns)
                _LineItem(
                  description: part.title,
                  qty: part.quantity,
                  rate: part.price,
                  amount: part.price * part.quantity,
                ),
              // Platform fee is shown in the summary below, not as a line item

              const SizedBox(height: 16),
              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: 12),

              // Sub-totals
              _SummaryRow(
                label: 'Base Service Fee',
                value: '₹${fmt.format(invoice.baseServiceFee.toInt())}',
              ),
              if (invoice.extraPartsTotal > 0) ...[
                const SizedBox(height: 6),
                _SummaryRow(
                  label: 'Extra Parts Total',
                  value: '₹${fmt.format(invoice.extraPartsTotal.toInt())}',
                ),
              ],
              if (invoice.platformFee > 0) ...[
                const SizedBox(height: 6),
                _SummaryRow(
                  label: 'Platform & Safety Fee',
                  value: '₹${fmt.format(invoice.platformFee.toInt())}',
                ),
              ],
              if (invoice.urgentFee > 0) ...[
                const SizedBox(height: 6),
                _SummaryRow(
                  label: 'Emergency / Urgent Fee',
                  value: '₹${fmt.format(invoice.urgentFee.toInt())}',
                ),
              ],
              if (invoice.couponDiscount > 0) ...[
                const SizedBox(height: 6),
                _SummaryRow(
                  label: 'Coupon used (${invoice.couponCode ?? ''})',
                  value: '-₹${fmt.format(invoice.couponDiscount.toInt())}',
                ),
              ],

              const SizedBox(height: 10),

              // Total amount highlight
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary50, Color(0xFFDBEAFE)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primary200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TOTAL AMOUNT',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppColors.primaryDark,
                        letterSpacing: 0.4,
                      ),
                    ),
                    Text(
                      '₹${fmt.format(invoice.totalAmount.toInt())}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ─── Payment Details Card ──────────────────────────────────────
        if (invoice.paymentMethod != null || invoice.transactionId != null) ...[
          const SizedBox(height: 14),
          _InvoiceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Payment Details',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                if (invoice.paymentMethod != null)
                  _DetailRow(
                    icon: Icons.payment_rounded,
                    label: 'Payment Method',
                    value: invoice.paymentMethod!.toUpperCase(),
                  ),
                if (invoice.transactionId != null &&
                    invoice.transactionId!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _DetailRow(
                    icon: Icons.receipt_rounded,
                    label: 'Razorpay Transaction ID',
                    value: invoice.transactionId!,
                    mono: true,
                  ),
                ],
                if (isPaid) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.success.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.verified_rounded,
                          color: AppColors.success,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Payment confirmed & verified',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],

        const SizedBox(height: 24),

        // ─── Action Buttons ────────────────────────────────────────────

        // Pay button (only if unpaid)
        if (!isPaid) ...[
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              icon: _isPaying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.payment_rounded, size: 20),
              label: Text(
                _isPaying
                    ? 'Processing…'
                    : 'Pay ₹${fmt.format(invoice.totalAmount.toInt())} with Razorpay',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              onPressed: _isPaying ? null : _payWithRazorpay,
            ),
          ),
          const SizedBox(height: 10),
        ],

        // Download + Report row
        Row(
          children: [
            Expanded(
              child: _PlainActionButton(
                icon: _isDownloading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded, size: 18),
                label: 'Download PDF',
                onPressed: _isDownloading ? null : _downloadPdf,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PlainActionButton(
                icon: _isReporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.flag_outlined, size: 18),
                label: 'Report Issue',
                onPressed: _isReporting ? null : _reportIssue,
              ),
            ),
          ],
        ),

        if (isPaid) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: _closeInvoice,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Close',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ] else ...[
          const SizedBox(height: 10),
          TextButton(
            onPressed: _closeInvoice,
            child: const Text(
              'Close Invoice',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],

        // Footer note
        const SizedBox(height: 16),
        Center(
          child: Text(
            '🛡️  All transactions are secured by Razorpay & Fixly.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  // ── PDF helpers ──────────────────────────────────────────────────────────

  PdfColor _pdfStatusColor(String? status) {
    switch (status) {
      case 'PAID':
        return const PdfColor.fromInt(0xFF10B981);
      case 'PAYMENT_PENDING':
        return const PdfColor.fromInt(0xFFF59E0B);
      default:
        return const PdfColor.fromInt(0xFF64748B);
    }
  }

  pw.Widget _pdfTableHeader(String text, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          color: PdfColors.white,
          fontWeight: pw.FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }

  pw.Widget _pdfTableCell(String text, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: pw.Text(
        text,
        textAlign: align,
        style: const pw.TextStyle(fontSize: 10),
      ),
    );
  }

  pw.Widget _pdfTotalRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
          pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
        ],
      ),
    );
  }

  pw.Widget _pdfMetaRow(String label, String value) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
        ),
        pw.SizedBox(width: 4),
        pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  Color _bg() {
    switch (status) {
      case 'PAID':
        return AppColors.success.withValues(alpha: 0.12);
      case 'PAYMENT_PENDING':
        return AppColors.warning.withValues(alpha: 0.12);
      default:
        return AppColors.primary50;
    }
  }

  Color _fg() {
    switch (status) {
      case 'PAID':
        return AppColors.success;
      case 'PAYMENT_PENDING':
        return AppColors.warning;
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _bg(),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _fg().withValues(alpha: 0.3)),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: TextStyle(
          color: _fg(),
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({
    required this.icon,
    required this.label,
    required this.name,
    this.sub,
  });

  final IconData icon;
  final String label;
  final String name;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.primary50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (sub != null)
                  Text(
                    sub!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
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

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              'Description',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              'Qty',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              'Rate',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          SizedBox(
            width: 75,
            child: Text(
              'Amount',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LineItem extends StatelessWidget {
  const _LineItem({
    required this.description,
    required this.rate,
    required this.amount,
    this.qty = 1,
    this.showQty = true,
  });

  final String description;
  final int qty;
  final double rate;
  final double amount;
  final bool showQty;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'en_IN');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              description,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              showQty ? qty.toString() : '',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              '₹${fmt.format(rate.toInt())}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
            ),
          ),
          SizedBox(
            width: 75,
            child: Text(
              '₹${fmt.format(amount.toInt())}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.mono = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  fontFamily: mono ? 'monospace' : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlainActionButton extends StatelessWidget {
  const _PlainActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Widget icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.border),
          foregroundColor: AppColors.textPrimary,
          backgroundColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

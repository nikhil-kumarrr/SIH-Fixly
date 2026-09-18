import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/router/route_names.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/l10n/category_localizer.dart';
import '../../../../core/navigation/screen_refresh.dart';
import '../../../../core/network/api_config.dart';
import '../../../../core/preferences/app_preferences.dart';
import '../../../../core/utils/toast_utils.dart';
import '../../../../core/widgets/core_widgets.dart';
import '../../../../services/webrtc_call_service.dart';
import '../../../../shared/models/models.dart';
import '../../../bookings/data/bookings_api_repository.dart';
import '../../../shared/data/service_scope_data.dart';
import '../cubit/job_feed_cubit.dart';

class WorkerOrderDetailPage extends StatefulWidget {
  const WorkerOrderDetailPage({required this.jobId, super.key});

  final String jobId;

  @override
  State<WorkerOrderDetailPage> createState() => _WorkerOrderDetailPageState();
}

class _WorkerOrderDetailPageState extends State<WorkerOrderDetailPage>
    with RefreshWhenNavigatedTo {
  Booking? _booking;
  WorkerJob? _feedJob;
  bool _loading = true;
  bool _accepting = false;
  String? _error;

  @override
  List<String> get refreshRoutePaths => [RouteNames.workerJobDetail];

  @override
  void onScreenRefresh() {
    unawaited(_resolve(forceNetwork: true));
  }

  @override
  void initState() {
    super.initState();
    unawaited(_resolve());
  }

  Future<void> _resolve({bool forceNetwork = false}) async {
    try {
      final booking = await BookingsApiRepository().getById(
        widget.jobId,
        forceNetwork: forceNetwork,
      );
      if (!mounted) return;
      setState(() {
        _booking = booking;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _feedJob = context.read<JobFeedCubit>().jobById(widget.jobId);
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _accept() async {
    if (_accepting) return;
    setState(() => _accepting = true);
    try {
      await BookingsApiRepository().accept(widget.jobId);
      await AppPreferences.instance.setActiveWorkerJobId(widget.jobId);
      if (!mounted) return;
      ToastUtils.showSuccess(
        context: context,
        message: '🎉 Booking accepted! Head to the customer location.',
      );
      context.goRefreshing(RouteNames.workerActiveJob);
    } catch (e) {
      if (!mounted) return;
      setState(() => _accepting = false);
      ToastUtils.showError(context: context, message: e.toString());
    }
  }

  Future<void> _callCustomerWebRtc() async {
    final bookingId = _booking?.id ?? widget.jobId;
    if (bookingId.isEmpty) {
      if (!mounted) return;
      ToastUtils.showError(context: context, message: 'Booking ID not available');
      return;
    }
    final peerName =
        (_booking?.customerName ?? _feedJob?.customerName ?? 'Customer').trim();
    final peerAvatar = _booking?.customerAvatar ?? _feedJob?.customerAvatar;
    final serviceTitle =
        _booking?.serviceTitle ?? _feedJob?.title ?? 'Fixly Service';

    context.push(
      RouteNames.call,
      extra: {
        'bookingId': bookingId,
        'peerName': peerName.isEmpty ? 'Customer' : peerName,
        'peerRole': 'customer',
        'peerAvatar': peerAvatar,
        'serviceTitle': serviceTitle,
        'isIncoming': false,
      },
    );

    final success = await WebRTCCallService.instance.startCall(
      bookingId: bookingId,
      expectedPeerName: peerName.isEmpty ? 'Customer' : peerName,
      expectedPeerRole: 'customer',
      expectedPeerAvatar: peerAvatar,
      expectedServiceTitle: serviceTitle,
    );

    if (!success && mounted) {
      ToastUtils.showError(context: context, message: 'Could not connect call');
    }
  }

  String _formatMediaUrl(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final base = ApiConfig.baseUrl.endsWith('/')
        ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
        : ApiConfig.baseUrl;
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return '$base$cleanPath';
  }

  void _previewImage(BuildContext context, String url) {
    final fullUrl = _formatMediaUrl(url);
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black.withValues(alpha: 0.9),
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                clipBehavior: Clip.none,
                child: Image.network(
                  fullUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  },
                  errorBuilder: (_, _, _) => const Center(
                    child: Text(
                      'Unable to load photo',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMediaUrl(String url) async {
    final fullUrl = _formatMediaUrl(url);
    final uri = Uri.parse(fullUrl);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    if (_loading) {
      return AppScaffold(
        title: context.l10n.orderDetails,
        showBack: true,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final booking = _booking;
    final fallback = _feedJob;
    if (booking == null && fallback == null) {
      return AppScaffold(
        title: context.l10n.orderDetails,
        showBack: true,
        body: Center(child: Text(_error ?? 'Booking not found')),
      );
    }

    // ── Data resolution ──────────────────────────────────────────────────────
    final title = booking?.serviceTitle ?? fallback?.title ?? 'Service Booking';
    final displayId = booking?.displayId;
    final customerName = (booking?.customerName ?? fallback?.customerName ?? '').trim();
    final customerPhone = booking?.customerPhone ?? fallback?.customerPhone;
    final customerAvatar = booking?.customerAvatar ?? fallback?.customerAvatar;
    final address = booking?.address ?? fallback?.address ?? '';
    final category = booking?.serviceCategory ?? fallback?.serviceCategory ?? '';
    final amount = booking?.workerPayout ?? fallback?.workerPayout ?? fallback?.pay ?? 0.0;
    final platformFee = booking?.platformFee ?? booking?.invoice?.platformFee ?? fallback?.platformFee ?? 0.0;
    final customerPaid = booking?.totalAmount ?? booking?.invoice?.totalAmount ?? booking?.totalPrice;
    final createdAt = booking?.createdAt;

    final isPending = booking?.status == BookingStatus.searching ||
        fallback?.status == JobStatus.incoming;
    final isActive = booking?.status == BookingStatus.accepted ||
        booking?.status == BookingStatus.arrived ||
        booking?.status == BookingStatus.inProgress ||
        fallback?.status == JobStatus.active;
    final isCompleted = booking?.status == BookingStatus.completed ||
        booking?.status == BookingStatus.paid ||
        fallback?.status == JobStatus.completed;

    final isSos = booking?.isSosBooking ?? fallback?.isSosBooking ?? false;
    final isScheduled = booking?.isScheduledBooking ?? fallback?.isScheduledBooking ?? false;
    final scheduledAt = booking?.scheduledAt ?? fallback?.scheduledAt;
    final timeSlot = booking?.timeSlot;

    final problemDesc = booking?.problemDescription ?? fallback?.problemDescription;
    final photos = booking?.problemPhotos.isNotEmpty == true
        ? booking!.problemPhotos
        : (fallback?.problemPhotos ?? const <String>[]);
    final videos = booking?.problemVideos.isNotEmpty == true
        ? booking!.problemVideos
        : (fallback?.problemVideos ?? const <String>[]);

    // ── Surface colours ──────────────────────────────────────────────────────
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final mutedText = isDark ? Colors.white54 : const Color(0xFF64748B);

    return AppScaffold(
      title: context.l10n.orderDetails,
      showBack: true,
      body: AppRefreshIndicator(
        onRefresh: _resolve,
        child: SingleChildScrollView(
          physics: appRefreshScrollPhysics,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Status Banner ─────────────────────────────────────────────
              if (isPending)
                _StatusBanner(
                  icon: Icons.hourglass_top_rounded,
                  title: 'Waiting for your response',
                  subtitle: 'Accept to get navigation & customer contact.',
                  color: const Color(0xFFF59E0B),
                  isDark: isDark,
                )
              else if (isActive)
                _StatusBanner(
                  icon: Icons.navigation_rounded,
                  title: 'Job Accepted • En Route',
                  subtitle: 'Customer is expecting your arrival.',
                  color: const Color(0xFF3B82F6),
                  isDark: isDark,
                )
              else if (isCompleted)
                _StatusBanner(
                  icon: Icons.check_circle_outline_rounded,
                  title: 'Order Fulfilled & Settled',
                  subtitle: 'This service request has been completed.',
                  color: const Color(0xFF10B981),
                  isDark: isDark,
                ),

              if (isPending || isActive || isCompleted) const SizedBox(height: 16),

              // ── Title + Payout hero ───────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Job type badge row
                    Row(
                      children: [
                        _JobTypeBadge(isSos: isSos, isScheduled: isScheduled, isDark: isDark),
                        if (category.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                localizeCategory(category, context.l10n.locale),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.primary,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (displayId != null)
                          Text(
                            '#$displayId',
                            style: TextStyle(fontSize: 11, color: mutedText),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Service title + payout
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              height: 1.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '₹${amount.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: scheme.primary,
                              ),
                            ),
                            Text(
                              'Your payout',
                              style: TextStyle(fontSize: 10, color: mutedText),
                            ),
                          ],
                        ),
                      ],
                    ),

                    if (createdAt != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Requested ${DateFormat('MMM d, y • h:mm a').format(createdAt)}',
                        style: TextStyle(fontSize: 11, color: mutedText),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Customer card ─────────────────────────────────────────────
              _SectionLabel('Customer Details', isDark),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  children: [
                    // Avatar + name + phone + call button
                    Row(
                      children: [
                        // Avatar
                        _CustomerAvatar(
                          name: customerName.isNotEmpty ? customerName : 'C',
                          avatarUrl: customerAvatar,
                          isDark: isDark,
                        ),
                        const SizedBox(width: 12),
                        // Name + phone
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                customerName.isNotEmpty ? customerName : 'Customer',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              if (customerPhone != null && customerPhone.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  customerPhone,
                                  style: TextStyle(fontSize: 12, color: mutedText),
                                ),
                              ] else ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Phone not available',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                    color: mutedText,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Call button — in-app WebRTC only (never tel:)
                        FilledButton.tonalIcon(
                            onPressed: _callCustomerWebRtc,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.phone_rounded, size: 14),
                            label: const Text(
                              'Call',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ),
                      ],
                    ),

                    // Address
                    if (address.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Divider(height: 1),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.location_on_outlined, size: 16, color: mutedText),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              address,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white70 : const Color(0xFF334155),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    // Scheduled slot
                    if (isScheduled && scheduledAt != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.schedule_rounded, size: 16, color: mutedText),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Slot: ${DateFormat('EEE, MMM d, y • h:mm a').format(scheduledAt)}'
                              '${timeSlot != null ? '  ($timeSlot)' : ''}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white70 : const Color(0xFF334155),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Problem description & media ────────────────────────────────
              _SectionLabel('Customer Request', isDark),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Issue Description',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: mutedText,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      problemDesc != null && problemDesc.trim().isNotEmpty
                          ? problemDesc.trim()
                          : 'No written description provided by customer.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        fontStyle: problemDesc == null || problemDesc.trim().isEmpty
                            ? FontStyle.italic
                            : FontStyle.normal,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),

                    // Photos
                    if (photos.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Icon(Icons.photo_library_outlined, size: 14, color: mutedText),
                          const SizedBox(width: 6),
                          Text(
                            '${photos.length} Photo${photos.length > 1 ? 's' : ''} • Tap to zoom',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: mutedText,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 88,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: photos.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final photoUrl = photos[index];
                            final formattedUrl = _formatMediaUrl(photoUrl);
                            return InkWell(
                              onTap: () => _previewImage(context, photoUrl),
                              borderRadius: BorderRadius.circular(10),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  width: 88,
                                  height: 88,
                                  color: isDark ? Colors.black26 : const Color(0xFFE2E8F0),
                                  child: Image.network(
                                    formattedUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const Center(
                                      child: Icon(Icons.broken_image_rounded, size: 24),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],

                    // Videos
                    if (videos.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Icon(Icons.videocam_outlined, size: 14, color: mutedText),
                          const SizedBox(width: 6),
                          Text(
                            '${videos.length} Video Attachment${videos.length > 1 ? 's' : ''}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: mutedText,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...videos.map(
                        (vidUrl) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: InkWell(
                            onTap: () => _openMediaUrl(vidUrl),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: cardBorder),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.play_circle_fill_rounded,
                                    size: 20,
                                    color: scheme.primary,
                                  ),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Text(
                                      'View Customer Video Attachment',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Icon(Icons.open_in_new_rounded, size: 14, color: mutedText),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],

                    if (photos.isEmpty && videos.isEmpty && (problemDesc == null || problemDesc.trim().isEmpty))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'No photo or video attachments provided.',
                          style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: mutedText,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Scope & Worker Procedure Guidelines ───────────────────────
              _SectionLabel('Work Scope & Guidelines', isDark),
              const SizedBox(height: 8),
              _buildScopeAndGuidelineCard(context, category, isDark, cardBg, cardBorder, mutedText),

              const SizedBox(height: 16),

              // ── Payout Breakdown ──────────────────────────────────────────
              _SectionLabel('Payout Breakdown', isDark),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  children: [
                    _PriceRow(
                      label: 'Base Service Fee',
                      amount: booking?.baseServiceFee ?? fallback?.baseServiceFee ?? (amount * 0.85),
                      isDark: isDark,
                    ),
                    if (isSos) ...[
                      const SizedBox(height: 8),
                      _PriceRow(
                        label: 'Emergency Dispatch Fee',
                        amount: booking?.urgentFee ?? 100.0,
                        isDark: isDark,
                        highlight: true,
                      ),
                    ],
                    if ((booking?.extraPartsTotal ?? 0) > 0 || (fallback?.extraPartsTotal ?? 0) > 0) ...[
                      const SizedBox(height: 8),
                      _PriceRow(
                        label: 'Approved Replacement Parts',
                        amount: booking?.extraPartsTotal ?? fallback?.extraPartsTotal ?? 0,
                        isDark: isDark,
                      ),
                    ],
                    if (platformFee > 0) ...[
                      const SizedBox(height: 8),
                      _PriceRow(
                        label: 'Platform fee (deducted)',
                        amount: -platformFee,
                        isDark: isDark,
                      ),
                    ],
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(height: 1),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Flexible(
                          child: Text(
                            'Your Payout',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '₹${amount.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ),
                    if (customerPaid != null && platformFee > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Customer paid ₹${customerPaid.toStringAsFixed(0)}',
                        style: TextStyle(fontSize: 11, color: mutedText),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // ── Action Buttons ────────────────────────────────────────────
              if (isPending) ...[
                SwipeActionButton(
                  label: 'Swipe to accept booking',
                  enabled: !_accepting,
                  onCompleted: _accept,
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _accepting
                        ? null
                        : () async {
                            await context.read<JobFeedCubit>().declineJob(widget.jobId);
                            if (context.mounted) context.pop();
                          },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? Colors.white70 : const Color(0xFF475569),
                      side: BorderSide(color: cardBorder),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text(
                      'Decline Job',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ] else if (isActive) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => context.push(RouteNames.workerActiveJob),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.navigation_rounded, size: 18),
                    label: const Text(
                      'Go to Active Job Console',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => context.pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Back to Job Feed'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScopeAndGuidelineCard(
    BuildContext context,
    String category,
    bool isDark,
    Color cardBg,
    Color cardBorder,
    Color mutedText,
  ) {
    final scope = ServiceScopeData.getScopeForCategory(category);
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder),
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
                child: Icon(Icons.assignment_turned_in_outlined, size: 20, color: primaryColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Standard Checklist & Boundaries',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'Review before starting service for ${scope.title}',
                      style: TextStyle(fontSize: 11, color: mutedText),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Included tasks preview
          const Text(
            'WHAT YOU ARE EXPECTED TO DO',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: Color(0xFF16A34A),
            ),
          ),
          const SizedBox(height: 6),
          ...scope.included.take(3).map(
                (task) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle_rounded, size: 15, color: Color(0xFF16A34A)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          task,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark ? Colors.white70 : const Color(0xFF334155),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

          const SizedBox(height: 10),

          // Excluded tasks preview
          const Text(
            'DO NOT PROCEED WITHOUT PRIOR CHARGES / APPROVAL',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: Color(0xFFDC2626),
            ),
          ),
          const SizedBox(height: 6),
          ...scope.excluded.take(2).map(
                (task) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.cancel_rounded, size: 15, color: Color(0xFFDC2626)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          task,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark ? Colors.white70 : const Color(0xFF334155),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

          const SizedBox(height: 12),
          Divider(height: 1, color: cardBorder),
          const SizedBox(height: 10),

          // Button to view full SOP and FAQs
          InkWell(
            onTap: () {
              context.push(
                '${RouteNames.workerFaq}?category=${Uri.encodeComponent(category)}',
              );
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.help_outline_rounded, size: 16, color: primaryColor),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Full SOP, How it Works & Worker FAQs',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_ios_rounded, size: 12, color: primaryColor),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Private sub-widgets ─────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, this.isDark);
  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
          color: isDark ? Colors.white70 : const Color(0xFF475569),
        ),
      );
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.isDark,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.12 : 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _CustomerAvatar extends StatelessWidget {
  const _CustomerAvatar({
    required this.name,
    required this.isDark,
    this.avatarUrl,
  });
  final String name;
  final String? avatarUrl;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final initials = name.isNotEmpty ? name[0].toUpperCase() : 'C';
    final bg = isDark ? Colors.white12 : const Color(0xFF0F172A).withValues(alpha: 0.1);
    final fg = isDark ? Colors.white : const Color(0xFF0F172A);

    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 22,
        backgroundImage: NetworkImage(avatarUrl!),
        backgroundColor: bg,
        onBackgroundImageError: (_, _) {},
        child: null,
      );
    }
    return CircleAvatar(
      radius: 22,
      backgroundColor: bg,
      child: Text(
        initials,
        style: TextStyle(fontWeight: FontWeight.bold, color: fg, fontSize: 16),
      ),
    );
  }
}

class _JobTypeBadge extends StatelessWidget {
  const _JobTypeBadge({
    required this.isSos,
    required this.isScheduled,
    required this.isDark,
  });
  final bool isSos;
  final bool isScheduled;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (isSos) {
      return _badge(
        icon: Icons.warning_amber_rounded,
        label: 'EMERGENCY SOS',
        bg: Colors.red.withValues(alpha: 0.1),
        border: Colors.red.withValues(alpha: 0.4),
        fg: Colors.red,
      );
    }
    if (isScheduled) {
      return _badge(
        icon: Icons.calendar_month_outlined,
        label: 'SCHEDULED',
        bg: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
        border: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
        fg: isDark ? Colors.white70 : const Color(0xFF475569),
      );
    }
    return _badge(
      icon: Icons.flash_on_rounded,
      label: 'ON-DEMAND',
      bg: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
      border: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
      fg: isDark ? Colors.white54 : const Color(0xFF64748B),
    );
  }

  Widget _badge({
    required IconData icon,
    required String label,
    required Color bg,
    required Color border,
    required Color fg,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: fg),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: fg,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      );
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.label,
    required this.amount,
    required this.isDark,
    this.highlight = false,
  });
  final String label;
  final double amount;
  final bool isDark;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white60 : const Color(0xFF64748B),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            amount < 0
                ? '-₹${amount.abs().toStringAsFixed(0)}'
                : '₹${amount.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: amount < 0
                  ? const Color(0xFFDC2626)
                  : (highlight
                      ? Colors.red
                      : (isDark ? Colors.white70 : const Color(0xFF334155))),
            ),
          ),
        ],
      );
}

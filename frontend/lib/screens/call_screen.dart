import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/router/route_names.dart';
import '../services/webrtc_call_service.dart';

class CallScreen extends StatefulWidget {
  final WebRTCCallService? callService;
  final String? bookingId;
  final String? peerName;
  final String? peerRole;
  final String? peerAvatar;
  final String? serviceTitle;
  final bool isIncoming;

  const CallScreen({
    super.key,
    this.callService,
    this.bookingId,
    this.peerName,
    this.peerRole,
    this.peerAvatar,
    this.serviceTitle,
    this.isIncoming = false,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  static const _bgLight = 'assets/images/call_bg_light.jpg';
  static const _bgDark = 'assets/images/call_bg_dark.jpg';

  late WebRTCCallService _service;
  bool _popScheduled = false;
  bool _ending = false;

  @override
  void initState() {
    super.initState();
    _service = widget.callService ?? WebRTCCallService.instance;

    final bId = widget.bookingId ?? _service.currentBookingId;
    if (bId != null && bId.isNotEmpty) {
      _service.currentBookingId ??= bId;
    }

    // Prefer route extras when CallKit left service fields empty.
    if (widget.peerName != null && widget.peerName!.trim().isNotEmpty) {
      _service.peerName = widget.peerName!.trim();
    }
    if (widget.peerRole != null && widget.peerRole!.trim().isNotEmpty) {
      _service.peerRole = widget.peerRole!.trim().toLowerCase();
    }
    if (widget.peerAvatar != null) {
      _service.peerAvatar = widget.peerAvatar;
    }
    if (widget.serviceTitle != null) {
      _service.serviceTitle = widget.serviceTitle;
    }
    if (widget.isIncoming) {
      _service.isOutgoing = false;
    }

    debugPrint(
      '[CallScreen] 📱 CallScreen initialized for booking: $bId, isIncoming: ${widget.isIncoming}, initial state: ${_service.currentState}',
    );

    _service.onCallStateChanged = _onCallStateChanged;
    _service.onFirewallError = _onFirewallError;
    _service.onPeerNetworkIssue = _onPeerNetworkIssue;
  }

  @override
  void dispose() {
    _service.onCallStateChanged = null;
    _service.onFirewallError = null;
    _service.onPeerNetworkIssue = null;
    super.dispose();
  }

  void _onCallStateChanged(CallState state) {
    debugPrint('[CallScreen] 🔄 Call state changed in CallScreen: $state');
    if (!mounted) return;
    setState(() {});
    if (state == CallState.ended || state == CallState.failed) {
      _schedulePop();
    }
  }

  void _onFirewallError(String message) {
    if (!mounted) return;
    _showFirewallDialog(message);
  }

  void _onPeerNetworkIssue(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange.shade800,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _schedulePop() {
    if (_popScheduled) return;
    _popScheduled = true;
    debugPrint('[CallScreen] 🚪 Scheduling screen pop in 500ms');
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        debugPrint('[CallScreen] 🚪 Popping CallScreen now');
        Navigator.of(context).pop();
      } else {
        debugPrint('[CallScreen] 🚪 Cannot pop (at root), navigating to home safely');
        try {
          final isWorker = (_service.peerRole ?? '').toLowerCase().contains('customer');
          if (isWorker) {
            context.go(RouteNames.workerDashboard);
          } else {
            context.go(RouteNames.customerHome);
          }
        } catch (_) {
          context.go(RouteNames.customerHome);
        }
      }
    });
  }

  void _declineCall() {
    if (_ending) return;
    _ending = true;
    final bId = widget.bookingId ?? _service.currentBookingId;
    debugPrint('[CallScreen] 🚫 Decline button tapped for booking: $bId');
    _service.rejectCall(
      bookingId: bId,
      reason: 'DECLINED',
    );
    _schedulePop();
  }

  void _endCall() {
    if (_ending) return;
    _ending = true;
    final bId = widget.bookingId ?? _service.currentBookingId;
    debugPrint(
      '[CallScreen] 🛑 End Call button tapped for booking: $bId, currentState: ${_service.currentState}',
    );

    if (_service.currentState == CallState.ended ||
        _service.currentState == CallState.failed ||
        _service.currentState == CallState.idle) {
      _schedulePop();
      return;
    }

    if (_service.currentState == CallState.ringing &&
        (widget.isIncoming || !_service.isOutgoing)) {
      _service.rejectCall(
        bookingId: bId,
        reason: 'DECLINED',
      );
    } else {
      _service.hangUp(
        bookingIdParam: bId,
        endReason: 'NORMAL_HANGUP',
      );
    }
    _schedulePop();
  }


  /// Peer on the other end: customer ↔ worker.
  String _peerKind() {
    final raw = (widget.peerRole ?? _service.peerRole ?? '').toLowerCase();
    if (raw.contains('customer')) return 'customer';
    if (raw.contains('worker')) return 'worker';
    // Outgoing to customer from worker pages passes peerRole=customer.
    if (_service.isOutgoing && raw.isEmpty) return 'worker';
    return 'worker';
  }

  String _peerKindLabel() =>
      _peerKind() == 'customer' ? 'Customer' : 'Worker';

  String _peerDisplayName() {
    final name = (widget.peerName ?? _service.peerName ?? '').trim();
    if (name.isNotEmpty) return name;
    return _peerKindLabel();
  }

  String _roleSubtitle(CallState state) {
    final kind = _peerKindLabel();
    final title =
        widget.serviceTitle ?? _service.serviceTitle ?? 'Fixly Service';
    final incoming = widget.isIncoming || !_service.isOutgoing;

    switch (state) {
      case CallState.initiating:
      case CallState.ringing:
        return incoming ? '$kind is calling' : 'Calling $kind…';
      case CallState.connected:
        return '$kind • $title';
      case CallState.ended:
        return 'Call ended';
      case CallState.failed:
        return 'Call failed';
      case CallState.idle:
        return kind;
    }
  }

  void _showFirewallDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF22223B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.wifi_off_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'Wi-Fi Firewall Blocked',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _endCall();
            },
            child: const Text('Switch to Mobile Data & Retry'),
          ),
        ],
      ),
    );
  }

  String _formatTimer(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final bgAsset = isDark ? _bgDark : _bgLight;

    final state = _service.currentState;
    final name = _peerDisplayName();
    final subtitle = _roleSubtitle(state);
    final avatar = widget.peerAvatar ?? _service.peerAvatar;

    late final String statusText;
    late final Color statusColor;

    switch (state) {
      case CallState.initiating:
        statusText = 'Connecting...';
        statusColor = const Color(0xFFF59E0B);
        break;
      case CallState.ringing:
        statusText = _service.isOutgoing ? 'Ringing...' : 'Incoming call';
        statusColor = const Color(0xFF38BDF8);
        break;
      case CallState.connected:
        statusText = _formatTimer(_service.callDurationSeconds);
        statusColor = const Color(0xFF10B981);
        break;
      case CallState.ended:
        statusText = 'Call Ended';
        statusColor = Colors.redAccent;
        break;
      case CallState.failed:
        statusText = 'Call Failed';
        statusColor = Colors.redAccent;
        break;
      case CallState.idle:
        statusText = 'Ready';
        statusColor = Colors.white70;
        break;
    }

    // High-contrast text over wallpaper (works on light + dark doodle).
    const fg = Colors.white;
    const fgMuted = Color(0xFFE2E8F0);
    final chipBg = Colors.black.withValues(alpha: 0.42);
    final controlBg = Colors.black.withValues(alpha: 0.45);

    return PopScope(
      canPop: state == CallState.ended ||
          state == CallState.failed ||
          state == CallState.idle,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _endCall();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: Image.asset(
                bgAsset,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, error, stackTrace) => const ColoredBox(
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
            // Light veil so doodle stays visible (was too opaque before).
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x660F172A),
                    Color(0x8F0F172A),
                    Color(0xB30F172A),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: chipBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_outline,
                            size: 14,
                            color: Color(0xFF10B981),
                          ),
                          SizedBox(width: 6),
                          Text(
                            'End-to-End Encrypted • Private Calling',
                            style: TextStyle(
                              fontSize: 12,
                              color: fgMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: (state == CallState.connected
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFF3B82F6))
                                  .withValues(alpha: 0.35),
                              blurRadius: 36,
                              spreadRadius: 8,
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 56,
                          backgroundColor: controlBg,
                          backgroundImage:
                              (avatar != null && avatar.isNotEmpty)
                                  ? NetworkImage(avatar)
                                  : null,
                          child: (avatar == null || avatar.isEmpty)
                              ? const Icon(
                                  Icons.person,
                                  size: 60,
                                  color: fgMuted,
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: fg,
                          letterSpacing: 0.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: chipBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 13,
                            color: fgMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 20,
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: 40,
                      left: 24,
                      right: 24,
                    ),
                    child: (state == CallState.ringing &&
                            (!_service.isOutgoing || widget.isIncoming))
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  FloatingActionButton(
                                    heroTag: 'declineCallFab',
                                    backgroundColor: const Color(0xFFEF4444),
                                    elevation: 6,
                                    onPressed: _declineCall,
                                    child: const Icon(
                                      Icons.call_end,
                                      color: Colors.white,
                                      size: 30,
                                    ),
                                  ),

                                  const SizedBox(height: 8),
                                  const Text(
                                    'Decline',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  FloatingActionButton(
                                    heroTag: 'acceptCallFab',
                                    backgroundColor: const Color(0xFF10B981),
                                    elevation: 6,
                                    onPressed: () async {
                                      final bId = widget.bookingId ??
                                          _service.currentBookingId ??
                                          '';
                                      if (bId.isNotEmpty) {
                                        await _service.acceptCall(
                                          bookingId: bId,
                                          callerName: widget.peerName ??
                                              _service.peerName,
                                          callerRole: widget.peerRole ??
                                              _service.peerRole,
                                          callerAvatar: widget.peerAvatar ??
                                              _service.peerAvatar,
                                          serviceTitleParam:
                                              widget.serviceTitle ??
                                                  _service.serviceTitle,
                                        );
                                        if (mounted) setState(() {});
                                      }
                                    },
                                    child: const Icon(
                                      Icons.call,
                                      color: Colors.white,
                                      size: 30,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Accept',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _CallControlButton(
                                icon: _service.isMuted
                                    ? Icons.mic_off
                                    : Icons.mic,
                                label: _service.isMuted ? 'Unmute' : 'Mute',
                                isActive: _service.isMuted,
                                onPressed: () {
                                  setState(() => _service.toggleMute());
                                },
                              ),
                              FloatingActionButton(
                                heroTag: 'endCallFab',
                                backgroundColor: const Color(0xFFEF4444),
                                elevation: 6,
                                onPressed: _endCall,
                                child: const Icon(
                                  Icons.call_end,
                                  color: Colors.white,
                                  size: 30,
                                ),
                              ),
                              _CallControlButton(
                                icon: _service.isSpeakerOn
                                    ? Icons.volume_up_rounded
                                    : Icons.volume_off_rounded,
                                label: _service.isSpeakerOn
                                    ? 'Speaker On'
                                    : 'Speaker Off',
                                isActive: _service.isSpeakerOn,
                                onPressed: () {
                                  setState(() => _service.toggleSpeaker());
                                },
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallControlButton extends StatelessWidget {
  const _CallControlButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? Colors.white : Colors.black.withValues(alpha: 0.45),
          ),
          child: IconButton(
            icon: Icon(
              icon,
              color: isActive ? const Color(0xFF0F172A) : Colors.white,
            ),
            onPressed: onPressed,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }
}

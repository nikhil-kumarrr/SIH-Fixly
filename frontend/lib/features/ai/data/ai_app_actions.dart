import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_names.dart';
import '../../../core/navigation/customer_navigation.dart';
import '../../../core/utils/toast_utils.dart';
import '../../../services/webrtc_call_service.dart';
import '../../auth/presentation/cubit/app_session_cubit.dart';

/// One in-chat / spoken app action from AI (theme, nav, pay, …).
class AiAppAction {
  const AiAppAction({
    required this.type,
    this.label,
    this.theme,
    this.route,
    this.language,
    this.bookingId,
  });

  final String type;
  final String? label;
  final String? theme;
  final String? route;
  final String? language;
  final String? bookingId;

  factory AiAppAction.fromJson(Map<String, dynamic> json) {
    return AiAppAction(
      type: json['type']?.toString() ?? '',
      label: json['label']?.toString(),
      theme: json['theme']?.toString(),
      route: json['route']?.toString(),
      language: json['language']?.toString(),
      bookingId: (json['bookingId'] ?? json['booking_id'])?.toString(),
    );
  }

  String get buttonLabel {
    if (label != null && label!.trim().isNotEmpty) return label!;
    return type;
  }
}

List<AiAppAction> parseAppActions(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((e) => AiAppAction.fromJson(Map<String, dynamic>.from(e)))
      .where((a) => a.type.isNotEmpty)
      .toList();
}

/// Execute AI app actions. Returns short human note for TTS/chat confirm.
Future<String> executeAiAppActions(
  BuildContext context,
  List<AiAppAction> actions, {
  String? fallbackBookingId,
  void Function(String lang)? onLanguage,
}) async {
  if (actions.isEmpty) return '';
  final notes = <String>[];

  for (final a in actions) {
    try {
      switch (a.type) {
        case 'SET_THEME':
          final cubit = context.read<AppSessionCubit>();
          final current = cubit.state.themeMode;
          final ThemeMode next;
          switch ((a.theme ?? 'toggle').toLowerCase()) {
            case 'dark':
              next = ThemeMode.dark;
            case 'light':
              next = ThemeMode.light;
            case 'system':
              next = ThemeMode.system;
            default:
              next =
                  current == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
          }
          await cubit.setThemeMode(next);
          notes.add(switch (next) {
            ThemeMode.dark => 'Theme set to dark mode',
            ThemeMode.light => 'Theme set to light mode',
            _ => 'Theme set to system',
          });

        case 'SET_LANGUAGE':
          final lang = (a.language ?? 'en').toLowerCase().startsWith('hi')
              ? 'hi'
              : 'en';
          await context.read<AppSessionCubit>().setLocale(lang);
          onLanguage?.call(lang);
          notes.add(lang == 'hi' ? 'Language set to Hindi' : 'Language set to English');

        case 'NAVIGATE':
          _navigateCustomer(context, a.route ?? 'home');
          notes.add('Opened ${a.label ?? a.route ?? 'screen'}');

        case 'PAY_LATEST':
        case 'OPEN_INVOICE':
          final id = _cleanId(a.bookingId ?? fallbackBookingId);
          if (id != null) {
            if (a.type == 'OPEN_INVOICE') {
              context.push('/customer/invoice/$id');
              notes.add('Here is your invoice');
            } else {
              context.push('${RouteNames.customerPayment}?bookingId=$id');
              notes.add('Here is the pay screen');
            }
          } else {
            context.push(RouteNames.customerPayments);
            notes.add('Opened payments — pick a booking to pay');
          }

        case 'TRACK_LATEST':
          final id = _cleanId(a.bookingId ?? fallbackBookingId);
          if (id != null) {
            context.push('${RouteNames.customerTracking}?bookingId=$id');
            notes.add('Opened live tracking');
          } else {
            context.goCustomerTab(3);
            notes.add('Opened bookings to track');
          }

        case 'CALL_WORKER':
          final id = _cleanId(a.bookingId ?? fallbackBookingId);
          if (id == null) {
            ToastUtils.showToast(
              context: context,
              message: 'No active booking to call',
            );
            notes.add('No booking found to call');
            break;
          }
          context.push(
            RouteNames.call,
            extra: {
              'bookingId': id,
              'peerName': 'Worker',
              'peerRole': 'worker',
              'serviceTitle': 'Fixly service',
              'isIncoming': false,
            },
          );
          unawaited(
            WebRTCCallService.instance.startCall(
              bookingId: id,
              expectedPeerName: 'Worker',
              expectedPeerRole: 'worker',
              expectedServiceTitle: 'Fixly service',
            ),
          );
          notes.add('Starting in-app call');

        case 'OPEN_RATING':
          final id = _cleanId(a.bookingId ?? fallbackBookingId);
          if (id != null) {
            context.push(RouteNames.customerRatingPath(id));
            notes.add('Opened rating');
          } else {
            context.goCustomerTab(3);
            notes.add('Opened bookings');
          }

        case 'SHOW_BOOKING_STATUS':
          context.goCustomerTab(3);
          notes.add('Showing your bookings');

        default:
          break;
      }
    } catch (e) {
      debugPrint('AiAppAction ${a.type} failed: $e');
    }
  }
  return notes.join('. ');
}

String? _cleanId(String? raw) {
  final p = raw?.trim();
  if (p == null || p.isEmpty || p.startsWith('#')) return null;
  return p;
}

void _navigateCustomer(BuildContext context, String route) {
  switch (route.toLowerCase()) {
    case 'home':
      context.goCustomerTab(0);
    case 'search':
      context.goCustomerTab(1);
    case 'ai':
    case 'ai_helper':
    case 'categories':
    case 'category':
      CustomerTabSwitcher.switchToAiTab(context: context);
    case 'bookings':
    case 'orders':
      context.goCustomerTab(3);
    case 'profile':
      context.goCustomerTab(4);
    case 'settings':
      context.push(RouteNames.sharedSettings);
    case 'notifications':
      context.push(RouteNames.sharedNotifications);
    case 'support':
      context.push(RouteNames.sharedSupportChat);
    case 'sos':
      context.push(RouteNames.sharedSos);
    case 'discovery':
      context.push(RouteNames.customerAiDiscovery);
    case 'payments':
      context.push(RouteNames.customerPayments);
    default:
      context.goCustomerTab(0);
  }
}

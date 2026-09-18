import 'dart:async';

import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../../core/network/api_exception.dart';
import '../data/payments_api_repository.dart';

class RazorpayCheckoutResult {
  const RazorpayCheckoutResult({
    required this.orderId,
    required this.paymentId,
    required this.signature,
  });

  final String orderId;
  final String paymentId;
  final String signature;
}

class RazorpayCheckoutService {
  Razorpay? _razorpay;

  /// Razorpay cancel / fail often returns "undefined" / empty — never show that.
  static String _friendlyFailure(PaymentFailureResponse response) {
    final fromError = response.error?['description']?.toString() ??
        response.error?['reason']?.toString() ??
        '';
    final raw = (response.message ?? fromError).trim();
    final code = response.code;
    final lower = raw.toLowerCase();
    // code 2 = PAYMENT_CANCELLED in razorpay_flutter
    if (raw.isEmpty ||
        code == 2 ||
        lower == 'undefined' ||
        lower == 'null' ||
        lower.contains('unidentified') ||
        lower.contains('payment_cancelled') ||
        lower.contains('payment cancelled')) {
      return 'Payment failed';
    }
    return ApiException.userFacingMessage(raw);
  }

  Future<RazorpayCheckoutResult> openCheckout({
    required PaymentOrder order,
    required String description,
    String? customerName,
    String? email,
    String? phone,
  }) async {
    _razorpay?.clear();
    _razorpay = Razorpay();
    final completer = Completer<RazorpayCheckoutResult>();

    void completeError(Object error) {
      if (!completer.isCompleted) completer.completeError(error);
      _razorpay?.clear();
    }

    _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse response) {
      final orderId = response.orderId;
      final paymentId = response.paymentId;
      final signature = response.signature;
      if (orderId == null || paymentId == null || signature == null) {
        completeError(ApiException('Payment failed'));
        return;
      }
      if (!completer.isCompleted) {
        completer.complete(
          RazorpayCheckoutResult(
            orderId: orderId,
            paymentId: paymentId,
            signature: signature,
          ),
        );
      }
      _razorpay?.clear();
    });

    _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) {
      completeError(ApiException(_friendlyFailure(response)));
    });

    _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, (_) {});

    final options = <String, dynamic>{
      'key': order.keyId.isNotEmpty ? order.keyId : 'rzp_test_RuFVNyVj523a8U',
      'amount': order.amountPaise.round(),
      'currency': order.currency,
      'name': 'Fixly',
      'order_id': order.orderId,
      'description': description,
      if (customerName != null && customerName.isNotEmpty)
        'prefill': {
          'name': customerName,
          if (email != null && email.isNotEmpty) 'email': email,
          if (phone != null && phone.isNotEmpty) 'contact': phone,
        },
      'theme': {'color': '#2563EB'},
    };

    _razorpay!.open(options);
    return completer.future;
  }

  Future<bool> processPayment({
    required String bookingId,
    required double amountRupees,
    required String description,
    String? customerName,
    String? email,
    String? phone,
    PaymentsApiRepository? paymentsRepo,
  }) async {
    final repo = paymentsRepo ?? PaymentsApiRepository();
    final order = await repo.createOrder(
      bookingId: bookingId,
      amountRupees: amountRupees,
    );
    final result = await openCheckout(
      order: order,
      description: description,
      customerName: customerName,
      email: email,
      phone: phone,
    );
    final verified = await repo.verify(
      razorpayOrderId: result.orderId,
      razorpayPaymentId: result.paymentId,
      razorpaySignature: result.signature,
      bookingId: bookingId,
    );
    return verified;
  }

  void dispose() {
    _razorpay?.clear();
    _razorpay = null;
  }
}

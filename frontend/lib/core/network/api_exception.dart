class ApiException implements Exception {
  ApiException(String message, {this.statusCode})
      : message = userFacingMessage(message);

  final String message;
  final int? statusCode;

  /// Map raw API / Mongo dumps to short UI copy.
  static String userFacingMessage(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'Something went wrong. Please try again.';

    final lower = trimmed.toLowerCase();
    // Razorpay cancel / native bridge often yields "undefined" / "unidentified".
    if (lower == 'undefined' ||
        lower == 'null' ||
        lower == 'exception: undefined' ||
        lower == 'exception: null' ||
        lower.contains('unidentified') ||
        lower.contains('payment_cancelled') ||
        lower.contains('payment cancelled')) {
      return 'Payment failed';
    }
    if (lower.contains('extract geo') ||
        lower.contains('out of bounds') ||
        lower.contains('longitude/latitude') ||
        lower.contains("can't extract geo") ||
        lower.contains('unable to extract geo')) {
      return 'Your location looks invalid. Turn on GPS and try again.';
    }
    if (lower.contains('socketexception') ||
        lower.contains('connection refused') ||
        lower.contains('network is unreachable') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection error') ||
        lower.contains('connection timed out') ||
        lower.contains('connection errored') ||
        lower.contains('no internet') ||
        lower.contains('cannot reach api') ||
        lower.contains('cannot reach server')) {
      // Prefer already-enriched ApiClient message when present.
      if (trimmed.toLowerCase().startsWith('cannot reach api')) {
        return trimmed;
      }
      return 'Cannot reach server. Check internet and API URL, then retry.';
    }
    if (lower.contains('cloudflare tunnel')) {
      return 'API tunnel is down. Restart cloudflared on the host machine.';
    }
    // Truncate only dump-looking payloads — keep full product API copy.
    final looksLikeDump = lower.contains('\n') ||
        lower.contains('stack') ||
        lower.contains('e11000') ||
        lower.contains('cast to') ||
        lower.contains('<html') ||
        lower.contains('mongoerror') ||
        lower.contains('validationerror') ||
        (trimmed.length > 320 && !trimmed.contains('. '));
    if (looksLikeDump && trimmed.length > 140) {
      return 'Something went wrong. Please try again.';
    }
    return trimmed;
  }

  /// Safe copy for snackbars from any thrown object.
  static String fromError(Object error) {
    if (error is ApiException) return error.message;
    return userFacingMessage(error.toString());
  }

  @override
  String toString() => message;
}

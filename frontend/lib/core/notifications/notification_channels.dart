abstract final class NotificationChannels {
  static const String booking = 'fixly_booking';
  static const String workerJobs = 'fixly_worker_jobs';
  static const String payment = 'fixly_payment';
  static const String safety = 'fixly_safety';
  static const String general = 'fixly_general';

  static String forEvent(String? eventType) {
    switch (eventType) {
      case 'SOS_ALERT':
        return safety;
      case 'NEW_BOOKING_AVAILABLE':
      case 'BOOKING_ASSIGNED':
        return workerJobs;
      case 'PAYMENT_SUCCESS':
      case 'PAYMENT_FAILED':
      case 'PAYMENT_RECEIVED':
      case 'WALLET_CREDITED':
      case 'PAYOUT_REQUESTED':
      case 'PAYOUT_PROCESSING':
      case 'PAYOUT_PAID':
      case 'PAYOUT_REJECTED':
        return payment;
      case 'BOOKING_ACCEPTED':
      case 'BOOKING_UPDATED':
      case 'BOOKING_CANCELLED':
      case 'WORKER_ARRIVED':
      case 'WORKER_ON_THE_WAY':
      case 'JOB_STARTED':
      case 'INVOICE_UPDATED':
      case 'JOB_COMPLETED':
        return booking;
      default:
        return general;
    }
  }
}

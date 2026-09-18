abstract final class RouteNames {
  static const splash = '/';
  static const language = '/language';
  static const cooperative = '/cooperative';
  static const federationPicker = '/federation-picker';
  static const role = '/role';
  static const login = '/login';
  static const signup = '/signup';
  static const otp = '/otp';
  static const demo = '/demo';

  static const customerHome = '/customer/home';
  static const customerSearch = '/customer/search';
  static const customerCategorySearch =
      '/customer/home/category-search/:categoryId';

  static String customerCategorySearchPath(String categoryId) =>
      '/customer/home/category-search/$categoryId';
  static const customerOrders = '/customer/orders';
  static const bookingDetail = '/booking/:id';

  static String bookingDetailPath(String bookingId) => '/booking/$bookingId';

  static const customerProfileTab = '/customer/profile';
  static const customerCategories = '/customer/home/categories';
  static const customerService = '/customer/service/:id';
  static const customerBooking = '/customer/booking';
  static const customerPriceEstimate = '/customer/price-estimate';
  static const customerFindingWorker = '/customer/finding-worker';
  static const customerWorkerAccepted = '/customer/worker-accepted';
  static const customerTracking = '/customer/tracking';
  static const customerWorkStarted = '/customer/work-started';
  static const customerPayment = '/customer/payment';
  static const customerPayments = '/customer/payments';
  static const customerRating = '/customer/rating';

  static String customerRatingPath(String bookingId) =>
      '/customer/rating?bookingId=$bookingId';

  static const customerHomeBooking = '/customer/home-booking';
  static const customerAiHelper = '/customer/ai-helper';
  static const customerAiChat = '/customer/ai-chat';
  static const customerAiDiscovery = '/customer/ai-discovery';
  static const customerAiWorkers = '/customer/ai-workers';
  static const customerWorkers = '/customer/workers';
  static const customerWorkerProfile = '/customer/worker/:id';
  static const customerBookingConfirmation = '/customer/booking-confirmation';
  static const customerInvoice = '/customer/invoice/:id';

  static const workerRateSettings = '/worker/rate-settings';
  static const workerPriceEstimation = '/worker/price-estimation';
  static const customerEstimationReview = '/customer/estimation-review';

  static const workerOnboardingIdentity = '/worker/onboarding/identity';
  static const workerOnboardingWork = '/worker/onboarding/work';
  static const workerOnboardingPayout = '/worker/onboarding/payout';
  static const workerOnboardingStatus = '/worker/onboarding/status';
  static const workerOnboardingAvailability = '/worker/onboarding/availability';

  static const workerDashboard = '/worker/dashboard';
  static const workerJobs = '/worker/jobs';
  static const workerProfileTab = '/worker/profile-tab';
  static const workerIncoming = '/worker/incoming';
  static const workerJobDetail = '/worker/job/:id';

  static String workerJobDetailPath(String bookingId) =>
      '/worker/job/$bookingId';
  static const workerActiveJob = '/worker/active-job';
  static const workerNavigation = '/worker/navigation';
  static const workerAvailability = '/worker/availability';
  static const workerEarnings = '/worker/earnings';
  static const workerWallet = '/worker/wallet';
  static const workerProfile = '/worker/profile';
  static const workerReliability = '/worker/reliability';
  static const workerWelfare = '/worker/welfare';
  static const workerCooperative = '/worker/cooperative';
  static const workerFaq = '/worker/faq';
  static const workerOtpEntry = '/worker/otp-entry';
  static const workerAddParts = '/worker/add-parts';
  static const workerRating = '/worker/rating';

  static String workerRatingPath(String bookingId, {String? customerId}) {
    final q = StringBuffer('bookingId=$bookingId');
    if (customerId != null && customerId.isNotEmpty) {
      q.write('&customerId=$customerId');
    }
    return '/worker/rating?$q';
  }

  static const customerWorkerArrived = '/customer/worker-arrived';

  static const sharedProfile = '/shared/profile';
  static const sharedEditProfile = '/shared/edit-profile';
  static const sharedSettings = '/shared/settings';
  static const sharedNotifications = '/shared/notifications';
  static const sharedOrderHistory = '/shared/order-history';
  static const sharedSos = '/shared/sos';
  static const sharedSupportChat = '/shared/support-chat';
  static const sharedSupportTicket = '/shared/support-ticket';

  static const systemState = '/system/:type';
  static const call = '/call';
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/otp_page.dart';
import '../../features/auth/presentation/pages/signup_page.dart';
import '../../features/cooperative/presentation/pages/cooperative_welcome_page.dart';
import '../../features/cooperative/presentation/pages/federation_picker_page.dart';
import '../../screens/call_screen.dart';
import '../../features/customer/presentation/cubit/booking_flow_cubit.dart';
import '../../features/customer/presentation/cubit/tracking_cubit.dart';
import '../../features/customer/presentation/pages/customer_ai_discovery_page.dart';
import '../../features/customer/presentation/pages/customer_ai_helper_page.dart';
import '../../features/customer/presentation/pages/customer_ai_workers_page.dart';
import '../../features/customer/presentation/pages/customer_booking_confirmation_page.dart';
import '../../features/customer/presentation/pages/customer_booking_page.dart';
import '../../features/customer/presentation/pages/customer_invoice_page.dart';
import '../../features/customer/presentation/pages/customer_estimation_review_page.dart';
import '../../features/customer/presentation/pages/customer_categories_page.dart';
import '../../features/customer/presentation/pages/customer_finding_worker_page.dart';
import '../../features/customer/presentation/pages/customer_home_booking_page.dart';
import '../../features/customer/presentation/pages/customer_home_page.dart';
import '../../features/customer/presentation/pages/customer_payment_page.dart';
import '../../features/customer/presentation/pages/customer_payments_page.dart';
import '../../features/customer/presentation/pages/customer_price_estimate_page.dart';
import '../../features/customer/presentation/pages/customer_rating_page.dart';
import '../../features/customer/presentation/pages/customer_search_page.dart';
import '../../features/customer/presentation/pages/customer_service_detail_page.dart';
import '../../features/customer/presentation/pages/customer_tracking_page.dart';
import '../../features/customer/presentation/pages/customer_work_started_page.dart';
import '../../features/customer/presentation/pages/customer_worker_accepted_page.dart';
import '../../features/customer/presentation/pages/customer_worker_arrived_page.dart';
import '../../features/customer/presentation/pages/customer_worker_profile_page.dart';
import '../../features/customer/presentation/pages/customer_workers_page.dart';
import '../../features/demo/presentation/pages/demo_hub_page.dart';
import '../../features/language/presentation/pages/language_page.dart';
import '../../features/role/presentation/pages/role_picker_page.dart';
import '../../features/shared/presentation/cubit/notifications_cubit.dart';
import '../../features/shared/presentation/cubit/profile_cubit.dart';
import '../../features/shared/presentation/cubit/support_cubit.dart';
import '../../features/shared/presentation/pages/edit_profile_page.dart';
import '../../features/shared/presentation/pages/notifications_page.dart';
import '../../features/shared/presentation/pages/order_history_page.dart';
import '../../features/shared/presentation/pages/booking_detail_page.dart';
import '../../features/shared/presentation/pages/profile_hub_page.dart';
import '../../features/shared/presentation/pages/settings_page.dart';
import '../../features/shared/presentation/pages/sos_page.dart';
import '../../features/shared/presentation/pages/support_chat_page.dart';
import '../../features/shared/presentation/pages/support_ticket_page.dart';
import '../../features/splash/presentation/pages/splash_page.dart';
import '../../features/system/presentation/pages/system_state_page.dart';
import '../../features/worker/presentation/cubit/active_job_cubit.dart';
import '../../features/worker/presentation/cubit/job_feed_cubit.dart';
import '../../features/worker/presentation/cubit/wallet_cubit.dart';
import '../../features/worker/presentation/cubit/worker_dashboard_cubit.dart';
import '../../features/worker/presentation/cubit/worker_onboarding_cubit.dart';
import '../../features/worker/presentation/pages/onboarding/worker_availability_page.dart';
import '../../features/worker/presentation/pages/onboarding/worker_identity_page.dart';
import '../../features/worker/presentation/pages/onboarding/worker_onboarding_status_page.dart';
import '../../features/worker/presentation/pages/onboarding/worker_payout_page.dart';
import '../../features/worker/presentation/pages/onboarding/worker_work_profile_page.dart';
import '../../features/worker/presentation/pages/worker_active_job_page.dart';
import '../../features/worker/presentation/pages/worker_add_parts_page.dart';
import '../../features/worker/presentation/pages/worker_availability_status_page.dart';
import '../../features/worker/presentation/pages/worker_dashboard_page.dart';
import '../../features/worker/presentation/pages/worker_earnings_page.dart';
import '../../features/worker/presentation/pages/worker_incoming_orders_page.dart';
import '../../features/worker/presentation/pages/worker_job_feed_page.dart';
import '../../features/worker/presentation/pages/worker_navigation_page.dart';
import '../../features/worker/presentation/pages/worker_order_detail_page.dart';
import '../../features/worker/presentation/pages/worker_otp_entry_page.dart';
import '../../features/worker/presentation/pages/worker_price_estimation_page.dart';
import '../../features/worker/presentation/pages/worker_rate_settings_page.dart';
import '../../features/worker/presentation/pages/worker_profile_page.dart';
import '../../features/worker/presentation/pages/worker_rating_page.dart';
import '../../features/worker/presentation/pages/worker_reliability_page.dart';
import '../../features/worker/presentation/pages/worker_cooperative_page.dart';
import '../../features/worker/presentation/pages/worker_faq_page.dart';
import '../../features/worker/presentation/pages/worker_welfare_page.dart';
import '../../features/worker/presentation/pages/worker_wallet_page.dart';
import '../../core/widgets/customer_main_shell.dart';
import '../../core/widgets/smooth_branch_switcher.dart';
import '../../core/constants/app_constants.dart';
import '../../core/widgets/worker_main_shell.dart';
import 'router_helpers.dart';
import 'route_names.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'rootNav');

final _customerHomeNavKey = GlobalKey<NavigatorState>(debugLabel: 'customerHomeNav');
final _customerSearchNavKey = GlobalKey<NavigatorState>(debugLabel: 'customerSearchNav');
final _customerAiNavKey = GlobalKey<NavigatorState>(debugLabel: 'customerAiNav');
final _customerOrdersNavKey = GlobalKey<NavigatorState>(debugLabel: 'customerOrdersNav');
final _customerProfileNavKey = GlobalKey<NavigatorState>(debugLabel: 'customerProfileNav');

final _workerDashboardNavKey = GlobalKey<NavigatorState>(debugLabel: 'workerDashboardNav');
final _workerJobsNavKey = GlobalKey<NavigatorState>(debugLabel: 'workerJobsNav');
final _workerWalletNavKey = GlobalKey<NavigatorState>(debugLabel: 'workerWalletNav');
final _workerProfileNavKey = GlobalKey<NavigatorState>(debugLabel: 'workerProfileNav');

final _bookingShellNavKey = GlobalKey<NavigatorState>(debugLabel: 'bookingShellNav');

GoRouter createAppRouter() {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: RouteNames.splash,
    routes: [
      _page(RouteNames.splash, (_, s) => const SplashPage()),
      _page(RouteNames.language, (_, s) => const LanguagePage()),
      _page(RouteNames.cooperative, (_, s) => const CooperativeWelcomePage()),
      _page(RouteNames.federationPicker, (_, s) => const FederationPickerPage()),
      _page(RouteNames.role, (_, s) => const RolePickerPage()),
      _page(RouteNames.login, (_, s) => const LoginPage()),
      _page(RouteNames.signup, (_, s) => const SignupPage()),
      _page(RouteNames.otp, (_, s) => const OtpPage()),
      if (kDebugMode) _page(RouteNames.demo, (_, s) => const DemoHubPage()),
      _page(RouteNames.call, (_, s) {
        final extra = s.extra as Map<String, dynamic>?;
        return CallScreen(
          bookingId: extra?['bookingId'] as String?,
          peerName: extra?['peerName'] as String?,
          peerRole: extra?['peerRole'] as String?,
          peerAvatar: extra?['peerAvatar'] as String?,
          serviceTitle: extra?['serviceTitle'] as String?,
          isIncoming: (extra?['isIncoming'] as bool?) ?? false,
        );
      }),

      StatefulShellRoute(
        builder: (context, state, navigationShell) {
          return CustomerMainShell(navigationShell: navigationShell);
        },
        navigatorContainerBuilder: (context, navigationShell, children) {
          return SmoothBranchSwitcher(
            currentIndex: navigationShell.currentIndex,
            children: children,
          );
        },
        branches: [
          StatefulShellBranch(
            navigatorKey: _customerHomeNavKey,
            routes: [
              GoRoute(
                path: RouteNames.customerHome,
                pageBuilder: (context, state) =>
                    transitPage(state: state, child: const CustomerHomePage()),
                routes: [
                  GoRoute(
                    path: 'categories',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) => transitPage(
                      state: state,
                      child: const CustomerCategoriesPage(),
                    ),
                  ),
                  GoRoute(
                    path: 'category-search/:categoryId',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) => transitPage(
                      state: state,
                      child: CustomerSearchPage(
                        categoryId: state.pathParameters['categoryId'],
                        showBack: true,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _customerSearchNavKey,
            routes: [
              _page(
                RouteNames.customerSearch,
                (_, s) => const CustomerSearchPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _customerAiNavKey,
            routes: [
              _page(
                RouteNames.customerAiHelper,
                (_, s) => CustomerAiHelperPage(
                  startInLiveMode: AppConstants.voiceAiEnabled &&
                      s.uri.queryParameters['live'] == '1',
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _customerOrdersNavKey,
            routes: [
              _page(
                RouteNames.customerOrders,
                (_, s) => const OrderHistoryPage(showBack: false),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _customerProfileNavKey,
            routes: [
              _page(
                RouteNames.customerProfileTab,
                (_, s) => BlocProvider(
                  create: (_) => ProfileCubit()..load(),
                  child: const ProfileHubPage(),
                ),
              ),
            ],
          ),
        ],
      ),

      StatefulShellRoute(
        builder: (context, state, navigationShell) {
          return WorkerMainShell(navigationShell: navigationShell);
        },
        navigatorContainerBuilder: (context, navigationShell, children) {
          return SmoothBranchSwitcher(
            currentIndex: navigationShell.currentIndex,
            children: children,
          );
        },
        branches: [
          StatefulShellBranch(
            navigatorKey: _workerDashboardNavKey,
            routes: [
              _page(
                RouteNames.workerDashboard,
                (_, s) => BlocProvider(
                  create: (_) => WorkerDashboardCubit()..load(),
                  child: const WorkerDashboardPage(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _workerJobsNavKey,
            routes: [
              _page(
                RouteNames.workerJobs,
                (_, s) => BlocProvider(
                  create: (_) => JobFeedCubit()..load(),
                  child: const WorkerJobFeedPage(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _workerWalletNavKey,
            routes: [
              _page(
                RouteNames.workerWallet,
                (_, s) => BlocProvider(
                  create: (_) => WalletCubit()..load(),
                  child: const WorkerWalletPage(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _workerProfileNavKey,
            routes: [
              _page(
                RouteNames.workerProfileTab,
                (_, s) => BlocProvider(
                  create: (_) => ProfileCubit()..load(),
                  child: const WorkerProfilePage(),
                ),
              ),
            ],
          ),
        ],
      ),

      // Customer booking shell — shared BookingFlowCubit + TrackingCubit
      ShellRoute(
        navigatorKey: _bookingShellNavKey,
        builder: (context, state, child) {
          return MultiBlocProvider(
            providers: [
              BlocProvider(create: (_) => BookingFlowCubit()),
              BlocProvider(create: (_) => TrackingCubit()),
            ],
            child: child,
          );
        },
        routes: [
          _page(
            RouteNames.customerBooking,
            (_, s) => CustomerBookingPage(
              workerId: s.uri.queryParameters['workerId'],
              serviceId: s.uri.queryParameters['serviceId'],
              categoryId: s.uri.queryParameters['category'] ??
                  s.uri.queryParameters['categoryId'],
            ),
          ),
          _page(
            RouteNames.customerPriceEstimate,
            (_, s) => const CustomerPriceEstimatePage(),
          ),
          _page(
            RouteNames.customerEstimationReview,
            (_, s) => CustomerEstimationReviewPage(
              bookingId: s.uri.queryParameters['bookingId'] ?? '',
            ),
          ),
          _page(
            RouteNames.customerFindingWorker,
            (_, s) => const CustomerFindingWorkerPage(),
          ),
          _page(
            RouteNames.customerWorkerAccepted,
            (_, s) => const CustomerWorkerAcceptedPage(),
          ),
          _page(
            RouteNames.customerTracking,
            (_, s) => CustomerTrackingPage(
              bookingId: s.uri.queryParameters['bookingId'],
            ),
          ),
          _page(
            RouteNames.customerWorkStarted,
            (_, s) => const CustomerWorkStartedPage(),
          ),
          _page(
            RouteNames.customerPayment,
            (_, s) => CustomerPaymentPage(
              bookingId: s.uri.queryParameters['bookingId'],
            ),
          ),
          _page(
            RouteNames.customerPayments,
            (_, s) => const CustomerPaymentsPage(),
          ),
          _page(
            RouteNames.customerRating,
            (_, s) => CustomerRatingPage(
              bookingId: s.uri.queryParameters['bookingId'],
            ),
          ),
          _page(
            RouteNames.customerWorkerArrived,
            (_, s) => const CustomerWorkerArrivedPage(),
          ),
          _page(
            RouteNames.customerBookingConfirmation,
            (_, s) => const CustomerBookingConfirmationPage(),
          ),
          GoRoute(
            path: RouteNames.customerInvoice,
            pageBuilder: (context, state) => transitPage(
              state: state,
              child: CustomerInvoicePage(
                bookingId: state.pathParameters['id']!,
              ),
            ),
          ),
        ],
      ),

      GoRoute(
        path: RouteNames.customerService,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => transitPage(
          state: state,
          child: CustomerServiceDetailPage(
            serviceId: state.pathParameters['id']!,
          ),
        ),
      ),
      GoRoute(
        path: RouteNames.bookingDetail,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => transitPage(
          state: state,
          child: BookingDetailPage(bookingId: state.pathParameters['id']!),
        ),
      ),
      _page(
        RouteNames.customerHomeBooking,
        (_, s) => const CustomerHomeBookingPage(),
        overlay: true,
      ),
      _page(
        RouteNames.customerAiDiscovery,
        (_, s) => const CustomerAiDiscoveryPage(),
        overlay: true,
      ),
      _page(
        RouteNames.customerAiWorkers,
        (_, s) => const CustomerAiWorkersPage(),
        overlay: true,
      ),
      _page(
        RouteNames.customerWorkers,
        (_, s) => const CustomerWorkersPage(),
        overlay: true,
      ),
      _page(
        RouteNames.customerAiChat,
        (_, s) => CustomerAiHelperPage(
          startInLiveMode: AppConstants.voiceAiEnabled &&
              s.uri.queryParameters['live'] == '1',
        ),
        overlay: true,
      ),
      GoRoute(
        path: RouteNames.customerWorkerProfile,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => transitPage(
          state: state,
          child: CustomerWorkerProfilePage(
            workerId: state.pathParameters['id']!,
            serviceId: state.uri.queryParameters['serviceId'],
          ),
        ),
      ),

      // Worker onboarding shell
      ShellRoute(
        builder: (context, state, child) {
          return BlocProvider(
            create: (_) => WorkerOnboardingCubit(),
            child: child,
          );
        },
        routes: [
          _page(
            RouteNames.workerOnboardingIdentity,
            (_, s) => const WorkerIdentityPage(),
          ),
          _page(
            RouteNames.workerOnboardingWork,
            (_, s) => const WorkerWorkProfilePage(),
          ),
          _page(
            RouteNames.workerOnboardingPayout,
            (_, s) => const WorkerPayoutPage(),
          ),
          _page(
            RouteNames.workerOnboardingStatus,
            (_, s) => const WorkerOnboardingStatusPage(),
          ),
          _page(
            RouteNames.workerOnboardingAvailability,
            (_, s) => const WorkerAvailabilityPage(),
          ),
        ],
      ),

      _page(
        RouteNames.workerIncoming,
        (_, s) => BlocProvider(
          create: (_) => JobFeedCubit()..load(),
          child: const WorkerIncomingOrdersPage(),
        ),
        overlay: true,
      ),
      GoRoute(
        path: RouteNames.workerJobDetail,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => transitPage(
          state: state,
          child: BlocProvider(
            create: (_) => JobFeedCubit()..load(),
            child: WorkerOrderDetailPage(jobId: state.pathParameters['id']!),
          ),
        ),
      ),
      _page(
        RouteNames.workerActiveJob,
        (_, s) => BlocProvider(
          create: (_) => ActiveJobCubit()..load(),
          child: const WorkerActiveJobPage(),
        ),
        overlay: true,
      ),
      _page(
        RouteNames.workerOtpEntry,
        (_, s) => BlocProvider(
          create: (_) => ActiveJobCubit()..load(),
          child: WorkerOtpEntryPage(
            bookingId: s.uri.queryParameters['bookingId'] ?? '',
          ),
        ),
        overlay: true,
      ),
      _page(
        RouteNames.workerPriceEstimation,
        (_, s) => WorkerPriceEstimationPage(
          bookingId: s.uri.queryParameters['bookingId'] ?? '',
        ),
        overlay: true,
      ),
      _page(
        RouteNames.workerRateSettings,
        (_, s) => BlocProvider(
          create: (_) => ProfileCubit()..load(),
          child: const WorkerRateSettingsPage(),
        ),
        overlay: true,
      ),
      _page(
        RouteNames.workerAddParts,
        (_, s) => WorkerAddPartsPage(
          bookingId: s.uri.queryParameters['bookingId'] ?? '',
        ),
        overlay: true,
      ),
      _page(
        RouteNames.workerRating,
        (_, s) => BlocProvider(
          create: (_) => ActiveJobCubit()..load(),
          child: WorkerRatingPage(
            bookingId: s.uri.queryParameters['bookingId'] ?? '',
            customerId: s.uri.queryParameters['customerId'] ?? '',
          ),
        ),
        overlay: true,
      ),
      _page(
        RouteNames.workerNavigation,
        (_, s) =>
            WorkerNavigationPage(bookingId: s.uri.queryParameters['bookingId']),
        overlay: true,
      ),
      _page(
        RouteNames.workerAvailability,
        (_, s) => const WorkerAvailabilityStatusPage(),
        overlay: true,
      ),
      _page(
        RouteNames.workerEarnings,
        (_, s) => const WorkerEarningsPage(),
        overlay: true,
      ),
      _page(
        RouteNames.workerReliability,
        (_, s) => const WorkerReliabilityPage(),
        overlay: true,
      ),
      _page(
        RouteNames.workerWelfare,
        (_, s) => const WorkerWelfarePage(),
        overlay: true,
      ),
      _page(
        RouteNames.workerCooperative,
        (_, s) => const WorkerCooperativePage(),
        overlay: true,
      ),
      _page(
        RouteNames.workerFaq,
        (_, s) => WorkerFaqPage(
          categoryId: s.uri.queryParameters['category'],
        ),
        overlay: true,
      ),

      _page(
        RouteNames.sharedProfile,
        (_, s) => BlocProvider(
          create: (_) => ProfileCubit()..load(),
          child: const ProfileHubPage(),
        ),
        overlay: true,
      ),
      _page(
        RouteNames.sharedEditProfile,
        (_, s) => BlocProvider(
          create: (_) => ProfileCubit()..load(),
          child: const EditProfilePage(),
        ),
        overlay: true,
      ),
      _page(
        RouteNames.sharedSettings,
        (_, s) => const SettingsPage(),
        overlay: true,
      ),
      _page(
        RouteNames.sharedNotifications,
        (_, s) => BlocProvider(
          create: (_) => NotificationsCubit(),
          child: const NotificationsPage(),
        ),
        overlay: true,
      ),
      _page(
        RouteNames.sharedOrderHistory,
        (_, s) => const OrderHistoryPage(),
        overlay: true,
      ),
      _page(
        RouteNames.sharedSos,
        (_, s) => SosPage(
          activeBookingId: s.uri.queryParameters['bookingId'],
        ),
        overlay: true,
      ),
      _page(
        RouteNames.sharedSupportChat,
        (_, s) => BlocProvider(
          create: (_) => SupportCubit()..loadChat(),
          child: const SupportChatPage(),
        ),
        overlay: true,
      ),
      _page(
        RouteNames.sharedSupportTicket,
        (_, s) => BlocProvider(
          create: (_) => SupportCubit(),
          child: const SupportTicketPage(),
        ),
        overlay: true,
      ),

      GoRoute(
        path: RouteNames.systemState,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => transitPage(
          state: state,
          child: SystemStatePage(typeParam: state.pathParameters['type']!),
        ),
      ),
    ],
  );
}

GoRoute _page(
  String path,
  Widget Function(BuildContext, GoRouterState) builder, {
  bool overlay = false,
}) {
  return GoRoute(
    path: path,
    parentNavigatorKey: overlay ? rootNavigatorKey : null,
    pageBuilder: (context, state) =>
        transitPage(state: state, child: builder(context, state)),
  );
}

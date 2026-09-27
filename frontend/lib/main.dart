import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'app/app.dart';
import 'core/binding/fixly_widgets_binding.dart';
import 'core/config/feature_flag.dart';
import 'core/firebase/firebase_bootstrap.dart';
import 'core/network/api_client.dart';
import 'core/notifications/notification_service.dart';
import 'core/preferences/app_preferences.dart';
import 'core/services/mock_worker_simulator_service.dart';
import 'core/utils/app_package_info.dart';

Future<void> main() async {
  final widgetsBinding = FixlyWidgetsBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  await AppPreferences.instance.init();
  await AppPackageInfo.ensureInitialized();
  try {
    await FirebaseBootstrap.init();
  } catch (e) {
    debugPrint('Google Sign-In bootstrap failed: $e');
  }
  await ApiServices.init();
  await NotificationService.instance.initialize();

  // Mock worker (Vaibhav Jain) simulation toggle
  if (kEnableMockWorkerSimulation) {
    MockWorkerSimulatorService.instance.init();
  }

  runApp(const App());
}


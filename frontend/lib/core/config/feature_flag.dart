/// Global feature flags configuration
class FeatureFlags {
  FeatureFlags._();

  /// Set to true to enable mock worker simulation over Socket.io.
  static bool enableMockWorkerSimulation = false;
}

/// Shorthand getter for easy access
bool get kEnableMockWorkerSimulation => FeatureFlags.enableMockWorkerSimulation;

# ==============================================================================
# Dockerfile for Flutter (Android Build & Dev Environment)
# ==============================================================================
# Base image includes:
# - Flutter SDK (stable channel)
# - Android SDK & command-line tools
# - OpenJDK 17
# ==============================================================================
FROM --platform=linux/amd64 ghcr.io/cirruslabs/flutter:stable

# Prevent git directory ownership warnings inside container
RUN git config --global --add safe.directory /app

# Install platforms 35 and 37.0 and create symlink for android-37
RUN yes | sdkmanager "platforms;android-35" "platforms;android-37.0" "ndk;28.2.13676358" "cmake;3.22.1" || true
RUN ln -sf /opt/android-sdk-linux/platforms/android-37.0 /opt/android-sdk-linux/platforms/android-37 || true

# Accept Android SDK licenses automatically
RUN yes | flutter doctor --android-licenses || true

# Configure workspace
WORKDIR /app

# Verify installation during image build
RUN flutter doctor -v

CMD ["bash"]

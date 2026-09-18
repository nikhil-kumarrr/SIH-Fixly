# Proguard / R8 Rules for Fixly Release Build

# Suppress warnings for optional Play Core deferred components
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**

# Flutter Wrapper & Engine
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# WebRTC Native JNI & flutter_webrtc Plugin
-keep class org.webrtc.** { *; }
-keep interface org.webrtc.** { *; }
-keep class com.cloudwebrtc.webrtc.** { *; }
-keep interface com.cloudwebrtc.webrtc.** { *; }
-keep class org.webrtc.audio.** { *; }
-keepclassmembers class org.webrtc.audio.** { *; }
-keepclassmembers class * {
    native <methods>;
}
-keepclasseswithmembernames class * {
    native <methods>;
}

# Audio Session & Audio Manager
-keep class com.ryanheise.audiosession.** { *; }
-keep interface com.ryanheise.audiosession.** { *; }

# Flutter CallKit Incoming
-keep class com.hiennv.flutter_callkit_incoming.** { *; }
-keep interface com.hiennv.flutter_callkit_incoming.** { *; }

# Firebase & Push Notifications
-keep class com.google.firebase.** { *; }
-keep interface com.google.firebase.** { *; }

# OkHttp & Socket.io
-keep class io.socket.** { *; }
-keep interface io.socket.** { *; }
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

# General warnings suppression for third-party libraries
-dontwarn okhttp3.**
-dontwarn io.socket.**
-dontwarn org.webrtc.**
-dontwarn com.google.firebase.**

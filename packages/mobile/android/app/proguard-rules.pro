# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep setters so SharedPreferences works
-keepclassmembers class * {
    void set*(***);
}

# Kotlin - keep only what's needed
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**

# Desugared JDK (java.time, java.util.stream, etc.)
-keep class j$.** { *; }
-keep class javax.** { *; }
-dontwarn j$.**
-dontwarn javax.**

# Keep enum values for JSON serialization
-keepclassmembers enum * { *; }

# Play Core (needed for Flutter app bundle / split APK)
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

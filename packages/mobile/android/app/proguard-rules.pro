# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep setters so SharedPreferences works
-keepclassmembers class * {
    *** *(...);
    void set*(***);
}

# Kotlin
-keep class kotlin.** { *; }
-dontwarn kotlin.**

# Desugared JDK (java.time, java.util.stream, etc.)
-keep class j$.** { *; }
-keep class javax.** { *; }
-dontwarn j$.**
-dontwarn javax.**

# Flutter plugins — keep all native method implementations
-keep class com.** { *; }
-keep class org.** { *; }

# Keep enum values for JSON serialization
-keepclassmembers enum * { *; }

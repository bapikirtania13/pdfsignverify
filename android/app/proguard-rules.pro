# BouncyCastle rules
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

# iText rules
-keep class com.itextpdf.** { *; }
-dontwarn com.itextpdf.**
-dontwarn java.awt.**
-dontwarn java.beans.**
-dontwarn javax.annotation.**
-dontwarn javax.xml.**
-dontwarn org.apache.**

# SLF4J rules (used by iText)
-dontwarn org.slf4j.**

# Keep signature verification classes
-keep class com.pdfsignverify.pdf_sign_verify.** { *; }
-keepclassmembers class com.pdfsignverify.pdf_sign_verify.** { *; }

# Meta Audience Network (Facebook Ads) SDK
-keep class com.facebook.ads.** { *; }
-dontwarn com.facebook.ads.**
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Google Mobile Ads SDK & Mediation Adapters
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.ads.**
-keep class com.google.ads.mediation.** { *; }
-dontwarn com.google.ads.mediation.**
-keep class com.google.android.gms.ads.mediation.** { *; }
-dontwarn com.google.android.gms.ads.mediation.**
-keep class com.google.ads.mediation.facebook.** { *; }

# AndroidX Startup (prevent crash on InitializationProvider)
-keep class * extends androidx.startup.Initializer {
    <init>();
}
-keepnames class * extends androidx.startup.Initializer

# AndroidX Room & WorkManager (prevent "Failed to create an instance of androidx.work.impl.WorkDatabase")
-keep class * extends androidx.room.RoomDatabase {
    <init>();
}
-keep class androidx.room.** { *; }
-dontwarn androidx.room.**
-keep class androidx.work.impl.WorkDatabase { *; }
-keep class androidx.work.impl.WorkDatabase_Impl {
    <init>();
}
-keep class androidx.work.** { *; }
-dontwarn androidx.work.**
-keep class androidx.sqlite.** { *; }
-dontwarn androidx.sqlite.**

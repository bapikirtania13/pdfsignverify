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

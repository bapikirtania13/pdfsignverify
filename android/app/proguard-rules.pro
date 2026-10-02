# BouncyCastle rules
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

# iText rules
-keep class com.itextpdf.** { *; }
-dontwarn com.itextpdf.**

# SLF4J rules (used by iText)
-dontwarn org.slf4j.**

# Keep signature verification classes
-keep class com.pdfsignverify.pdf_sign_verify.** { *; }

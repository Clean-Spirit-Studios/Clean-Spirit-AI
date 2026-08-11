# -----------------------------------------------------------------------
# PdfBox (used by read_pdf_text)
# JP2/JPEG2000 encoder+decoder are optional native libs not bundled on
# Android. Tell R8 to ignore both missing references.
# -----------------------------------------------------------------------
-dontwarn com.gemalto.jp2.JP2Decoder
-dontwarn com.gemalto.jp2.JP2Encoder
-keep class com.tom_roush.pdfbox.filter.** { *; }

# -----------------------------------------------------------------------
# Google Play Core (dynamic feature / deferred component delivery)
# Flutter embeds PlayStoreDeferredComponentManager but it is only used
# when the app is distributed via the Play Store with split APKs.
# A regular APK build does not need these classes - suppress R8 warnings.
# -----------------------------------------------------------------------
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task

# -----------------------------------------------------------------------
# General Flutter keep rules
# -----------------------------------------------------------------------
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

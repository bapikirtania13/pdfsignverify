package com.pdfsignverify.pdf_sign_verify

import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import android.os.Bundle
import android.util.Log
import com.facebook.ads.AudienceNetworkAds

/**
 * MainActivity - Bridge between Flutter UI and native Kotlin verification engine.
 * Uses MethodChannel for communication.
 */
class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.pdfsignverify/verification"
    private val TAG = "PdfSignVerify"
    private var verifier: PdfSignatureVerifier? = null
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            AudienceNetworkAds.buildInitSettings(this)
                .withInitListener { result ->
                    Log.d(TAG, "Meta Audience Network initialized: isSuccess=${result.isSuccess}, message=${result.message}")
                }
                .initialize()
        } catch (e: Exception) {
            Log.e(TAG, "Meta Audience Network initialization error", e)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "verifyPdfSignature" -> {
                    val uriString = call.argument<String>("uri")
                    val password = call.argument<String>("password")
                    if (uriString == null) {
                        result.error("INVALID_ARGUMENT", "URI is required", null)
                        return@setMethodCallHandler
                    }
                    
                    scope.launch {
                        try {
                            if (verifier == null) {
                                verifier = PdfSignatureVerifier(this@MainActivity)
                            }
                            val uri = Uri.parse(uriString)
                            val verificationResult = verifier!!.verifyPdf(uri, password)
                            result.success(verificationResult.toString())
                        } catch (e: Exception) {
                            Log.e(TAG, "Verification failed", e)
                            result.error("VERIFICATION_ERROR", e.message, e.stackTraceToString())
                        }
                    }
                }
                "getAppVersion" -> {
                    try {
                        val pInfo = packageManager.getPackageInfo(packageName, 0)
                        result.success(pInfo.versionName)
                    } catch (e: Exception) {
                        result.success("1.0.9")
                    }
                }
                "savePdfToDownloads" -> {
                    val sourcePath = call.argument<String>("sourcePath")
                    val fileName = call.argument<String>("fileName") ?: "verified_document.pdf"
                    if (sourcePath == null) {
                        result.error("INVALID_ARGUMENT", "sourcePath is required", null)
                        return@setMethodCallHandler
                    }

                    scope.launch(Dispatchers.IO) {
                        try {
                            val srcFile = java.io.File(sourcePath)
                            if (!srcFile.exists()) {
                                withContext(Dispatchers.Main) {
                                    result.error("FILE_NOT_FOUND", "Source file does not exist", null)
                                }
                                return@launch
                            }

                            var cleanName = fileName
                            if (!cleanName.lowercase().endsWith(".pdf")) {
                                cleanName = "$cleanName.pdf"
                            }

                            var savedPathOrUri: String? = null

                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                                val contentValues = android.content.ContentValues().apply {
                                    put(android.provider.MediaStore.MediaColumns.DISPLAY_NAME, cleanName)
                                    put(android.provider.MediaStore.MediaColumns.MIME_TYPE, "application/pdf")
                                    put(android.provider.MediaStore.MediaColumns.RELATIVE_PATH, android.os.Environment.DIRECTORY_DOWNLOADS)
                                    put(android.provider.MediaStore.MediaColumns.IS_PENDING, 1)
                                }

                                val resolver = contentResolver
                                val collection = android.provider.MediaStore.Downloads.getContentUri(android.provider.MediaStore.VOLUME_EXTERNAL_PRIMARY)
                                val itemUri = resolver.insert(collection, contentValues)

                                if (itemUri != null) {
                                    resolver.openOutputStream(itemUri)?.use { out ->
                                        srcFile.inputStream().use { input ->
                                            input.copyTo(out)
                                        }
                                    }

                                    contentValues.clear()
                                    contentValues.put(android.provider.MediaStore.MediaColumns.IS_PENDING, 0)
                                    resolver.update(itemUri, contentValues, null, null)
                                    savedPathOrUri = itemUri.toString()
                                }
                            } else {
                                @Suppress("DEPRECATION")
                                val downloadsDir = android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_DOWNLOADS)
                                if (!downloadsDir.exists()) {
                                    downloadsDir.mkdirs()
                                }
                                val destFile = java.io.File(downloadsDir, cleanName)
                                srcFile.copyTo(destFile, overwrite = true)
                                android.media.MediaScannerConnection.scanFile(
                                    this@MainActivity,
                                    arrayOf(destFile.absolutePath),
                                    arrayOf("application/pdf"),
                                    null
                                )
                                savedPathOrUri = destFile.absolutePath
                            }

                            withContext(Dispatchers.Main) {
                                if (savedPathOrUri != null) {
                                    result.success(savedPathOrUri)
                                } else {
                                    result.error("SAVE_FAILED", "Could not save to MediaStore", null)
                                }
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Error saving PDF to public downloads", e)
                            withContext(Dispatchers.Main) {
                                result.error("SAVE_ERROR", e.message, e.stackTraceToString())
                            }
                        }
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}

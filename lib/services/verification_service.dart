import 'dart:convert';
import 'package:flutter/services.dart';

/// Service that communicates with the native Kotlin verification engine
/// via MethodChannel. All actual cryptographic work happens on the native side.
class VerificationService {
  static const MethodChannel _channel =
      MethodChannel('com.pdfsignverify/verification');

  /// Verify all digital signatures in a PDF file at the given URI.
  /// Returns parsed verification results from the native engine.
  static Future<Map<String, dynamic>> verifyPdf(String uri, {String? password}) async {
    try {
      final String result = await _channel.invokeMethod(
        'verifyPdfSignature',
        {
          'uri': uri,
          if (password != null && password.isNotEmpty) 'password': password,
        },
      );
      return json.decode(result) as Map<String, dynamic>;
    } on PlatformException catch (e) {
      return {
        'status': 'ERROR',
        'error': 'Platform error: ${e.message}',
        'details': e.details?.toString(),
      };
    } catch (e) {
      return {
        'status': 'ERROR',
        'error': 'Verification failed: $e',
      };
    }
  }

  /// Get app version from native side.
  static Future<String> getAppVersion() async {
    try {
      final String version = await _channel.invokeMethod('getAppVersion');
      return version;
    } catch (e) {
      return '1.0.9';
    }
  }
}

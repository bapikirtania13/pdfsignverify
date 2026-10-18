import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Generates a separate verification report file.
/// IMPORTANT: The report is a SEPARATE file - the original PDF is NEVER modified.
class ReportService {
  /// Generate a text-based verification report and return the file path.
  static Future<String> generateReport(Map<String, dynamic> result) async {
    final buffer = StringBuffer();
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    final now = DateTime.now();

    buffer.writeln('╔══════════════════════════════════════════════════════════╗');
    buffer.writeln('║            PDF SIGN VERIFY - VERIFICATION REPORT        ║');
    buffer.writeln('╚══════════════════════════════════════════════════════════╝');
    buffer.writeln();
    buffer.writeln('Report Generated: ${dateFormat.format(now)}');
    buffer.writeln('App Version: PDF Sign Verify v1.0.4');
    buffer.writeln();

    // File Information
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('FILE INFORMATION');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('File Name: ${result['fileName'] ?? 'Unknown'}');
    buffer.writeln('File Size: ${_formatFileSize(result['fileSize'] ?? 0)}');
    buffer.writeln('SHA-256 (Before): ${result['sha256'] ?? 'N/A'}');
    buffer.writeln('SHA-256 (After):  ${result['sha256After'] ?? 'N/A'}');
    buffer.writeln('File Integrity:   ${result['fileIntact'] == true ? '✓ File unchanged' : '✗ File may have been modified'}');
    buffer.writeln('Verification At:  ${result['verificationTimestamp'] ?? dateFormat.format(now)}');
    buffer.writeln();

    // Overall Status
    final status = result['status'] ?? 'UNKNOWN';
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('OVERALL VERIFICATION RESULT');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('Status: ${_getStatusEmoji(status)} $status');
    buffer.writeln('Signatures Found: ${result['signatureCount'] ?? 0}');
    buffer.writeln('PDF Revisions: ${result['totalRevisions'] ?? 'N/A'}');
    buffer.writeln();

    if (status == 'NO_SIGNATURES') {
      buffer.writeln('This PDF does not contain any digital signatures.');
      buffer.writeln();
    }

    // Individual Signatures
    final signatures = result['signatures'] as List<dynamic>? ?? [];
    for (int i = 0; i < signatures.length; i++) {
      final sig = signatures[i] as Map<String, dynamic>;
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      buffer.writeln('SIGNATURE ${i + 1} of ${signatures.length}');
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      final sigStatus = sig['status'] ?? 'UNKNOWN';
      buffer.writeln('Status:              ${_getStatusEmoji(sigStatus)} $sigStatus');
      buffer.writeln('Signature Name:      ${sig['signatureName'] ?? 'N/A'}');
      buffer.writeln('Revision:            ${sig['revision'] ?? 'N/A'} of ${sig['totalRevisions'] ?? 'N/A'}');
      buffer.writeln('Covers Whole Doc:    ${sig['coversWholeDocument'] == true ? '✓ Yes' : '✗ No'}');
      buffer.writeln('Sign Date:           ${sig['signDate'] ?? 'N/A'}');
      buffer.writeln();

      // Verification Details
      buffer.writeln('  ┌─ Verification Details ──────────────────────────────');
      buffer.writeln('  │ Signature Integrity:  ${_getStatusEmoji(sig['signatureIntegrityStatus'] ?? 'UNKNOWN')} ${sig['signatureIntegrityStatus'] ?? 'UNKNOWN'}');
      buffer.writeln('  │ Document Integrity:   ${_getStatusEmoji(sig['documentIntegrityStatus'] ?? 'UNKNOWN')} ${sig['documentIntegrityStatus'] ?? 'UNKNOWN'}');
      buffer.writeln('  │ Certificate Valid:    ${_getStatusEmoji(sig['certificateValidStatus'] ?? 'UNKNOWN')} ${sig['certificateValidStatus'] ?? 'UNKNOWN'}');
      buffer.writeln('  │ Certificate Trust:    ${_getStatusEmoji(sig['trustStatus'] ?? 'UNKNOWN')} ${sig['trustStatus'] ?? 'UNKNOWN'}');
      buffer.writeln('  │ Revocation:           ${_getStatusEmoji(sig['revocationStatus'] ?? 'UNKNOWN')} ${sig['revocationStatus'] ?? 'UNKNOWN'}');
      buffer.writeln('  │ Timestamp:            ${_getStatusEmoji(sig['timestampStatus'] ?? 'UNKNOWN')} ${sig['timestampStatus'] ?? 'UNKNOWN'}');
      buffer.writeln('  └────────────────────────────────────────────────────');
      buffer.writeln();

      // Algorithms
      buffer.writeln('  Digest Algorithm:      ${sig['digestAlgorithm'] ?? 'N/A'}');
      buffer.writeln('  Signature Algorithm:   ${sig['signatureAlgorithm'] ?? 'N/A'}');
      buffer.writeln('  Encryption Algorithm:  ${sig['digestEncryptionAlgorithm'] ?? 'N/A'}');
      buffer.writeln();

      // Certificate Information
      final cert = sig['certificate'] as Map<String, dynamic>?;
      if (cert != null) {
        buffer.writeln('  ┌─ Signer Certificate ─────────────────────────────');
        buffer.writeln('  │ Common Name:      ${cert['commonName'] ?? 'N/A'}');
        buffer.writeln('  │ Organization:     ${cert['organization'] ?? 'N/A'}');
        buffer.writeln('  │ Org Unit:         ${cert['organizationalUnit'] ?? 'N/A'}');
        buffer.writeln('  │ Country:          ${cert['country'] ?? 'N/A'}');
        buffer.writeln('  │ Email:            ${cert['email'] ?? 'N/A'}');
        buffer.writeln('  │ Serial Number:    ${cert['serialNumber'] ?? 'N/A'}');
        buffer.writeln('  │ Valid From:        ${cert['validFrom'] ?? 'N/A'}');
        buffer.writeln('  │ Valid To:          ${cert['validTo'] ?? 'N/A'}');
        buffer.writeln('  │ Currently Valid:   ${cert['currentlyValid'] == true ? '✓ Yes' : '✗ No'}');
        buffer.writeln('  │ Issuer CN:        ${cert['issuerCommonName'] ?? 'N/A'}');
        buffer.writeln('  │ Issuer Org:       ${cert['issuerOrganization'] ?? 'N/A'}');
        buffer.writeln('  │ SHA-256:          ${cert['sha256Fingerprint'] ?? 'N/A'}');
        buffer.writeln('  │ Sig Algorithm:    ${cert['signatureAlgorithm'] ?? 'N/A'}');
        buffer.writeln('  │ Is CA:            ${cert['isCA'] == true ? 'Yes' : 'No'}');
        buffer.writeln('  └────────────────────────────────────────────────────');
        buffer.writeln();
      }

      // Certificate Chain
      final chain = sig['certificateChain'] as List<dynamic>? ?? [];
      if (chain.isNotEmpty) {
        buffer.writeln('  ┌─ Certificate Chain (${chain.length} certificates) ────────');
        for (int j = 0; j < chain.length; j++) {
          final chainCert = chain[j] as Map<String, dynamic>;
          buffer.writeln('  │ [$j] ${chainCert['commonName'] ?? 'N/A'}');
          buffer.writeln('  │     Org: ${chainCert['organization'] ?? 'N/A'}');
          buffer.writeln('  │     Issuer: ${chainCert['issuerCommonName'] ?? 'N/A'}');
          buffer.writeln('  │     Valid: ${chainCert['validFrom'] ?? ''} to ${chainCert['validTo'] ?? ''}');
          if (j < chain.length - 1) buffer.writeln('  │');
        }
        buffer.writeln('  └────────────────────────────────────────────────────');
        buffer.writeln();
      }

      // Trust details
      if (sig['trustMessage'] != null) {
        buffer.writeln('  Trust Details: ${sig['trustMessage']}');
        if (sig['trustedRoot'] != null && (sig['trustedRoot'] as String).isNotEmpty) {
          buffer.writeln('  Trusted Root: ${sig['trustedRoot']}');
        }
      }

      // Revocation details
      if (sig['revocationMessage'] != null) {
        buffer.writeln('  Revocation Details: ${sig['revocationMessage']}');
        buffer.writeln('  Revocation Method: ${sig['revocationMethod'] ?? 'N/A'}');
      }

      // Timestamp details
      if (sig['timestampDate'] != null) {
        buffer.writeln('  Timestamp Date: ${sig['timestampDate']}');
      }
      if (sig['timestampMessage'] != null) {
        buffer.writeln('  Timestamp Details: ${sig['timestampMessage']}');
      }

      buffer.writeln();
    }

    // Disclaimer
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('DISCLAIMER');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('This report was generated by PDF Sign Verify.');
    buffer.writeln('The original PDF was NOT modified during verification.');
    buffer.writeln('This report is a SEPARATE document from the original PDF.');
    buffer.writeln('Verification was performed using cryptographic methods.');
    buffer.writeln('Results depend on available certificate trust stores and');
    buffer.writeln('network access for revocation checking.');
    buffer.writeln();
    buffer.writeln('© PDF Sign Verify ${now.year}');

    // Save to file
    final directory = await getApplicationDocumentsDirectory();
    final fileName = result['fileName'] ?? 'document';
    final cleanName = fileName.replaceAll(RegExp(r'[^\w\s\-\.]'), '_');
    final reportFileName = 'verification_report_${cleanName}_${DateFormat('yyyyMMdd_HHmmss').format(now)}.txt';
    final file = File('${directory.path}/$reportFileName');
    await file.writeAsString(buffer.toString());

    return file.path;
  }

  /// Share the verification report.
  static Future<void> shareReport(String filePath) async {
    await Share.shareXFiles(
      [XFile(filePath)],
      subject: 'PDF Sign Verify - Verification Report',
    );
  }

  static String _getStatusEmoji(String status) {
    switch (status.toUpperCase()) {
      case 'VALID':
      case 'TRUSTED':
      case 'NOT_REVOKED':
        return '✓';
      case 'INVALID':
      case 'REVOKED':
      case 'EXPIRED':
        return '✗';
      case 'WARNING':
      case 'UNTRUSTED':
        return '⚠';
      case 'NOT_PRESENT':
        return '—';
      default:
        return '?';
    }
  }

  static String _formatFileSize(dynamic size) {
    if (size == null) return 'Unknown';
    final bytes = size is int ? size : int.tryParse(size.toString()) ?? 0;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

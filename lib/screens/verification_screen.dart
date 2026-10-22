import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:animate_do/animate_do.dart';
import '../theme/app_theme.dart';
import '../services/report_service.dart';
import '../services/verification_service.dart';
import '../services/pdf_download_service.dart';
import '../services/ad_service.dart';
import '../widgets/app_banner_ad_widget.dart';
import '../widgets/app_native_ad_widget.dart';
import 'pdf_viewer_screen.dart';
import '../widgets/signature_card.dart';
import '../widgets/bouncing_tap.dart';
import '../widgets/app_snack_bar.dart';

class VerificationScreen extends StatefulWidget {
  final Map<String, dynamic> result;
  final String pdfPath;
  final String fileName;
  final String? password;

  const VerificationScreen({
    super.key,
    required this.result,
    required this.pdfPath,
    required this.fileName,
    this.password,
  });

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  Map<String, dynamic> get result => widget.result;
  String get pdfPath => widget.pdfPath;
  String get fileName => widget.fileName;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = result['status'] as String? ?? 'UNKNOWN';
    final signatures = result['signatures'] as List<dynamic>? ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verification Result'),
      ),
      bottomNavigationBar: const AppBannerAdWidget(
        adUnitId: AdService.verifyBannerId,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 1. Overall Status Banner
            FadeInDown(
              duration: const Duration(milliseconds: 400),
              child: _buildStatusBanner(context, status, isDark),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),

                  // 2. PRIMARY ACTION BUTTONS (At the top right below status banner)
                  FadeInUp(
                    delay: const Duration(milliseconds: 150),
                    duration: const Duration(milliseconds: 400),
                    child: _buildActionButtons(context, isDark, status),
                  ),

                  // Native Ad Card below action buttons
                  const SizedBox(height: 16),
                  const AppNativeAdWidget(
                    adUnitId: AdService.nativeAdId,
                  ),

                  const SizedBox(height: 20),

                  // 3. When NO signature is found: Friendly guidance
                  if (status == 'NO_SIGNATURES') ...[
                    FadeInUp(
                      delay: const Duration(milliseconds: 250),
                      duration: const Duration(milliseconds: 400),
                      child: _buildNoSignaturesCard(context, isDark),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // 3b. When PDF could not be read / corrupted: Clear explanation
                  if (status == 'ERROR') ...[
                    FadeInUp(
                      delay: const Duration(milliseconds: 250),
                      duration: const Duration(milliseconds: 400),
                      child: _buildErrorGuidanceCard(context, isDark),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // 4. When signatures exist: Simplified Important Details
                  if (signatures.isNotEmpty) ...[
                    FadeInUp(
                      delay: const Duration(milliseconds: 250),
                      duration: const Duration(milliseconds: 400),
                      child: _buildImportantDetailsCard(context, signatures, isDark),
                    ),
                    const SizedBox(height: 16),

                    // Advanced Technical Details (Collapsible for interested users)
                    FadeInUp(
                      delay: const Duration(milliseconds: 350),
                      duration: const Duration(milliseconds: 400),
                      child: _buildTechnicalDetailsTile(signatures, isDark),
                    ),
                    const SizedBox(height: 24),
                  ],

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner(BuildContext context, String status, bool isDark) {
    Color bannerColor;
    IconData bannerIcon;
    String bannerTitle;
    String bannerSubtitle;
    final sigs = (result['signatures'] as List<dynamic>?) ?? [];
    final hasIntactCryptographicSigs = sigs.isNotEmpty && sigs.every((s) {
      if (s is! Map<String, dynamic>) return false;
      return (s['signatureIntegrity'] == true) &&
             (s['documentIntegrity'] == true) &&
             (s['status'] != 'INVALID');
    });

    final effectiveStatus = (status == 'WARNING' && hasIntactCryptographicSigs) ? 'VALID' : status;

    switch (effectiveStatus) {
      case 'VALID':
        bannerColor = const Color(0xFF008A2A);
        bannerIcon = Icons.check_circle_rounded;
        bannerTitle = 'Digital Signature Valid';
        bannerSubtitle = 'All cryptographic checks passed';
        break;
      case 'INVALID':
        bannerColor = AppTheme.invalidColor;
        bannerIcon = Icons.cancel_rounded;
        bannerTitle = 'Digital Signature Invalid';
        bannerSubtitle = 'Cryptographic verification failed';
        break;
      case 'WARNING':
        bannerColor = AppTheme.warningColor;
        bannerIcon = Icons.warning_rounded;
        bannerTitle = 'Signature Has Warnings';
        bannerSubtitle = 'Some checks could not be fully verified';
        break;
      case 'NO_SIGNATURES':
        bannerColor = AppTheme.warningColor;
        bannerIcon = Icons.warning_amber_rounded;
        bannerTitle = 'No Digital Signature Found';
        bannerSubtitle = 'Please upload a genuine digitally signed PDF';
        break;
      case 'ERROR':
        bannerColor = AppTheme.invalidColor;
        bannerIcon = Icons.error_outline_rounded;
        bannerTitle = 'Unable to Read PDF File';
        bannerSubtitle = _getReadableErrorMessage(result['error'] as String?);
        break;
      default:
        bannerColor = AppTheme.unknownColor;
        bannerIcon = Icons.help_rounded;
        bannerTitle = 'Unknown Status';
        bannerSubtitle = 'Could not determine verification status';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            bannerColor,
            bannerColor.withValues(alpha: 0.88),
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Icon(
              bannerIcon,
              size: 54,
              color: Colors.white,
            ),
            const SizedBox(height: 12),
            Text(
              bannerTitle,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              bannerSubtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.92),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getReadableErrorMessage(String? rawError) {
    if (rawError == null || rawError.isEmpty) {
      return 'This file is damaged or saved in an unsupported format.';
    }
    final lower = rawError.toLowerCase();
    if (lower.contains('password') || lower.contains('encrypt')) {
      return 'This document is protected with a password or encrypted permissions.';
    }
    if (lower.contains('startxref') || lower.contains('xref') || lower.contains('eof') || lower.contains('corrupt') || lower.contains('incomplete')) {
      return 'This PDF file appears to be damaged, corrupted, or an incomplete download.';
    }
    if (lower.contains('not a valid pdf') || lower.contains('magic') || lower.contains('format')) {
      return 'The selected file is not a valid PDF or has an unsupported format.';
    }
    return rawError;
  }

  Widget _buildActionButtons(BuildContext context, bool isDark, String status) {
    final verifiedPath = result['verifiedPdfPath'] as String?;
    final hasVerified = verifiedPath != null && File(verifiedPath).existsSync();

    if (status == 'NO_SIGNATURES' || status == 'ERROR') {
      return Column(
        children: [
          BouncingTap(
            onTap: _pickAndVerifyNewPdf,
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: null, // handled by BouncingTap
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white,
                  disabledBackgroundColor: AppTheme.primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                icon: const Icon(Icons.upload_file_rounded, size: 22),
                label: Text(
                  status == 'ERROR' ? 'Upload Another PDF' : 'Upload Digitally Signed PDF',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          BouncingTap(
            onTap: () => _openPdfViewer(context, preferVerified: false),
            child: SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: null, // handled by BouncingTap
                icon: const Icon(Icons.visibility_rounded, size: 20),
                label: Text(status == 'ERROR' ? 'Try Viewing File' : 'View Uploaded Document'),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        // 1. View Verified PDF
        if (hasVerified) ...[
          BouncingTap(
            onTap: () => _openPdfViewer(context, preferVerified: true),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: null, // handled by BouncingTap
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF008A2A),
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF008A2A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 3,
                ),
                icon: const Icon(Icons.verified_rounded, size: 24),
                label: const Text(
                  'View Verified PDF',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        // 2. View Original Unmodified PDF
        BouncingTap(
          onTap: () => _openPdfViewer(context, preferVerified: !hasVerified),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: null, // handled by BouncingTap
              icon: const Icon(Icons.description_outlined, size: 20),
              label: Text(hasVerified ? 'View Original Unmodified PDF' : 'View PDF'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // 3. Download / Save PDF
        BouncingTap(
          onTap: () {
            PdfDownloadService.showDownloadSheet(
              context: context,
              originalPath: pdfPath,
              verifiedPath: verifiedPath,
              baseFileName: fileName,
            );
          },
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: null, // handled by BouncingTap
              icon: const Icon(Icons.download_rounded, size: 20),
              label: const Text(
                'Download / Save PDF',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? const Color(0xFF1E3A5F) : const Color(0xFF0D47A1),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white,
                disabledBackgroundColor: isDark ? const Color(0xFF1E3A5F) : const Color(0xFF0D47A1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // 4. Export Verification Report
        BouncingTap(
          onTap: () => _exportReport(context),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: null, // handled by BouncingTap
              icon: const Icon(Icons.receipt_long_rounded, size: 20),
              label: const Text('Export Verification Report'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImportantDetailsCard(
    BuildContext context,
    List<dynamic> signatures,
    bool isDark,
  ) {
    final primarySig = signatures.first as Map<String, dynamic>;
    final signerName = primarySig['documentSignerName'] as String? ??
        primarySig['signerName'] as String? ??
        'Signer';
    final signDate = primarySig['formattedSignDate'] as String? ??
        primarySig['signDate'] as String? ??
        'N/A';
    final reason = primarySig['reason'] as String? ?? '';
    final location = primarySig['location'] as String? ?? '';
    final certInfo = primarySig['certificate'] as Map<String, dynamic>?;
    final caName = _getSimplifiedIssuer(certInfo);
    final fileIntact = result['fileIntact'] as bool? ?? false;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurfaceVariant : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF008A2A).withValues(alpha: 0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset(
                'assets/images/green_tick.png',
                width: 26,
                height: 26,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 10),
              Text(
                'Signature Details',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.grey.shade900,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF008A2A).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '✓ Verified',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF008A2A),
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          _buildDetailRow(Icons.person_rounded, 'Signer Name', signerName, isDark, isHighlight: true),
          _buildDetailRow(Icons.access_time_rounded, 'Signing Time', signDate, isDark),
          if (reason.isNotEmpty)
            _buildDetailRow(Icons.help_outline_rounded, 'Reason', reason, isDark),
          if (location.isNotEmpty)
            _buildDetailRow(Icons.location_on_outlined, 'Location', location, isDark),
          _buildDetailRow(
            Icons.shield_rounded,
            'Document Integrity',
            fileIntact ? '✓ Document is authentic & unaltered' : '✗ Modified after signing',
            isDark,
            valueColor: fileIntact ? const Color(0xFF008A2A) : AppTheme.invalidColor,
          ),
          _buildDetailRow(Icons.account_balance_rounded, 'Certified By', caName, isDark),
          _buildDetailRow(Icons.picture_as_pdf_rounded, 'File Name', fileName, isDark),
          if (certInfo != null) ...[
            const SizedBox(height: 12),
            BouncingTap(
              onTap: () => _showCertificateModal(context, certInfo, isDark),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: null, // handled by BouncingTap
                  icon: const Icon(Icons.security_rounded, size: 18),
                  label: const Text(
                    'Inspect Certificate & Trust Chain',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showCertificateModal(BuildContext context, Map<String, dynamic> certInfo, bool isDark) {
    final subject = certInfo['subject'] as String? ?? 'Signer';
    final issuer = certInfo['issuer'] as String? ?? 'Certificate Authority';
    final validFrom = certInfo['validFrom'] as String? ?? 'N/A';
    final validUntil = certInfo['validUntil'] as String? ?? 'N/A';
    final thumbprint = certInfo['sha256Thumbprint'] as String? ??
        certInfo['fingerprint'] as String? ??
        certInfo['serialNumber'] as String? ??
        '';
    final sigAlg = certInfo['signatureAlgorithm'] as String? ?? 'SHA256withRSA';
    final keyAlg = certInfo['keyAlgorithm'] as String? ?? 'RSA 2048-bit';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).padding.bottom;

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.82,
          maxChildSize: 0.95,
          minChildSize: 0.50,
          builder: (_, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.shield_outlined, color: AppTheme.primaryColor, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'X.509 Digital Certificate',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 16),
                // Expanded scrollable details
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    children: [
                      // Trust Hierarchy Tree
                      Text(
                        'Trust Chain Hierarchy',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          color: isDark ? Colors.white60 : Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.darkSurfaceVariant : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.account_balance_rounded, size: 16, color: Color(0xFF008A2A)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Root CA: ${_getSimplifiedIssuer(certInfo)}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 7),
                              child: Container(
                                width: 2,
                                height: 18,
                                color: const Color(0xFF008A2A).withValues(alpha: 0.5),
                              ),
                            ),
                            Row(
                              children: [
                                const Icon(Icons.verified_user_rounded, size: 16, color: AppTheme.primaryColor),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Signer: $subject',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      // Detailed Fields
                      _buildModalRow('Subject (Owner)', subject, isDark),
                      _buildModalRow('Issuer (CA)', issuer, isDark),
                      _buildModalRow('Valid From', validFrom, isDark),
                      _buildModalRow('Valid Until', validUntil, isDark),
                      _buildModalRow('Key Type & Algorithm', '$keyAlg ($sigAlg)', isDark),
                      if (thumbprint.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'SHA-256 Fingerprint',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white60 : Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.black26 : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: SelectableText(
                                  thumbprint,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, size: 18),
                                tooltip: 'Copy Fingerprint',
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: thumbprint));
                                  AppSnackBar.show(
                                    context,
                                    message: 'Fingerprint copied to clipboard',
                                    duration: const Duration(seconds: 2),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                // Pinned Bottom Action with safe area clearance
                Container(
                  padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkSurface : Colors.white,
                    border: Border(
                      top: BorderSide(
                        color: isDark ? Colors.white12 : Colors.grey.shade200,
                        width: 1,
                      ),
                    ),
                  ),
                  child: BouncingTap(
                    onTap: () => Navigator.pop(ctx),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppTheme.primaryColor,
                          disabledForegroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 2,
                        ),
                        onPressed: null, // handled by BouncingTap
                        child: const Text(
                          'Close Inspector',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildModalRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white54 : Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.grey.shade900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    IconData icon,
    String label,
    String value,
    bool isDark, {
    bool isHighlight = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: isDark ? Colors.white54 : Colors.grey.shade600,
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white60 : Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isHighlight ? FontWeight.w700 : FontWeight.w600,
                color: valueColor ?? (isDark ? Colors.white : Colors.grey.shade900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTechnicalDetailsTile(List<dynamic> signatures, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurfaceVariant : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Theme(
        data: ThemeData(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            'Advanced Technical Information',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.grey.shade700,
            ),
          ),
          leading: Icon(
            Icons.code_rounded,
            size: 20,
            color: isDark ? Colors.white54 : Colors.grey.shade600,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: List.generate(signatures.length, (index) {
                  return SignatureCard(
                    signature: signatures[index] as Map<String, dynamic>,
                    index: index,
                    total: signatures.length,
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoSignaturesCard(BuildContext context, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark
            ? AppTheme.warningColor.withValues(alpha: 0.1)
            : AppTheme.warningColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.warningColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 48,
            color: AppTheme.warningColor,
          ),
          const SizedBox(height: 14),
          Text(
            'This PDF Has No Digital Signature',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'The uploaded document does not contain an electronic digital signature. '
            'It may be an unsigned file or a scanned copy.\n\n'
            'To view your PDF with an official green checkmark and "Signature valid", '
            'please upload a genuine digitally signed PDF (e.g. government certificates, '
            'e-District documents, or signed contracts).',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              color: isDark ? Colors.white70 : Colors.grey.shade700,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          BouncingTap(
            onTap: _pickAndVerifyNewPdf,
            child: ElevatedButton.icon(
              onPressed: null, // handled by BouncingTap
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.warningColor,
                foregroundColor: Colors.black,
                disabledForegroundColor: Colors.black,
                disabledBackgroundColor: AppTheme.warningColor,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 1,
              ),
              icon: const Icon(Icons.file_upload_outlined, size: 20),
              label: const Text(
                'Select Genuine Signed PDF',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorGuidanceCard(BuildContext context, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark
            ? AppTheme.invalidColor.withValues(alpha: 0.1)
            : AppTheme.invalidColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.invalidColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.broken_image_outlined,
            size: 48,
            color: AppTheme.invalidColor,
          ),
          const SizedBox(height: 14),
          Text(
            'Document Could Not Be Inspected',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'The verification engine could not read this PDF structure. '
            'Common reasons include:\n\n'
            '• The file is damaged, corrupted, or download was interrupted.\n'
            '• The document was created using a non-standard scanner or converter.\n'
            '• The file is an image or web page renamed to .pdf.\n\n'
            'Please download a fresh original copy of the PDF and try again.',
            textAlign: TextAlign.start,
            style: TextStyle(
              fontSize: 13.5,
              color: isDark ? Colors.white70 : Colors.grey.shade700,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          BouncingTap(
            onTap: _pickAndVerifyNewPdf,
            child: ElevatedButton.icon(
              onPressed: null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.invalidColor,
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white,
                disabledBackgroundColor: AppTheme.invalidColor,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.file_upload_outlined, size: 20),
              label: const Text(
                'Upload Another PDF',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openPdfViewer(BuildContext context, {bool preferVerified = true}) {
    final verifiedPath = result['verifiedPdfPath'] as String?;
    final cleanOriginalPath = result['originalCleanPdfPath'] as String?;
    final hasVerified = verifiedPath != null && File(verifiedPath).existsSync();
    final hasCleanOriginal = cleanOriginalPath != null && File(cleanOriginalPath).existsSync();
    final effectiveOriginalPath = (hasCleanOriginal ? cleanOriginalPath : null) ?? pdfPath;
    final String pathToShow = (preferVerified && hasVerified) ? verifiedPath : effectiveOriginalPath;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PdfViewerScreen(
          pdfPath: pathToShow,
          originalPdfPath: pdfPath,
          originalCleanPdfPath: cleanOriginalPath,
          verifiedPdfPath: hasVerified ? verifiedPath : null,
          fileName: fileName,
          verificationResult: result,
          password: widget.password,
          preferVerified: preferVerified,
        ),
      ),
    );
  }

  Future<void> _pickAndVerifyNewPdf() async {
    try {
      final pickerResult = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: false,
        withReadStream: false,
      );

      if (pickerResult != null && pickerResult.files.isNotEmpty) {
        final file = pickerResult.files.first;
        if (file.path == null) return;
        final fileUri = file.path!.startsWith('/')
            ? 'file://${file.path}'
            : 'file:///${file.path}';

        if (!mounted) return;
        AdService.isOperationInProgress = true;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Verifying digital signature...'),
                  ],
                ),
              ),
            ),
          ),
        );

        final verificationResult = await VerificationService.verifyPdf(fileUri);

        if (!mounted) return;
        Navigator.pop(context); // Close progress dialog

        var currentResult = verificationResult;
        String? enteredPassword;

        while (currentResult['status'] == 'PASSWORD_REQUIRED' && mounted) {
          final pwd = await _showPasswordDialog(errorMsg: currentResult['error'] as String?);
          if (pwd == null || !mounted) return;
          enteredPassword = pwd;
          currentResult = await VerificationService.verifyPdf(fileUri, password: pwd);
        }

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (ctx) => VerificationScreen(
                result: currentResult,
                pdfPath: file.path!,
                fileName: file.name,
                password: enteredPassword,
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(
          context,
          message: 'Error: $e',
          backgroundColor: AppTheme.invalidColor,
          duration: const Duration(seconds: 2),
        );
      }
    } finally {
      AdService.isOperationInProgress = false;
    }
  }

  String _getSimplifiedIssuer(Map<String, dynamic>? certInfo) {
    if (certInfo == null) return 'Authorized Certificate Authority';
    final issuer = certInfo['issuer'] as String? ?? '';
    final cnMatch = RegExp(r'CN=([^,]+)').firstMatch(issuer);
    if (cnMatch != null) {
      final name = cnMatch.group(1)?.trim();
      if (name != null && name.isNotEmpty) return name;
    }
    final oMatch = RegExp(r'O=([^,]+)').firstMatch(issuer);
    if (oMatch != null) {
      final name = oMatch.group(1)?.trim();
      if (name != null && name.isNotEmpty) return name;
    }
    return issuer.isNotEmpty ? issuer : 'Authorized Certificate Authority';
  }

  Future<void> _exportReport(BuildContext context) async {
    try {
      final reportPath = await ReportService.generateReport(result);
      if (context.mounted) {
        AppSnackBar.show(
          context,
          content: const Text('Report generated'),
          duration: const Duration(seconds: 2),
          action: SnackBarAction(
            label: 'Share',
            textColor: Colors.white,
            onPressed: () => ReportService.shareReport(reportPath),
          ),
        );
        await ReportService.shareReport(reportPath);
      }
    } catch (e) {
      if (context.mounted) {
        AppSnackBar.show(
          context,
          message: 'Error generating report: $e',
          backgroundColor: AppTheme.invalidColor,
          duration: const Duration(seconds: 2),
        );
      }
    }
  }

  Future<String?> _showPasswordDialog({String? errorMsg}) {
    if (!mounted) return Future.value(null);
    final passwordController = TextEditingController();
    bool obscurePassword = true;

    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.lock_rounded, color: AppTheme.primaryColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Password Required', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This PDF document is encrypted. Please enter the password to verify its digital signature.',
                    style: TextStyle(fontSize: 13.5, color: isDark ? Colors.white70 : Colors.grey.shade700),
                  ),
                  if (errorMsg != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              errorMsg,
                              style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      hintText: 'Enter PDF password',
                      prefixIcon: const Icon(Icons.key_rounded, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(obscurePassword ? Icons.visibility_off : Icons.visibility, size: 20),
                        onPressed: () => setDialogState(() => obscurePassword = !obscurePassword),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    onSubmitted: (pwd) {
                      if (pwd.trim().isNotEmpty) Navigator.pop(dialogCtx, pwd.trim());
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    final pwd = passwordController.text.trim();
                    if (pwd.isNotEmpty) Navigator.pop(dialogCtx, pwd);
                  },
                  child: const Text('Unlock & Verify'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

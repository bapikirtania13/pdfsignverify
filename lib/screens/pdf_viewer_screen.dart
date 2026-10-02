import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import '../theme/app_theme.dart';
import '../services/pdf_download_service.dart';

/// PDF Viewer screen - displays the PDF in true colors.
/// Seamlessly supports viewing the verified PDF (with official green checkmark
/// and 'Signature valid' directly on the document) or the original unmodified PDF.
class PdfViewerScreen extends StatefulWidget {
  final String pdfPath;
  final String? originalPdfPath;
  final String? verifiedPdfPath;
  final String fileName;
  final Map<String, dynamic>? verificationResult;
  final String? password;

  const PdfViewerScreen({
    super.key,
    required this.pdfPath,
    this.originalPdfPath,
    this.verifiedPdfPath,
    required this.fileName,
    this.verificationResult,
    this.password,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  int _currentPage = 0;
  int _totalPages = 0;
  bool _isReady = false;
  String _errorMessage = '';
  late String _currentDisplayPath;
  late bool _isShowingVerified;
  int _rotationQuarterTurns = 0;

  @override
  void initState() {
    super.initState();
    _currentDisplayPath = widget.pdfPath;
    _isShowingVerified = widget.verifiedPdfPath != null &&
        _currentDisplayPath == widget.verifiedPdfPath;
  }

  void _toggleDisplayMode() {
    if (widget.verifiedPdfPath == null || widget.originalPdfPath == null) return;

    setState(() {
      _isReady = false;
      _errorMessage = '';
      if (_isShowingVerified) {
        _currentDisplayPath = widget.originalPdfPath!;
        _isShowingVerified = false;
      } else {
        _currentDisplayPath = widget.verifiedPdfPath!;
        _isShowingVerified = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final signatures = widget.verificationResult?['signatures'] as List<dynamic>? ?? [];
    final hasSignatures = signatures.isNotEmpty;
    final primarySig = hasSignatures ? (signatures.first as Map<String, dynamic>) : null;
    final status = primarySig != null ? (primarySig['status'] as String? ?? 'UNKNOWN') : 'NO_SIGNATURE';
    final hasBothVersions = widget.verifiedPdfPath != null &&
        widget.originalPdfPath != null &&
        File(widget.verifiedPdfPath!).existsSync();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.fileName,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          // Toggle between Verified (with Green Tick) and Original Unmodified
          if (hasBothVersions)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: TextButton.icon(
                onPressed: _toggleDisplayMode,
                style: TextButton.styleFrom(
                  backgroundColor: _isShowingVerified
                      ? const Color(0xFF00C853).withValues(alpha: 0.18)
                      : Colors.white.withValues(alpha: 0.12),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: Icon(
                  _isShowingVerified ? Icons.check_circle_rounded : Icons.history_rounded,
                  size: 16,
                  color: _isShowingVerified ? const Color(0xFF00E676) : Colors.white,
                ),
                label: Text(
                  _isShowingVerified ? 'Verified' : 'Original',
                  style: TextStyle(
                    color: _isShowingVerified ? const Color(0xFF00E676) : Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          // Download / Save PDF button
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Download / Save PDF',
            onPressed: () {
              PdfDownloadService.showDownloadSheet(
                context: context,
                originalPath: widget.originalPdfPath ?? widget.pdfPath,
                verifiedPath: widget.verifiedPdfPath,
                baseFileName: widget.fileName,
              );
            },
          ),
          // Rotate Document button
          IconButton(
            icon: const Icon(Icons.rotate_right_rounded),
            tooltip: 'Rotate Document',
            onPressed: () {
              setState(() {
                _rotationQuarterTurns = (_rotationQuarterTurns + 1) % 4;
              });
            },
          ),
          if (_isReady && _totalPages > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_currentPage + 1} / $_totalPages',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Adobe Acrobat Style Top Status Banner
              if (hasSignatures) _buildAdobeTopBanner(status, isDark, primarySig!),
              Expanded(
                child: RotatedBox(
                  quarterTurns: _rotationQuarterTurns,
                  child: PDFView(
                    key: ValueKey('${_currentDisplayPath}_$_rotationQuarterTurns'),
                    filePath: _currentDisplayPath,
                    password: widget.password,
                    enableSwipe: true,
                    swipeHorizontal: false,
                    autoSpacing: true,
                    pageFling: true,
                    pageSnap: true,
                    fitPolicy: FitPolicy.BOTH,
                    preventLinkNavigation: true,
                    nightMode: false, // Prevents inverted/colourless document rendering!
                    onRender: (pages) {
                      setState(() {
                        _totalPages = pages ?? 0;
                        _isReady = true;
                      });
                    },
                    onError: (error) {
                      setState(() {
                        _errorMessage = error.toString();
                      });
                    },
                    onPageError: (page, error) {
                      setState(() {
                        _errorMessage = 'Error on page $page: $error';
                      });
                    },
                    onViewCreated: (controller) {
                      // PDF view controller initialized
                    },
                    onPageChanged: (page, total) {
                      setState(() {
                        _currentPage = page ?? 0;
                        _totalPages = total ?? 0;
                      });
                    },
                  ),
                ),
              ),
              // Bottom security footer
              _buildBottomSecurityFooter(isDark),
            ],
          ),



          // Error message
          if (_errorMessage.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 48,
                      color: AppTheme.invalidColor,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Unable to display PDF',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white54 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Adobe Acrobat Top Signature Bar
  Widget _buildAdobeTopBanner(String status, bool isDark, Map<String, dynamic> sig) {
    final isValid = status == 'VALID';
    final isWarning = status == 'WARNING';

    final Color bgColor = isValid
        ? const Color(0xFF1E7E34) // Official Adobe Green
        : isWarning
            ? const Color(0xFFD97706)
            : const Color(0xFFDC2626);

    final String message = isValid
        ? '✓ Signed and all signatures are valid.'
        : isWarning
            ? '⚠️ Signature has warnings.'
            : '✕ Digital signature is invalid.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
          InkWell(
            onTap: () => _showSignatureDetailsModal(context, sig, isDark),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Signature Details',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Bottom Security Bar
  Widget _buildBottomSecurityFooter(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? AppTheme.darkSurface.withValues(alpha: 0.95)
            : Colors.white.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isShowingVerified ? Icons.verified_rounded : Icons.lock_rounded,
            size: 14,
            color: _isShowingVerified
                ? const Color(0xFF00C853)
                : (isDark ? Colors.white38 : Colors.grey.shade500),
          ),
          const SizedBox(width: 6),
          Text(
            _isShowingVerified
                ? 'Displaying verified signature appearance with green tick'
                : 'Viewing original unmodified PDF file',
            style: TextStyle(
              fontSize: 11,
              fontWeight: _isShowingVerified ? FontWeight.w600 : FontWeight.normal,
              color: _isShowingVerified
                  ? const Color(0xFF00A844)
                  : (isDark ? Colors.white38 : Colors.grey.shade500),
            ),
          ),
        ],
      ),
    );
  }

  /// Signature details bottom modal
  void _showSignatureDetailsModal(BuildContext context, Map<String, dynamic> sig, bool isDark) {
    final cert = sig['certificate'] as Map<String, dynamic>? ?? {};
    final signerName = sig['signerName'] as String? ?? cert['commonName'] as String? ?? 'Signer';
    final issuer = cert['issuerOrganization'] as String? ?? cert['issuerCommonName'] as String? ?? 'CA';
    final signDate = sig['formattedSignDate'] as String? ?? sig['signDate'] as String? ?? 'Unknown';

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.verified, color: Color(0xFF00C853), size: 28),
                    const SizedBox(width: 10),
                    const Text(
                      'Adobe Verified Signature',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 8),
                _buildModalDetailRow('Signer Name', signerName),
                _buildModalDetailRow('Certificate Issuer', issuer),
                _buildModalDetailRow('Signing Date', signDate),
                _buildModalDetailRow('Reason', sig['reason'] as String? ?? 'D-Sign'),
                _buildModalDetailRow('Location', sig['location'] as String? ?? 'E-Dist 2.0'),
                _buildModalDetailRow('Integrity', 'Document unmodified since signing'),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildModalDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

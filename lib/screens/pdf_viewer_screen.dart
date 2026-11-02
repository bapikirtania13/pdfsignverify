import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import '../theme/app_theme.dart';
import '../services/pdf_download_service.dart';
import '../widgets/bouncing_tap.dart';

/// PDF Viewer screen - displays the PDF in true colors.
/// Seamlessly supports viewing the verified PDF (with official green checkmark
/// and 'Signature valid' directly on the document) or the original unmodified PDF.
class PdfViewerScreen extends StatefulWidget {
  final String pdfPath;
  final String? originalPdfPath;
  final String? originalCleanPdfPath;
  final String? verifiedPdfPath;
  final String fileName;
  final Map<String, dynamic>? verificationResult;
  final String? password;
  final bool preferVerified;

  const PdfViewerScreen({
    super.key,
    required this.pdfPath,
    this.originalPdfPath,
    this.originalCleanPdfPath,
    this.verifiedPdfPath,
    required this.fileName,
    this.verificationResult,
    this.password,
    this.preferVerified = true,
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
  final int _rotationQuarterTurns = 0;
  String? _activePassword;

  String get _unverifiedDisplayPath {
    if (widget.originalCleanPdfPath != null &&
        File(widget.originalCleanPdfPath!).existsSync()) {
      return widget.originalCleanPdfPath!;
    }
    return widget.originalPdfPath ?? widget.pdfPath;
  }

  @override
  void initState() {
    super.initState();
    _activePassword = widget.password;
    final status = widget.verificationResult?['status'] as String? ?? 'UNKNOWN';
    final isAllowedVerified = status == 'VALID' || status == 'WARNING';
    final hasVerified = isAllowedVerified &&
        widget.verifiedPdfPath != null &&
        File(widget.verifiedPdfPath!).existsSync();

    if (widget.preferVerified && hasVerified) {
      _currentDisplayPath = widget.verifiedPdfPath!;
      _isShowingVerified = true;
    } else {
      _currentDisplayPath = _unverifiedDisplayPath;
      _isShowingVerified = false;
    }
  }

  void _toggleDisplayMode() {
    final status = widget.verificationResult?['status'] as String? ?? 'UNKNOWN';
    final isAllowedVerified = status == 'VALID' || status == 'WARNING';
    final hasVerified = isAllowedVerified &&
        widget.verifiedPdfPath != null &&
        File(widget.verifiedPdfPath!).existsSync();

    if (!hasVerified) {
      return;
    }

    setState(() {
      _isReady = false;
      _errorMessage = '';
      if (_isShowingVerified) {
        _currentDisplayPath = _unverifiedDisplayPath;
        _isShowingVerified = false;
      } else {
        _currentDisplayPath = widget.verifiedPdfPath ?? widget.pdfPath;
        _isShowingVerified = true;
      }
    });
  }

  Future<void> _promptPasswordToUnlock() async {
    final controller = TextEditingController();
    bool obscure = true;

    final entered = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.lock_rounded, color: AppTheme.primaryColor),
              SizedBox(width: 8),
              Text('Unlock Document', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'This PDF is password-protected. Please enter the password to view it:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: obscure,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  suffixIcon: IconButton(
                    icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setDialogState(() => obscure = !obscure),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(dialogCtx, controller.text.trim()),
              child: const Text('Unlock'),
            ),
          ],
        ),
      ),
    );

    if (entered != null && entered.isNotEmpty) {
      setState(() {
        _activePassword = entered;
        _errorMessage = '';
        _isReady = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final signatures = widget.verificationResult?['signatures'] as List<dynamic>? ?? [];
    final hasSignatures = signatures.isNotEmpty;
    final primarySig = hasSignatures ? (signatures.first as Map<String, dynamic>) : null;
    final status = primarySig != null ? (primarySig['status'] as String? ?? 'UNKNOWN') : 'NO_SIGNATURE';
    final hasBothVersions = widget.verifiedPdfPath != null &&
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
              child: BouncingTap(
                onTap: _toggleDisplayMode,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isShowingVerified
                        ? const Color(0xFF00C853).withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isShowingVerified ? Icons.check_circle_rounded : Icons.history_rounded,
                        size: 16,
                        color: _isShowingVerified ? const Color(0xFF00E676) : Colors.white,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _isShowingVerified ? 'Verified' : 'Original',
                        style: TextStyle(
                          color: _isShowingVerified ? const Color(0xFF00E676) : Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Download / Save PDF button
          BouncingTap(
            onTap: () {
              PdfDownloadService.showDownloadSheet(
                context: context,
                originalPath: widget.originalCleanPdfPath ?? widget.originalPdfPath ?? widget.pdfPath,
                verifiedPath: widget.verifiedPdfPath,
                baseFileName: widget.fileName,
              );
            },
            child: const IconButton(
              icon: Icon(Icons.download_rounded),
              tooltip: 'Download / Save PDF',
              onPressed: null, // handled by BouncingTap
            ),
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
              // Standard Verification Top Status Banner
              if (hasSignatures) _buildVerificationTopBanner(status, isDark, primarySig!),
              Expanded(
                child: RotatedBox(
                  quarterTurns: _rotationQuarterTurns,
                  child: PDFView(
                    key: ValueKey('${_currentDisplayPath}_${_rotationQuarterTurns}_$_activePassword'),
                    filePath: _currentDisplayPath,
                    password: _activePassword,
                    enableSwipe: true,
                    swipeHorizontal: false,
                    autoSpacing: false,
                    pageFling: false,
                    pageSnap: false,
                    fitPolicy: FitPolicy.WIDTH,
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
                      _errorMessage.toLowerCase().contains('password')
                          ? Icons.lock_clock_rounded
                          : Icons.error_outline_rounded,
                      size: 48,
                      color: _errorMessage.toLowerCase().contains('password')
                          ? AppTheme.warningColor
                          : AppTheme.invalidColor,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage.toLowerCase().contains('password')
                          ? 'Password Protected PDF'
                          : 'Unable to display PDF',
                      style: const TextStyle(
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
                    const SizedBox(height: 18),
                    BouncingTap(
                      onTap: _promptPasswordToUnlock,
                      child: ElevatedButton.icon(
                        onPressed: _promptPasswordToUnlock,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.key_rounded, size: 18),
                        label: const Text('Enter Password to Unlock'),
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

  /// Standard Top Signature Status Bar
  Widget _buildVerificationTopBanner(String status, bool isDark, Map<String, dynamic> sig) {
    final isValid = status == 'VALID';
    final isWarning = status == 'WARNING';

    final Color bgColor = isValid
        ? const Color(0xFF1E7E34) // Standard Verified Green
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
          BouncingTap(
            onTap: () => _showSignatureDetailsModal(context, sig, isDark),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(6),
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
    final status = widget.verificationResult?['status'] as String? ?? 'UNKNOWN';
    final isDocInvalid = status == 'INVALID' || status == 'ERROR';

    final IconData footerIcon;
    final Color footerColor;
    final String footerText;

    if (isDocInvalid) {
      footerIcon = Icons.cancel_outlined;
      footerColor = AppTheme.invalidColor;
      footerText = 'Viewing unverified document (Digital signature is invalid)';
    } else if (_isShowingVerified) {
      footerIcon = Icons.verified_rounded;
      footerColor = const Color(0xFF00C853);
      footerText = 'Displaying verified signature appearance with green tick';
    } else {
      footerIcon = Icons.lock_rounded;
      footerColor = isDark ? Colors.white38 : Colors.grey.shade500;
      footerText = 'Viewing original unmodified PDF file';
    }

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
            footerIcon,
            size: 14,
            color: footerColor,
          ),
          const SizedBox(width: 6),
          Text(
            footerText,
            style: TextStyle(
              fontSize: 11,
              fontWeight: (_isShowingVerified || isDocInvalid) ? FontWeight.w600 : FontWeight.normal,
              color: footerColor,
            ),
          ),
        ],
      ),
    );
  }

  /// Signature details bottom modal
  void _showSignatureDetailsModal(BuildContext context, Map<String, dynamic> sig, bool isDark) {
    final overallStatus = widget.verificationResult?['status'] as String? ?? 'UNKNOWN';
    final sigStatus = sig['status'] as String? ?? overallStatus;
    final sigIntegrity = sig['signatureIntegrity'] as bool? ?? false;
    final docIntegrity = sig['documentIntegrity'] as bool? ?? false;

    final isSigValid = sigStatus == 'VALID' && overallStatus == 'VALID';
    final isSigWarning = (sigStatus == 'WARNING' || overallStatus == 'WARNING') && !isSigValid && sigIntegrity && docIntegrity;
    final isSigInvalid = !isSigValid && !isSigWarning;

    final IconData modalIcon = isSigValid
        ? Icons.verified
        : isSigWarning
            ? Icons.warning_amber_rounded
            : Icons.cancel_rounded;

    final Color modalColor = isSigValid
        ? const Color(0xFF00C853)
        : isSigWarning
            ? AppTheme.warningColor
            : AppTheme.invalidColor;

    final String modalTitle = isSigValid
        ? 'Verified Digital Signature'
        : isSigWarning
            ? 'Digital Signature Warning'
            : 'Invalid Digital Signature';

    final String integrityText = !docIntegrity
        ? 'Document modified after signing'
        : !sigIntegrity
            ? 'Cryptographic verification failed'
            : isSigValid
                ? 'Document unmodified since signing'
                : 'Document intact with warnings';

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
                    Icon(modalIcon, color: modalColor, size: 28),
                    const SizedBox(width: 10),
                    Text(
                      modalTitle,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: modalColor),
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
                _buildModalDetailRow('Status', isSigValid ? 'VALID' : (isSigWarning ? 'WARNING' : 'INVALID'), valueColor: modalColor),
                _buildModalDetailRow('Signer Name', signerName),
                _buildModalDetailRow('Certificate Issuer', issuer),
                _buildModalDetailRow('Signing Date', signDate),
                if (sig['reason'] != null && sig['reason'].toString().isNotEmpty && sig['reason'].toString().toLowerCase() != 'null')
                  _buildModalDetailRow('Reason', sig['reason'].toString()),
                if (sig['location'] != null && sig['location'].toString().isNotEmpty && sig['location'].toString().toLowerCase() != 'null')
                  _buildModalDetailRow('Location', sig['location'].toString()),
                _buildModalDetailRow('Integrity', integrityText, valueColor: isSigInvalid ? AppTheme.invalidColor : (isSigValid ? const Color(0xFF008A2A) : AppTheme.warningColor)),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildModalDetailRow(String label, String value, {Color? valueColor}) {
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
              style: TextStyle(
                fontWeight: valueColor != null ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

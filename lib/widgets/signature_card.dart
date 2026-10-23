import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A card widget that displays detailed verification results for a single signature.
/// Uses colors AND text/icons so users don't depend only on color.
class SignatureCard extends StatefulWidget {
  final Map<String, dynamic> signature;
  final int index;
  final int total;

  const SignatureCard({
    super.key,
    required this.signature,
    required this.index,
    required this.total,
  });

  @override
  State<SignatureCard> createState() => _SignatureCardState();
}

class _SignatureCardState extends State<SignatureCard> {
  bool _isCertExpanded = false;
  bool _isChainExpanded = false;
  bool _isDetailsExpanded = true;

  @override
  Widget build(BuildContext context) {
    final sig = widget.signature;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = sig['status'] as String? ?? 'UNKNOWN';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurfaceVariant : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _getStatusColor(status).withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          _buildHeader(sig, status, isDark),

          // Official Adobe-style Signature Stamp (as requested)
          _buildAdobeSignatureStamp(sig, status, isDark),

          // Verification checks
          _buildVerificationChecks(sig, isDark),

          // Certificate info (expandable)
          _buildCertificateSection(sig, isDark),

          // Certificate chain (expandable)
          _buildChainSection(sig, isDark),

          // Additional details
          _buildAdditionalDetails(sig, isDark),
        ],
      ),
    );
  }

  Widget _buildHeader(Map<String, dynamic> sig, String status, bool isDark) {
    final sigName = sig['signatureName'] as String? ?? 'Signature';
    final revision = sig['revision'];
    final totalRevisions = sig['totalRevisions'];
    final coversWhole = sig['coversWholeDocument'] as bool? ?? false;
    final signDate = sig['signDate'] as String?;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _getStatusColor(status).withValues(alpha: isDark ? 0.12 : 0.06),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildStatusIcon(status, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Signature ${widget.index + 1} of ${widget.total}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.grey.shade800,
                      ),
                    ),
                    if (sigName.isNotEmpty)
                      Text(
                        sigName,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.grey.shade500,
                        ),
                      ),
                  ],
                ),
              ),
              _buildStatusBadge(status),
            ],
          ),
          if (revision != null || signDate != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                if (revision != null)
                  _buildTag(
                    'Rev $revision/$totalRevisions',
                    Icons.layers_rounded,
                    isDark,
                  ),
                if (coversWhole)
                  _buildTag(
                    'Full Document',
                    Icons.check_circle_outline_rounded,
                    isDark,
                  )
                else
                  _buildTag(
                    'Partial Coverage',
                    Icons.warning_amber_rounded,
                    isDark,
                    color: AppTheme.warningColor,
                  ),
                if (signDate != null)
                  _buildTag(
                    _formatDate(signDate),
                    Icons.schedule_rounded,
                    isDark,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVerificationChecks(Map<String, dynamic> sig, bool isDark) {
    return InkWell(
      onTap: () => setState(() => _isDetailsExpanded = !_isDetailsExpanded),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Verification Checks',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.grey.shade700,
                  ),
                ),
                const Spacer(),
                Icon(
                  _isDetailsExpanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 20,
                  color: isDark ? Colors.white54 : Colors.grey.shade400,
                ),
              ],
            ),
            if (_isDetailsExpanded) ...[
              const SizedBox(height: 12),
              _buildCheckRow(
                'Signature Integrity',
                sig['signatureIntegrityStatus'] as String? ?? 'UNKNOWN',
                'CMS/PKCS#7 cryptographic verification',
                isDark,
              ),
              _buildCheckRow(
                'Document Integrity',
                sig['documentIntegrityStatus'] as String? ?? 'UNKNOWN',
                'ByteRange and hash verification',
                isDark,
              ),
              _buildCheckRow(
                'Certificate Valid',
                sig['certificateValidStatus'] as String? ?? 'UNKNOWN',
                sig['certificateValidMessage'] as String? ?? '',
                isDark,
              ),
              _buildCheckRow(
                'Certificate Trust',
                sig['trustStatus'] as String? ?? 'UNKNOWN',
                sig['trustMessage'] as String? ?? '',
                isDark,
              ),
              _buildCheckRow(
                'Revocation Status',
                sig['revocationStatus'] as String? ?? 'UNKNOWN',
                sig['revocationMessage'] as String? ?? '',
                isDark,
              ),
              _buildCheckRow(
                'Timestamp',
                sig['timestampStatus'] as String? ?? 'UNKNOWN',
                sig['timestampMessage'] as String? ?? '',
                isDark,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCheckRow(
    String label,
    String status,
    String detail,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatusIcon(status, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : Colors.grey.shade800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _getStatusLabel(status),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _getStatusColor(status),
                      ),
                    ),
                  ],
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white38 : Colors.grey.shade500,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCertificateSection(Map<String, dynamic> sig, bool isDark) {
    final cert = sig['certificate'] as Map<String, dynamic>?;
    if (cert == null) return const SizedBox.shrink();

    return Column(
      children: [
        Divider(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          height: 1,
        ),
        InkWell(
          onTap: () => setState(() => _isCertExpanded = !_isCertExpanded),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.badge_rounded,
                      size: 18,
                      color: isDark ? Colors.white60 : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Signer Certificate',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.grey.shade700,
                            ),
                          ),
                          Text(
                            cert['commonName'] as String? ?? 'Unknown Signer',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white54 : Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _isCertExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 20,
                      color: isDark ? Colors.white54 : Colors.grey.shade400,
                    ),
                  ],
                ),
                if (_isCertExpanded) ...[
                  const SizedBox(height: 12),
                  _certRow('Common Name', cert['commonName'], isDark),
                  _certRow('Organization', cert['organization'], isDark),
                  _certRow('Org Unit', cert['organizationalUnit'], isDark),
                  _certRow('Country', cert['country'], isDark),
                  _certRow('Email', cert['email'], isDark),
                  _certRow('Serial Number', cert['serialNumber'], isDark),
                  _certRow('Valid From', _formatDate(cert['validFrom'] as String?), isDark),
                  _certRow('Valid To', _formatDate(cert['validTo'] as String?), isDark),
                  _certRow('Currently Valid', cert['currentlyValid'] == true ? '✓ Yes' : '✗ No', isDark),
                  _certRow('Issuer CN', cert['issuerCommonName'], isDark),
                  _certRow('Issuer Org', cert['issuerOrganization'], isDark),
                  _certRow('Sig Algorithm', cert['signatureAlgorithm'], isDark),
                  _certRow('Is CA', cert['isCA'] == true ? 'Yes' : 'No', isDark),
                  const SizedBox(height: 8),
                  Text(
                    'SHA-256 Fingerprint',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white54 : Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.3)
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      cert['sha256Fingerprint'] as String? ?? 'N/A',
                      style: TextStyle(
                        fontSize: 9,
                        fontFamily: 'monospace',
                        color: isDark ? Colors.white54 : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChainSection(Map<String, dynamic> sig, bool isDark) {
    final chain = sig['certificateChain'] as List<dynamic>? ?? [];
    if (chain.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        Divider(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          height: 1,
        ),
        InkWell(
          onTap: () => setState(() => _isChainExpanded = !_isChainExpanded),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.link_rounded,
                      size: 18,
                      color: isDark ? Colors.white60 : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Certificate Chain (${chain.length})',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.grey.shade700,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _isChainExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 20,
                      color: isDark ? Colors.white54 : Colors.grey.shade400,
                    ),
                  ],
                ),
                if (_isChainExpanded) ...[
                  const SizedBox(height: 12),
                  ...List.generate(chain.length, (i) {
                    final cert = chain[i] as Map<String, dynamic>;
                    return _buildChainCertCard(cert, i, chain.length, isDark);
                  }),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChainCertCard(
    Map<String, dynamic> cert,
    int index,
    int total,
    bool isDark,
  ) {
    return Container(
      margin: EdgeInsets.only(left: index * 12.0, bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withValues(alpha: 0.2)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                index == 0
                    ? Icons.person_rounded
                    : index == total - 1
                        ? Icons.verified_rounded
                        : Icons.account_tree_rounded,
                size: 16,
                color: isDark ? Colors.white60 : Colors.grey.shade600,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  cert['commonName'] as String? ?? 'Unknown',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.grey.shade800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (cert['isCA'] == true)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppTheme.infoColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'CA',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.infoColor,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            cert['organization'] as String? ?? '',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white38 : Colors.grey.shade500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildAdditionalDetails(Map<String, dynamic> sig, bool isDark) {
    final digestAlg = sig['digestAlgorithm'] as String?;
    final sigAlg = sig['signatureAlgorithm'] as String?;
    final encAlg = sig['digestEncryptionAlgorithm'] as String?;
    final revMethod = sig['revocationMethod'] as String?;
    final timestampDate = sig['timestampDate'] as String?;

    return Column(
      children: [
        Divider(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          height: 1,
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Technical Details',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              if (digestAlg != null)
                _certRow('Digest Algorithm', digestAlg, isDark),
              if (sigAlg != null)
                _certRow('Signature Algorithm', sigAlg, isDark),
              if (encAlg != null)
                _certRow('Encryption Algorithm', encAlg, isDark),
              if (revMethod != null)
                _certRow('Revocation Method', revMethod, isDark),
              if (timestampDate != null)
                _certRow('Timestamp Date', _formatDate(timestampDate), isDark),
              if (sig['error'] != null)
                _certRow('Error', sig['error'] as String, isDark),
            ],
          ),
        ),
      ],
    );
  }

  Widget _certRow(String label, dynamic value, bool isDark) {
    final displayValue = value?.toString() ?? 'N/A';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.grey.shade500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              displayValue,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white70 : Colors.grey.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTag(String text, IconData icon, bool isDark, {Color? color}) {
    final tagColor = color ?? (isDark ? Colors.white60 : Colors.grey.shade600);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tagColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: tagColor),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: tagColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(String status, {double size = 20}) {
    final color = _getStatusColor(status);
    IconData icon;

    switch (status.toUpperCase()) {
      case 'VALID':
      case 'TRUSTED':
      case 'NOT_REVOKED':
        icon = Icons.check_circle_rounded;
        break;
      case 'INVALID':
      case 'REVOKED':
      case 'EXPIRED':
        icon = Icons.cancel_rounded;
        break;
      case 'WARNING':
      case 'UNTRUSTED':
        icon = Icons.warning_rounded;
        break;
      case 'NOT_PRESENT':
        icon = Icons.remove_circle_outline_rounded;
        break;
      case 'NOT_YET_VALID':
        icon = Icons.schedule_rounded;
        break;
      default:
        icon = Icons.help_rounded;
    }

    return Icon(icon, size: size, color: color);
  }

  Widget _buildStatusBadge(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _getStatusColor(status).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _getStatusLabel(status),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: _getStatusColor(status),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'VALID':
      case 'TRUSTED':
      case 'NOT_REVOKED':
        return AppTheme.validColor;
      case 'INVALID':
      case 'REVOKED':
      case 'EXPIRED':
        return AppTheme.invalidColor;
      case 'WARNING':
      case 'UNTRUSTED':
        return AppTheme.warningColor;
      case 'NOT_PRESENT':
        return AppTheme.unknownColor;
      default:
        return AppTheme.unknownColor;
    }
  }

  String _getStatusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'VALID':
        return '✓ VALID';
      case 'INVALID':
        return '✗ INVALID';
      case 'TRUSTED':
        return '✓ TRUSTED';
      case 'UNTRUSTED':
        return '⚠ UNTRUSTED';
      case 'NOT_REVOKED':
        return '✓ NOT REVOKED';
      case 'REVOKED':
        return '✗ REVOKED';
      case 'EXPIRED':
        return '✗ EXPIRED';
      case 'NOT_YET_VALID':
        return '⚠ NOT YET VALID';
      case 'WARNING':
        return '⚠ WARNING';
      case 'NOT_PRESENT':
        return '— NOT PRESENT';
      case 'ERROR':
        return '✗ ERROR';
      default:
        return '? UNKNOWN';
    }
  }

  Widget _buildAdobeSignatureStamp(Map<String, dynamic> sig, String status, bool isDark) {
    final cert = sig['certificate'] as Map<String, dynamic>? ?? {};
    final docSignerName = sig['documentSignerName'] as String?;
    final signerName = docSignerName ??
        sig['signerName'] as String? ??
        cert['commonName'] as String? ??
        'Signer';
    final signDate = sig['formattedSignDate'] as String? ??
        _formatDate(sig['signDate'] as String?);
    final reason = sig['reason'] as String? ?? '';
    final location = sig['location'] as String? ?? '';
    final originalLines = (sig['originalTextLines'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .toList();

    final sigIntegrity = sig['signatureIntegrity'] as bool? ?? false;
    final docIntegrity = sig['documentIntegrity'] as bool? ?? false;
    final isValid = status == 'VALID' || (sigIntegrity && docIntegrity && status != 'INVALID');
    final isWarning = status == 'WARNING' && !isValid;
    final isInvalid = status == 'INVALID';

    final Color primaryColor = isValid
        ? const Color(0xFF007A3D) // Adobe Official Green
        : isWarning
            ? const Color(0xFFC87000)
            : const Color(0xFFD32F2F);

    final String statusText = isValid
        ? 'Signature Valid'
        : isWarning
            ? 'Signature has warnings'
            : isInvalid
                ? 'Signature invalid'
                : 'Signature Not Verified';

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E242B) : const Color(0xFFF9FBF9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Background subtle check watermark
          Positioned(
            right: 0,
            bottom: -8,
            child: Opacity(
              opacity: 0.08,
              child: Icon(
                isValid ? Icons.check : Icons.close,
                size: 70,
                color: primaryColor,
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Checkmark / status badge icon
              Container(
                margin: const EdgeInsets.only(top: 2),
                child: isValid
                    ? Image.asset(
                        'assets/images/adobe_green_tick.png',
                        width: 32,
                        height: 32,
                        fit: BoxFit.contain,
                      )
                    : Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isWarning
                              ? Icons.warning_amber_rounded
                              : Icons.close_rounded,
                          color: primaryColor,
                          size: 24,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              // Adobe signature details block matching Image 3
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: primaryColor,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (originalLines != null && originalLines.isNotEmpty) ...[
                      for (final line in originalLines)
                        Text(
                          line,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white70 : Colors.black87,
                            height: 1.35,
                            fontFamily: 'monospace',
                            fontWeight: (line.toLowerCase().startsWith('name:') || line.toLowerCase().contains('digitally signed'))
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                    ] else ...[
                      RichText(
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark ? Colors.white70 : Colors.black87,
                            height: 1.35,
                            fontFamily: 'monospace',
                          ),
                          children: [
                            const TextSpan(text: 'Digitally signed by '),
                            TextSpan(
                              text: signerName,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                      if (signDate.isNotEmpty && signDate != 'N/A')
                        Text(
                          'Date: $signDate',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black54,
                            height: 1.35,
                            fontFamily: 'monospace',
                          ),
                        ),
                      if (reason.isNotEmpty)
                        Text(
                          'Reason: $reason',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black54,
                            height: 1.35,
                            fontFamily: 'monospace',
                          ),
                        ),
                      if (location.isNotEmpty)
                        Text(
                          'Location: $location',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black54,
                            height: 1.35,
                            fontFamily: 'monospace',
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return 'N/A';
    try {
      final date = DateTime.parse(isoDate);
      return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return isoDate;
    }
  }
}

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:animate_do/animate_do.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/verification_service.dart';
import '../services/history_service.dart';
import '../services/ad_service.dart';
import '../widgets/app_banner_ad_widget.dart';
import '../widgets/app_native_ad_widget.dart';
import '../widgets/bouncing_tap.dart';
import '../widgets/app_snack_bar.dart';
import 'verification_screen.dart';

class BatchPdfItem {
  final String path;
  final String name;
  final int size;
  String status; // 'PENDING', 'VERIFYING', 'VALID', 'INVALID', 'NO_SIGNATURES', 'SKIPPED', 'ERROR'
  String? errorMessage;
  Map<String, dynamic>? result;
  String? password;

  BatchPdfItem({
    required this.path,
    required this.name,
    required this.size,
    this.status = 'PENDING',
    this.errorMessage,
    this.result,
    this.password,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  String? _selectedFilePath;
  String? _selectedFileUri;
  String? _selectedFileName;
  int? _selectedFileSize;
  bool _isVerifying = false;

  List<BatchPdfItem> _batchItems = [];
  List<HistoryItem> _historyItems = [];

  late AnimationController _animController;
  late Animation<double> _logoFadeAnim;
  late Animation<Offset> _logoSlideAnim;
  late Animation<double> _headerFadeAnim;
  late Animation<Offset> _headerSlideAnim;
  late Animation<double> _buttonFadeAnim;
  late Animation<Offset> _buttonSlideAnim;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _initAnimations();
  }

  void _initAnimations() {
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    // Staggered silky smooth curves using Interval
    _logoFadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );
    _logoSlideAnim = Tween<Offset>(
      begin: const Offset(0.0, -0.25),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOutCubic),
      ),
    );

    _headerFadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.2, 0.75, curve: Curves.easeOut),
      ),
    );
    _headerSlideAnim = Tween<Offset>(
      begin: const Offset(0.0, 0.2),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.2, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    _buttonFadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.35, 0.9, curve: Curves.easeOut),
      ),
    );
    _buttonSlideAnim = Tween<Offset>(
      begin: const Offset(0.0, 0.25),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.35, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final items = await HistoryService.getHistory();
    if (mounted) {
      setState(() => _historyItems = items);
    }
  }

  Future<void> _pickPdf() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: true,
        withData: false,
        withReadStream: false,
      );

      if (result != null && result.files.isNotEmpty) {
        if (result.files.length == 1) {
          final file = result.files.first;
          setState(() {
            _batchItems.clear();
            _selectedFilePath = file.path;
            _selectedFileUri = file.path != null ? 'file://${file.path}' : null;
            _selectedFileName = file.name;
            _selectedFileSize = file.size;
          });
        } else {
          // Multiple PDFs selected - maximum 3 PDFs allowed
          final wasOverLimit = result.files.length > 3;
          final selectedFiles = result.files
              .where((f) => f.path != null)
              .take(3)
              .toList();

          setState(() {
            _selectedFilePath = null;
            _selectedFileUri = null;
            _selectedFileName = null;
            _selectedFileSize = null;
            _batchItems = selectedFiles
                .map((f) => BatchPdfItem(name: f.name, path: f.path!, size: f.size))
                .toList();
          });

          if (wasOverLimit && mounted) {
            AppSnackBar.show(
              context,
              message: 'Maximum 3 PDFs allowed at once. Selected the first 3 PDFs.',
              duration: const Duration(seconds: 3),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(
          context,
          message: 'Error selecting file: $e',
          backgroundColor: AppTheme.invalidColor,
          duration: const Duration(seconds: 2),
        );
      }
    }
  }

  Future<void> _verifySignature({String? password}) async {
    if (_selectedFilePath == null) return;

    setState(() => _isVerifying = true);
    AdService.isOperationInProgress = true;

    try {
      final actualUri = _selectedFileUri ??
          (_selectedFilePath!.startsWith('/')
              ? 'file://$_selectedFilePath'
              : 'file:///$_selectedFilePath');

      final verificationResult = await VerificationService.verifyPdf(
        actualUri,
        password: password,
      );

      if (!mounted) return;

      if (verificationResult['status'] == 'PASSWORD_REQUIRED') {
        setState(() => _isVerifying = false);
        _promptForPassword(
          isRetry: password != null,
          errorMsg: verificationResult['error'] as String?,
        );
        return;
      }

      // Record in History
      final sigs = verificationResult['signatures'] as List<dynamic>? ?? [];
      String? signer;
      if (sigs.isNotEmpty) {
        final firstSig = sigs.first as Map<String, dynamic>;
        signer = firstSig['documentSignerName'] as String? ?? firstSig['signerName'] as String?;
      }
      await HistoryService.addItem(HistoryItem(
        fileName: _selectedFileName ?? 'Document.pdf',
        filePath: _selectedFilePath!,
        status: verificationResult['status'] as String? ?? 'UNKNOWN',
        signerName: signer,
        timestamp: DateTime.now(),
        result: verificationResult,
      ));
      _loadHistory();

      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => VerificationScreen(
            result: verificationResult,
            pdfPath: _selectedFilePath!,
            fileName: _selectedFileName ?? 'Unknown',
            password: password,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(
          context,
          message: 'Verification error: $e',
          backgroundColor: AppTheme.invalidColor,
          duration: const Duration(seconds: 2),
        );
      }
    } finally {
      AdService.isOperationInProgress = false;
      if (mounted) {
        setState(() => _isVerifying = false);
      }
    }
  }

  Future<void> _verifyBatch() async {
    if (_batchItems.isEmpty) return;
    setState(() => _isVerifying = true);
    AdService.isOperationInProgress = true;

    try {
      for (int i = 0; i < _batchItems.length; i++) {
        final item = _batchItems[i];
        if (item.status == 'VALID' || item.status == 'INVALID' || item.status == 'NO_SIGNATURES') {
          continue; // Already verified
        }

        setState(() {
          item.status = 'VERIFYING';
        });

        final actualUri = item.path.startsWith('/') ? 'file://${item.path}' : 'file:///${item.path}';
        var res = await VerificationService.verifyPdf(actualUri, password: item.password);

        // Handle Password Protected PDF in Batch
        if (res['status'] == 'PASSWORD_REQUIRED' && mounted) {
          final enteredPwd = await _promptPasswordForBatchItem(item);
          if (enteredPwd == null) {
            // User chose to skip this specific PDF
            setState(() {
              item.status = 'SKIPPED';
              item.errorMessage = 'Password skipped';
            });
            continue; // Continue seamlessly with next PDF in batch!
          } else {
            item.password = enteredPwd;
            res = await VerificationService.verifyPdf(actualUri, password: enteredPwd);
          }
        }

        final resStatus = res['status'] as String? ?? 'ERROR';
        setState(() {
          item.result = res;
          item.status = resStatus;
          if (resStatus == 'ERROR') {
            item.errorMessage = res['error'] as String? ?? 'Verification failed';
          }
        });

        // Add to history
        if (item.status != 'SKIPPED') {
          final sigs = res['signatures'] as List<dynamic>? ?? [];
          String? signer;
          if (sigs.isNotEmpty) {
            final firstSig = sigs.first as Map<String, dynamic>;
            signer = firstSig['documentSignerName'] as String? ?? firstSig['signerName'] as String?;
          }
          await HistoryService.addItem(HistoryItem(
            fileName: item.name,
            filePath: item.path,
            status: item.status,
            signerName: signer,
            timestamp: DateTime.now(),
            result: res,
          ));
        }
      }
      _loadHistory();
    } catch (e) {
      debugPrint('[HomeScreen] Batch error: $e');
    } finally {
      AdService.isOperationInProgress = false;
      if (mounted) {
        setState(() => _isVerifying = false);
      }
    }
  }

  Future<String?> _promptPasswordForBatchItem(BatchPdfItem item) async {
    final passwordController = TextEditingController();
    bool obscurePassword = true;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.warningColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.lock_rounded,
                      color: AppTheme.warningColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Password Protected',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkSurfaceVariant : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.picture_as_pdf_rounded, size: 20, color: Colors.redAccent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'This file is encrypted. Enter its password or skip this file to continue verifying the rest of the batch.',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white70 : Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      hintText: 'Enter password for this PDF',
                      prefixIcon: const Icon(Icons.key_rounded, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePassword ? Icons.visibility_off : Icons.visibility,
                          size: 20,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            obscurePassword = !obscurePassword;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    onSubmitted: (pwd) {
                      if (pwd.trim().isNotEmpty) {
                        Navigator.pop(dialogCtx, pwd.trim());
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx, null),
                  child: const Text('Skip This PDF'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    final pwd = passwordController.text.trim();
                    if (pwd.isNotEmpty) {
                      Navigator.pop(dialogCtx, pwd);
                    } else {
                      Navigator.pop(dialogCtx, null);
                    }
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

  void _promptForPassword({bool isRetry = false, String? errorMsg}) {
    final passwordController = TextEditingController();
    bool obscurePassword = true;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.lock_rounded,
                      color: AppTheme.primaryColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Password Required',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This PDF document is encrypted. Please enter the password to verify its digital signature.',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: isDark ? Colors.white70 : Colors.grey.shade700,
                    ),
                  ),
                  if (isRetry && errorMsg != null) ...[
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
                        icon: Icon(
                          obscurePassword ? Icons.visibility_off : Icons.visibility,
                          size: 20,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            obscurePassword = !obscurePassword;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    onSubmitted: (pwd) {
                      if (pwd.trim().isNotEmpty) {
                        Navigator.pop(dialogCtx);
                        _verifySignature(password: pwd.trim());
                      }
                    },
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    final pwd = passwordController.text.trim();
                    if (pwd.isNotEmpty) {
                      Navigator.pop(dialogCtx);
                      _verifySignature(password: pwd);
                    }
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Sign Verify'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            tooltip: 'About',
            onPressed: _showAboutDialog,
          ),
        ],
      ),
      bottomNavigationBar: const AppBannerAdWidget(
        adUnitId: AdService.homeBannerId,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header gradient
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDark
                      ? [
                          AppTheme.darkSurface,
                          AppTheme.darkBackground,
                        ]
                      : [
                          AppTheme.primaryColor.withValues(alpha: 0.08),
                          AppTheme.lightBackground,
                        ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                child: Column(
                  children: [
                    FadeTransition(
                      opacity: _logoFadeAnim,
                      child: SlideTransition(
                        position: _logoSlideAnim,
                        child: _buildLogoSection(isDark),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FadeTransition(
                      opacity: _headerFadeAnim,
                      child: SlideTransition(
                        position: _headerSlideAnim,
                        child: Column(
                          children: [
                            Text(
                              'Verify PDF Digital Signature',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : AppTheme.primaryColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Upload a PDF document to verify its digital signature',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? Colors.white60
                                    : Colors.grey.shade600,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  const SizedBox(height: 24),

                  // Select PDF button
                  FadeTransition(
                    opacity: _buttonFadeAnim,
                    child: SlideTransition(
                      position: _buttonSlideAnim,
                      child: _buildSelectPdfSection(isDark, colorScheme),
                    ),
                  ),

                  // If multiple files selected: Batch Section
                  if (_batchItems.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    _buildBatchSection(isDark, colorScheme),
                  ],

                  // Selected single file info
                  if (_selectedFilePath != null) ...[
                    const SizedBox(height: 16),
                    FadeInUp(
                      duration: const Duration(milliseconds: 400),
                      child: _buildFileInfoCard(isDark),
                    ),
                    const SizedBox(height: 20),
                    FadeInUp(
                      duration: const Duration(milliseconds: 400),
                      child: _buildVerifyButton(colorScheme),
                    ),
                  ],

                  // Verification History Section
                  if (_historyItems.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildHistorySection(isDark),
                  ],

                  // Native Ad on Home Page
                  const SizedBox(height: 20),
                  const AppNativeAdWidget(
                    adUnitId: AdService.nativeAdId,
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatchSection(bool isDark, ColorScheme colorScheme) {
    final pendingCount = _batchItems.where((i) => i.status == 'PENDING').length;
    final verifyingCount = _batchItems.where((i) => i.status == 'VERIFYING').length;
    final validCount = _batchItems.where((i) => i.status == 'VALID').length;
    final skippedCount = _batchItems.where((i) => i.status == 'SKIPPED').length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurfaceVariant : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
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
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.folder_zip_rounded, color: AppTheme.primaryColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Batch Queue (${_batchItems.length} PDFs)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Text(
                      _isVerifying
                          ? 'Verifying files...'
                          : '$validCount Valid • $skippedCount Skipped • $pendingCount Pending',
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _isVerifying
                    ? null
                    : () {
                        setState(() {
                          _batchItems.clear();
                        });
                      },
                child: const Text('Clear'),
              ),
            ],
          ),
          const Divider(height: 20),
          // List of items
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _batchItems.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = _batchItems[index];
                return _buildBatchItemTile(item, isDark);
              },
            ),
          ),
          const SizedBox(height: 16),
          // Button to verify batch
          BouncingTap(
            onTap: _isVerifying
                ? null
                : () {
                    if (_batchItems.isEmpty) return;
                    AdService.showInterstitialAd(
                      onProceed: () {
                        _verifyBatch();
                      },
                    );
                  },
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: null, // handled by BouncingTap
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white,
                  disabledBackgroundColor: AppTheme.primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _isVerifying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.verified_user_rounded, size: 20),
                label: Text(
                  _isVerifying
                      ? 'Verifying Batch...'
                      : (pendingCount == 0 && verifyingCount == 0
                          ? 'Re-Verify All (${_batchItems.length} PDFs)'
                          : 'Verify All (${_batchItems.length} PDFs)'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchItemTile(BatchPdfItem item, bool isDark) {
    Color badgeColor;
    String badgeText;
    IconData? badgeIcon;

    switch (item.status) {
      case 'VALID':
        badgeColor = const Color(0xFF008A2A);
        badgeText = '✓ Valid';
        badgeIcon = Icons.check_circle_rounded;
        break;
      case 'INVALID':
        badgeColor = AppTheme.invalidColor;
        badgeText = '✗ Invalid';
        badgeIcon = Icons.cancel_rounded;
        break;
      case 'NO_SIGNATURES':
        badgeColor = AppTheme.warningColor;
        badgeText = '⚠ Unsigned';
        badgeIcon = Icons.warning_amber_rounded;
        break;
      case 'SKIPPED':
        badgeColor = Colors.amber.shade800;
        badgeText = '🔒 Skipped';
        badgeIcon = Icons.lock_clock_rounded;
        break;
      case 'VERIFYING':
        badgeColor = AppTheme.primaryColor;
        badgeText = 'Verifying...';
        break;
      case 'ERROR':
        badgeColor = AppTheme.invalidColor;
        badgeText = 'Error';
        badgeIcon = Icons.error_outline_rounded;
        break;
      default:
        badgeColor = Colors.grey;
        badgeText = 'Queued';
        badgeIcon = Icons.schedule_rounded;
    }

    final canOpen = item.result != null;

    return BouncingTap(
      onTap: canOpen
          ? () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => VerificationScreen(
                    result: item.result!,
                    pdfPath: item.path,
                    fileName: item.name,
                    password: item.password,
                  ),
                ),
              );
            }
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurface : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.picture_as_pdf_rounded, color: Colors.redAccent, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    item.errorMessage ?? _formatFileSize(item.size),
                    style: TextStyle(
                      fontSize: 11,
                      color: item.status == 'SKIPPED'
                          ? Colors.amber.shade800
                          : (isDark ? Colors.white54 : Colors.grey.shade600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: item.status == 'VERIFYING'
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor: AlwaysStoppedAnimation<Color>(badgeColor),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          badgeText,
                          style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (badgeIcon != null) ...[
                          Icon(badgeIcon, size: 12, color: badgeColor),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          badgeText,
                          style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
            ),
            if (canOpen) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 18, color: isDark ? Colors.white38 : Colors.grey.shade400),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHistorySection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.history_rounded, size: 18, color: AppTheme.primaryColor),
                const SizedBox(width: 6),
                Text(
                  'Recent Verifications',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.grey.shade900,
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: () async {
                await HistoryService.clearHistory();
                _loadHistory();
                if (mounted) {
                  AppSnackBar.show(
                    context,
                    message: 'History cleared',
                    duration: const Duration(seconds: 2),
                  );
                }
              },
              child: const Text('Clear All', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _historyItems.length > 5 ? 5 : _historyItems.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final item = _historyItems[index];
            return _buildHistoryItemTile(item, isDark);
          },
        ),
      ],
    );
  }

  Widget _buildHistoryItemTile(HistoryItem item, bool isDark) {
    Color badgeColor;
    String badgeText;

    switch (item.status) {
      case 'VALID':
        badgeColor = const Color(0xFF008A2A);
        badgeText = '✓ Valid';
        break;
      case 'INVALID':
        badgeColor = AppTheme.invalidColor;
        badgeText = '✗ Invalid';
        break;
      case 'NO_SIGNATURES':
        badgeColor = AppTheme.warningColor;
        badgeText = '⚠ Unsigned';
        break;
      default:
        badgeColor = Colors.grey;
        badgeText = item.status;
    }

    final formattedDate = DateFormat('d MMM, h:mm a').format(item.timestamp);

    return BouncingTap(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => VerificationScreen(
              result: item.result,
              pdfPath: item.filePath,
              fileName: item.fileName,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurfaceVariant : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.picture_as_pdf_rounded, color: Colors.redAccent, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.fileName,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.signerName != null
                        ? '${item.signerName} • $formattedDate'
                        : formattedDate,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : Colors.grey.shade600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                badgeText,
                style: TextStyle(
                  color: badgeColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 18, color: isDark ? Colors.white38 : Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoSection(bool isDark) {
    return SizedBox(
      width: 105,
      height: 105,
      child: Image.asset(
        'assets/icon/app_logo.png',
        fit: BoxFit.contain,
        cacheWidth: 210,
        cacheHeight: 210,
      ),
    );
  }

  Widget _buildSelectPdfSection(bool isDark, ColorScheme colorScheme) {
    return BouncingTap(
      onTap: _isVerifying ? null : _pickPdf,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurfaceVariant : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? AppTheme.primaryColor.withValues(alpha: 0.3)
                : AppTheme.primaryColor.withValues(alpha: 0.2),
            width: 2,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                _selectedFilePath != null
                    ? Icons.picture_as_pdf_rounded
                    : Icons.upload_file_rounded,
                size: 32,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _selectedFilePath != null
                  ? 'Change PDF File'
                  : 'Select PDF File',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap to browse and select a PDF document',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white54 : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileInfoCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurfaceVariant : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.validColor.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.picture_as_pdf_rounded,
              color: Colors.red.shade700,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedFileName ?? 'Unknown',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  _formatFileSize(_selectedFileSize ?? 0),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.check_circle_rounded,
            color: AppTheme.validColor,
            size: 22,
          ),
        ],
      ),
    );
  }

  Widget _buildVerifyButton(ColorScheme colorScheme) {
    return BouncingTap(
      onTap: _isVerifying
          ? null
          : () {
              if (_selectedFilePath == null) return;
              AdService.showInterstitialAd(
                onProceed: () {
                  _verifySignature();
                },
              );
            },
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton(
          onPressed: null, // handled by BouncingTap
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white,
            disabledBackgroundColor: AppTheme.primaryColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 2,
          ),
          child: _isVerifying
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  SizedBox(width: 14),
                  Text(
                    'Verifying Signatures...',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified_user_rounded, size: 22),
                  SizedBox(width: 10),
                  Text(
                    'Verify Digital Signature',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
        ),
      ),
    );
  }



    // URLs for Privacy Policy, Terms, Feedback, and Open Source
  static const String privacyPolicyUrl =
      'https://sites.google.com/view/pdf-sign-verify-privacy-policy/home';
  static const String termsAndConditionsUrl =
      'https://sites.google.com/view/pdf-sign-verify-terms-and-cond/home';
  static const String feedbackUrl =
      'https://docs.google.com/forms/d/e/1FAIpQLSfint7zfaiEG7laKRKEFEw2_djnIYaqtoj_jlsc9HiYp1qbaw/viewform?usp=publish-editor';
  static const String githubSourceUrl =
      'https://github.com/bapikirtania13/pdfsignverify';

  Future<void> _openUrl(String urlString) async {
    final uri = Uri.parse(urlString);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (_) {
      try {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (e) {
        if (mounted) {
          AppSnackBar.show(
            context,
            message: 'Could not open link: $e',
            duration: const Duration(seconds: 2),
          );
        }
      }
    }
  }

  void _showAboutDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. App Logo (Clean transparent PNG)
                SizedBox(
                  width: 82,
                  height: 82,
                  child: Image.asset(
                    'assets/icon/app_logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 14),

                // 2. Title & Version Badge
                Text(
                  'PDF Sign Verify',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : Colors.grey.shade900,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: isDark ? 0.18 : 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'v1.0.16 • Digital Signature Engine',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // 3. Professional Overview Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.darkSurfaceVariant
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                    ),
                  ),
                  child: Column(
                    children: [
                      _buildAboutFeatureItem(
                        Icons.verified_user_rounded,
                        'Cryptographic Verification',
                        'Standard CMS/PKCS#7 signature validation',
                        isDark,
                      ),
                      const SizedBox(height: 10),
                      _buildAboutFeatureItem(
                        Icons.lock_outline_rounded,
                        '100% On-Device Privacy',
                        'Documents are inspected locally and never uploaded',
                        isDark,
                      ),
                      const SizedBox(height: 10),
                      _buildAboutFeatureItem(
                        Icons.check_circle_outline_rounded,
                        'Official Verified Display',
                        'Generates authentic verified green checkmark preview',
                        isDark,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // 4. Privacy Policy, Terms, Feedback & Open Source Links Section
                _buildLinkTile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy Policy',
                  subtitle: 'Read our data protection & privacy terms',
                  onTap: () => _openUrl(privacyPolicyUrl),
                  isDark: isDark,
                ),
                const SizedBox(height: 10),
                _buildLinkTile(
                  icon: Icons.description_outlined,
                  title: 'Terms & Conditions',
                  subtitle: 'Read our service terms & legal disclaimer',
                  onTap: () => _openUrl(termsAndConditionsUrl),
                  isDark: isDark,
                ),
                const SizedBox(height: 10),
                _buildLinkTile(
                  icon: Icons.feedback_outlined,
                  title: 'Feedback & Support',
                  subtitle: 'Share suggestions or get technical help',
                  onTap: () => _openUrl(feedbackUrl),
                  isDark: isDark,
                ),
                const SizedBox(height: 10),
                _buildLinkTile(
                  icon: Icons.code_rounded,
                  title: 'Source Code & License',
                  subtitle: 'Open source under GNU AGPLv3 on GitHub',
                  onTap: () => _openUrl(githubSourceUrl),
                  isDark: isDark,
                ),
                const SizedBox(height: 22),

                // 5. Done Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 1,
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAboutFeatureItem(
    IconData icon,
    String title,
    String description,
    bool isDark,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 18,
          color: const Color(0xFF008A2A),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.grey.shade900,
                ),
              ),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white60 : Colors.grey.shade600,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLinkTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurfaceVariant : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: isDark ? 0.18 : 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 20,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.grey.shade900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white54 : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: isDark ? Colors.white38 : Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

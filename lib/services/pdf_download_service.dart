import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'ad_service.dart';
import '../widgets/app_snack_bar.dart';

class PdfDownloadService {
  static const MethodChannel _platformChannel =
      MethodChannel('com.pdfsignverify/verification');

  /// Save a PDF file to the Android public Downloads directory
  static Future<bool> saveToDownloads({
    required String sourcePath,
    required String targetFileName,
  }) async {
    try {
      final sourceFile = File(sourcePath);
      if (!sourceFile.existsSync()) return false;

      // Ensure fileName ends with .pdf
      var cleanName = targetFileName;
      if (!cleanName.toLowerCase().endsWith('.pdf')) {
        cleanName = '$cleanName.pdf';
      }

      // 1. Native Android MediaStore Downloads saver (indexes directly into system Downloads)
      try {
        final result = await _platformChannel.invokeMethod<String>(
          'savePdfToDownloads',
          {
            'sourcePath': sourceFile.path,
            'fileName': cleanName,
          },
        );
        if (result != null && result.isNotEmpty) {
          debugPrint('Successfully saved to public downloads via MediaStore: $result');
          return true;
        }
      } catch (channelError) {
        debugPrint('Native savePdfToDownloads error, trying fallback: $channelError');
      }

      // 2. Secondary public Download directory fallback
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (downloadDir.existsSync()) {
        try {
          final destFile = File('${downloadDir.path}/$cleanName');
          await sourceFile.copy(destFile.path);
          if (destFile.existsSync() && destFile.lengthSync() > 0) {
            return true;
          }
        } catch (_) {}
      }

      // 3. Secondary SDCard path fallback
      final altDownloadDir = Directory('/sdcard/Download');
      if (altDownloadDir.existsSync()) {
        try {
          final destFile = File('${altDownloadDir.path}/$cleanName');
          await sourceFile.copy(destFile.path);
          if (destFile.existsSync() && destFile.lengthSync() > 0) {
            return true;
          }
        } catch (_) {}
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  /// Share PDF via Android system share sheet
  static Future<void> sharePdf({
    required String filePath,
    required String title,
  }) async {
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        await Share.shareXFiles(
          [XFile(filePath)],
          subject: title,
        );
      }
    } catch (_) {}
  }

  /// Show standard bottom sheet offering Download and Share options
  static void showDownloadSheet({
    required BuildContext context,
    required String originalPath,
    String? verifiedPath,
    required String baseFileName,
  }) {
    final hasVerified = verifiedPath != null &&
        verifiedPath.isNotEmpty &&
        File(verifiedPath).existsSync();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: isDark ? const Color(0xFF1E232A) : Colors.white,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF008A2A).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.download_rounded,
                        color: Color(0xFF008A2A),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Download / Save PDF',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                if (hasVerified) ...[
                  ListTile(
                    leading: const Icon(Icons.verified_rounded, color: Color(0xFF008A2A)),
                    title: const Text('Download Verified PDF', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('With verified green tick & signature details'),
                    trailing: const Icon(Icons.file_download_outlined),
                    onTap: () {
                      Navigator.pop(ctx);
                      // Play rewarded interstitial ad only for verified PDF download
                      AdService.showRewardedIfVerified(
                        isVerified: true,
                        onProceed: () async {
                          final name = baseFileName.toLowerCase().endsWith('.pdf')
                              ? '${baseFileName.substring(0, baseFileName.length - 4)}_verified.pdf'
                              : '${baseFileName}_verified.pdf';

                          final saved = await saveToDownloads(
                            sourcePath: verifiedPath,
                            targetFileName: name,
                          );

                          if (context.mounted) {
                            if (saved) {
                              AppSnackBar.show(
                                context,
                                content: Text('Saved to Downloads: $name'),
                                backgroundColor: const Color(0xFF008A2A),
                                duration: const Duration(seconds: 2),
                                action: SnackBarAction(
                                  label: 'Share',
                                  textColor: Colors.white,
                                  onPressed: () => sharePdf(filePath: verifiedPath, title: name),
                                ),
                              );
                            } else {
                              // Fallback to system share
                              await sharePdf(filePath: verifiedPath, title: name);
                            }
                          }
                        },
                      );
                    },
                  ),
                ],
                ListTile(
                  leading: const Icon(Icons.description_outlined, color: Colors.blueAccent),
                  title: Text(
                    hasVerified ? 'Download Original Unmodified PDF' : 'Download PDF',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('Original file as uploaded'),
                  trailing: const Icon(Icons.file_download_outlined),
                  onTap: () async {
                    Navigator.pop(ctx);
                    // Do NOT play ad when downloading unverified / original unmodified PDF
                    final name = baseFileName.toLowerCase().endsWith('.pdf')
                        ? baseFileName
                        : '$baseFileName.pdf';

                    final saved = await saveToDownloads(
                      sourcePath: originalPath,
                      targetFileName: name,
                    );

                    if (context.mounted) {
                      if (saved) {
                        AppSnackBar.show(
                          context,
                          content: Text('Saved to Downloads: $name'),
                          backgroundColor: const Color(0xFF008A2A),
                          duration: const Duration(seconds: 2),
                          action: SnackBarAction(
                            label: 'Share',
                            textColor: Colors.white,
                            onPressed: () => sharePdf(filePath: originalPath, title: name),
                          ),
                        );
                      } else {
                        // Fallback to system share
                        await sharePdf(filePath: originalPath, title: name);
                      }
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.share_rounded, color: Colors.deepPurpleAccent),
                  title: const Text('Share PDF via Other Apps', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('WhatsApp, Gmail, Drive, etc.'),
                  trailing: const Icon(Icons.open_in_new_rounded),
                  onTap: () {
                    Navigator.pop(ctx);
                    final targetPath = hasVerified ? verifiedPath : originalPath;
                    if (hasVerified) {
                      // Verified share: trigger rewarded interstitial
                      AdService.showRewardedIfVerified(
                        isVerified: true,
                        onProceed: () async {
                          await sharePdf(filePath: targetPath, title: baseFileName);
                        },
                      );
                    } else {
                      // Unverified share: no ad played
                      sharePdf(filePath: targetPath, title: baseFileName);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

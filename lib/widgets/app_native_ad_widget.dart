import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_service.dart';
import '../theme/app_theme.dart';

/// A polished, modern, policy-compliant Native Ad Widget.
///
/// Features:
/// - Styled NativeTemplateStyle conforming to AppTheme (light and dark mode).
/// - Loads once per screen visit with resilient auto-retry if initial load fails
///   (e.g. WebView/JavascriptEngine warm-up delay or temporary network glitch).
/// - Clear "Sponsored" badge that strictly distinguishes ads from core document features.
/// - Graceful error collapse.
class AppNativeAdWidget extends StatefulWidget {
  final String adUnitId;

  const AppNativeAdWidget({
    super.key,
    required this.adUnitId,
  });

  @override
  State<AppNativeAdWidget> createState() => _AppNativeAdWidgetState();
}

class _AppNativeAdWidgetState extends State<AppNativeAdWidget> {
  NativeAd? _nativeAd;
  bool _isLoaded = false;
  bool _hasLoadedOnce = false;
  Timer? _retryTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasLoadedOnce) {
      _hasLoadedOnce = true;
      _loadNativeAd();
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _nativeAd?.dispose();
    super.dispose();
  }

  NativeTemplateStyle _buildNativeStyle(bool isDark) {
    return NativeTemplateStyle(
      templateType: TemplateType.small,
      mainBackgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
      cornerRadius: 12.0,
      callToActionTextStyle: NativeTemplateTextStyle(
        textColor: Colors.white,
        backgroundColor: AppTheme.primaryColor,
        style: NativeTemplateFontStyle.bold,
        size: 13.0,
      ),
      primaryTextStyle: NativeTemplateTextStyle(
        textColor: isDark ? Colors.white : const Color(0xFF1F2937),
        style: NativeTemplateFontStyle.bold,
        size: 13.5,
      ),
      secondaryTextStyle: NativeTemplateTextStyle(
        textColor: isDark ? Colors.white70 : const Color(0xFF4B5563),
        style: NativeTemplateFontStyle.normal,
        size: 12.0,
      ),
      tertiaryTextStyle: NativeTemplateTextStyle(
        textColor: isDark ? Colors.white60 : const Color(0xFF6B7280),
        style: NativeTemplateFontStyle.normal,
        size: 11.0,
      ),
    );
  }

  Future<void> _loadNativeAd() async {
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    _retryTimer?.cancel();

    await AdService.waitForInit;
    if (!mounted) return;

    final nativeAd = NativeAd(
      adUnitId: widget.adUnitId,
      request: const AdRequest(),
      nativeTemplateStyle: _buildNativeStyle(isDark),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          debugPrint('[AppNativeAd] Native ad loaded successfully: $ad');
          if (!mounted) {
            ad.dispose();
            return;
          }
          AdService.recordLoadSuccess('native');
          setState(() {
            _nativeAd?.dispose();
            _nativeAd = ad as NativeAd;
            _isLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('[AppNativeAd] Failed to load: ${error.message} (Code: ${error.code})');
          AdService.recordLoadFailure('native', error);
          ad.dispose();
          if (!mounted) return;
          // Auto-retry after 5 seconds if not yet loaded (e.g. WebView warm-up delay)
          _retryTimer?.cancel();
          _retryTimer = Timer(const Duration(seconds: 5), () {
            if (mounted && _nativeAd == null) {
              _loadNativeAd();
            }
          });
        },
        onAdImpression: (ad) {
          AdService.recordImpression('native', widget.adUnitId);
        },
      ),
    );

    nativeAd.load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _nativeAd == null) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.grey.shade200,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ad Badge Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.campaign_rounded,
                        size: 12,
                        color: AppTheme.primaryColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Sponsored',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Ad',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white38 : Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          // Native Ad Content (height: 110 for optimal small template rendering)
          LayoutBuilder(
            builder: (context, constraints) {
              final adWidth = constraints.maxWidth > 0 ? constraints.maxWidth : MediaQuery.of(context).size.width - 32;
              return ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
                child: SizedBox(
                  width: adWidth,
                  height: 110,
                  child: AdWidget(
                    key: ValueKey(_nativeAd.hashCode),
                    ad: _nativeAd!,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

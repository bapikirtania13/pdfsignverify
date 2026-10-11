import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_service.dart';
import '../theme/app_theme.dart';

/// A polished, modern, policy-compliant Native Ad Widget.
///
/// Features:
/// - Styled NativeTemplateStyle conforming to AppTheme (light and dark mode).
/// - Policy-compliant 45-second refresh interval to maximize legitimate viewability and eCPM.
/// - Seamless background loading: preloads the next ad in memory before swapping to eliminate flicker.
/// - Lifecycle-aware: automatically pauses auto-refresh when the app is backgrounded.
/// - Pauses during PDF verification/signing operations.
/// - Clear "Sponsored" badge that strictly distinguishes ads from core document features.
/// - Smooth loading skeleton and graceful error collapse.
class AppNativeAdWidget extends StatefulWidget {
  final String adUnitId;

  const AppNativeAdWidget({
    super.key,
    required this.adUnitId,
  });

  @override
  State<AppNativeAdWidget> createState() => _AppNativeAdWidgetState();
}

class _AppNativeAdWidgetState extends State<AppNativeAdWidget>
    with WidgetsBindingObserver {
  NativeAd? _currentNativeAd;
  NativeAd? _loadingNextNativeAd;
  bool _isLoaded = false;
  Timer? _refreshTimer;
  bool _isAppResumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadNativeAd();
    _startAutoRefreshTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final resumed = (state == AppLifecycleState.resumed);
    if (_isAppResumed != resumed) {
      _isAppResumed = resumed;
      if (_isAppResumed) {
        _startAutoRefreshTimer();
      } else {
        _stopAutoRefreshTimer();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAutoRefreshTimer();
    _currentNativeAd?.dispose();
    _loadingNextNativeAd?.dispose();
    super.dispose();
  }

  void _startAutoRefreshTimer() {
    _stopAutoRefreshTimer();
    if (!_isAppResumed || !mounted) return;

    _refreshTimer = Timer.periodic(AdService.nativeRefreshInterval, (_) {
      if (!mounted) return;
      if (!_isAppResumed || AdService.isOperationInProgress) return;
      final isCurrentRoute = ModalRoute.of(context)?.isCurrent ?? true;
      if (!isCurrentRoute) return; // Do not reload native ad while screen is obscured

      if (_currentNativeAd == null) {
        _loadNativeAd();
      } else {
        _refreshNativeAd();
      }
    });
  }

  void _stopAutoRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
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

  void _loadNativeAd() {
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final nativeAd = NativeAd(
      adUnitId: widget.adUnitId,
      request: const AdRequest(),
      nativeTemplateStyle: _buildNativeStyle(isDark),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          AdService.recordLoadSuccess('native');
          setState(() {
            _currentNativeAd?.dispose();
            _currentNativeAd = ad as NativeAd;
            _isLoaded = true;
          });
          _startAutoRefreshTimer();
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('[AppNativeAd] Failed to load: ${error.message}');
          AdService.recordLoadFailure('native', error);
          ad.dispose();
        },
        onAdImpression: (ad) {
          AdService.recordImpression('native', widget.adUnitId);
        },
      ),
    );

    nativeAd.load();
  }

  void _refreshNativeAd() {
    if (_loadingNextNativeAd != null || !mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    _loadingNextNativeAd = NativeAd(
      adUnitId: widget.adUnitId,
      request: const AdRequest(),
      nativeTemplateStyle: _buildNativeStyle(isDark),
      listener: NativeAdListener(
        onAdLoaded: (newAd) {
          if (!mounted) {
            newAd.dispose();
            return;
          }
          AdService.recordLoadSuccess('native');
          final oldAd = _currentNativeAd;
          setState(() {
            _currentNativeAd = newAd as NativeAd;
            _loadingNextNativeAd = null;
            _isLoaded = true;
          });
          oldAd?.dispose();
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('[AppNativeAd] Refresh failed: ${error.message}');
          AdService.recordLoadFailure('native', error);
          ad.dispose();
          _loadingNextNativeAd = null;
        },
        onAdImpression: (ad) {
          AdService.recordImpression('native', widget.adUnitId);
        },
      ),
    );

    _loadingNextNativeAd!.load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _currentNativeAd == null) {
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
          // Native Ad Content
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(14),
              bottomRight: Radius.circular(14),
            ),
            child: SizedBox(
              height: 96,
              child: AdWidget(ad: _currentNativeAd!),
            ),
          ),
        ],
      ),
    );
  }
}

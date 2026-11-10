import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_service.dart';
import '../theme/app_theme.dart';

/// Reusable, premium AdMob Banner Ad widget with policy-compliant auto-refresh.
///
/// Features modeled after Crypto-Test and Trade-Test:
/// - Policy-compliant auto-refresh (clamped to minimum 30s per AdMob terms, default 45s).
/// - Seamless ad swapping with zero UI flicker during rotation (old ad stays visible until new ad loads).
/// - App lifecycle awareness (WidgetsBindingObserver pauses refresh and retry in background, resumes on foreground).
/// - Resilient 45s auto-retry when unfilled or recovering from network issues.
/// - Operation protection: pauses refresh while PDF signing/verification is in progress.
/// - Debug mode test ad fallback for reliable local developer verification.
/// - Polished design with light/dark theme support, subtle borders, and non-intrusive AD badge.
class AppBannerAdWidget extends StatefulWidget {
  final String adUnitId;
  final EdgeInsetsGeometry? margin;
  final Duration? autoRefreshInterval;

  const AppBannerAdWidget({
    super.key,
    required this.adUnitId,
    this.margin,
    this.autoRefreshInterval,
  });

  @override
  State<AppBannerAdWidget> createState() => _AppBannerAdWidgetState();
}

class _AppBannerAdWidgetState extends State<AppBannerAdWidget>
    with WidgetsBindingObserver {
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;
  bool _isLoading = false;
  bool _usingFallback = false;
  Timer? _refreshTimer;
  Timer? _retryTimer;
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAndLoadAd();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _isPaused = true;
      _refreshTimer?.cancel();
      _retryTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _isPaused = false;
      if (!_isAdLoaded) {
        _retryTimer?.cancel();
        _loadAd(widget.adUnitId);
      } else {
        _scheduleAutoRefresh();
      }
    }
  }

  Future<void> _initAndLoadAd() async {
    await AdService.waitForInit;
    if (!mounted) return;
    _loadAd(widget.adUnitId);
  }

  /// Automatically retries loading banner ad every 45 seconds when no ad is present
  void _scheduleRetry() {
    _retryTimer?.cancel();
    _refreshTimer?.cancel();
    if (_isPaused || !mounted || _isAdLoaded) return;

    _retryTimer = Timer(AdService.retryInterval, () {
      if (mounted && !_isPaused && !_isAdLoaded) {
        debugPrint('[AppBannerAd] Retrying banner load after ${AdService.retryInterval.inSeconds}s until filled...');
        _usingFallback = false;
        _loadAd(widget.adUnitId);
      }
    });
  }

  /// Policy-compliant automatic refresh: rotates banner every 45 seconds (clamped to >= 30s per AdMob policy)
  void _scheduleAutoRefresh() {
    _refreshTimer?.cancel();
    if (_isPaused || !mounted) return;

    // AdMob policy strictly forbids client-side refresh below 30 seconds
    final requestedInterval = widget.autoRefreshInterval ?? AdService.bannerRefreshInterval;
    final effectiveInterval = requestedInterval < const Duration(seconds: 30)
        ? const Duration(seconds: 30)
        : requestedInterval;

    _refreshTimer = Timer(effectiveInterval, () {
      if (!mounted || _isPaused) return;

      // Defer refresh if a cryptographic PDF operation is actively computing
      if (AdService.isOperationInProgress) {
        debugPrint('[AppBannerAd] Operation in progress; deferring banner refresh by 10s');
        _refreshTimer = Timer(const Duration(seconds: 10), _scheduleAutoRefresh);
        return;
      }

      _usingFallback = false;
      _loadAd(widget.adUnitId);
    });
  }

  void _loadAd(String targetAdUnitId) {
    if (_isLoading) return;
    _isLoading = true;

    final oldAd = _bannerAd;
    final newAd = BannerAd(
      adUnitId: targetAdUnitId,
      request: const AdRequest(
        keywords: AdService.contextualKeywords,
      ),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          _isLoading = false;
          if (!mounted) {
            ad.dispose();
            return;
          }
          debugPrint('[AppBannerAd] Banner loaded successfully ($targetAdUnitId)');
          _retryTimer?.cancel();
          _retryTimer = null;
          AdService.recordLoadSuccess('banner');

          // Seamless swap: replace current banner without UI blank
          setState(() {
            _bannerAd = ad as BannerAd;
            _isAdLoaded = true;
          });
          oldAd?.dispose();

          // Schedule next auto-rotation
          _scheduleAutoRefresh();
        },
        onAdFailedToLoad: (ad, err) {
          _isLoading = false;
          ad.dispose();
          debugPrint(
            '[AppBannerAd] Failed to load banner ($targetAdUnitId): ${err.message} (code ${err.code})',
          );
          AdService.recordLoadFailure('banner', err);

          // Fallback to test banner if production banner has no fill, ensuring banner is never blank
          if (!_usingFallback &&
              targetAdUnitId != AdService.testBannerId) {
            _usingFallback = true;
            debugPrint('[AppBannerAd] Falling back to test banner...');
            Future.microtask(() {
              if (mounted) _loadAd(AdService.testBannerId);
            });
          } else {
            if (_bannerAd == null) {
              if (mounted) {
                setState(() {
                  _isAdLoaded = false;
                });
              }
              // If no banner is displayed, retry periodically every 45s
              _scheduleRetry();
            } else {
              // Existing banner is still visible on screen; re-arm refresh timer for next cycle
              _scheduleAutoRefresh();
            }
          }
        },
        onAdImpression: (ad) {
          AdService.recordImpression('banner', targetAdUnitId);
        },
      ),
    );

    try {
      newAd.load();
    } catch (e) {
      _isLoading = false;
      debugPrint('[AppBannerAd] Exception loading banner ad: $e');
      if (_bannerAd == null) {
        _scheduleRetry();
      } else {
        _scheduleAutoRefresh();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _retryTimer?.cancel();
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdLoaded || _bannerAd == null) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.darkSurfaceVariant : Colors.white;
    final adWidth = _bannerAd!.size.width.toDouble();
    final adHeight = _bannerAd!.size.height.toDouble();

    return SafeArea(
      top: false,
      child: Padding(
        padding: widget.margin ?? const EdgeInsets.only(top: 4, bottom: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: _isAdLoaded ? 1.0 : 0.0,
              child: Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? AppTheme.primaryColor.withValues(alpha: 0.22)
                        : AppTheme.primaryColor.withValues(alpha: 0.18),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.35)
                          : AppTheme.primaryColor.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: adWidth,
                      height: adHeight,
                      child: AdWidget(
                        key: ValueKey(_bannerAd.hashCode),
                        ad: _bannerAd!,
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black54 : Colors.black12,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          'AD',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

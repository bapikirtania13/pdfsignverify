import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_service.dart';
import '../theme/app_theme.dart';

/// Premium floating card banner ad widget matching the Pito Notes design.
///
/// Features:
/// - Sleek, professional rounded card frame with ambient shadows and subtle borders.
/// - Sits neatly at the bottom without taking up excessive screen or body space.
/// - AdMob policy-compliant refresh rate to maximize legitimate viewability and eCPM.
/// - Seamless background ad preloading and post-frame disposal to prevent UI flicker.
/// - Pauses refresh on ad interaction (click / open) to give users seamless ad experience.
/// - Resilient auto-retry on load failure so the banner reliably displays.
class AppBannerAdWidget extends StatefulWidget {
  final String adUnitId;

  const AppBannerAdWidget({
    super.key,
    required this.adUnitId,
  });

  @override
  State<AppBannerAdWidget> createState() => _AppBannerAdWidgetState();
}

class _AppBannerAdWidgetState extends State<AppBannerAdWidget>
    with WidgetsBindingObserver {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  Timer? _refreshTimer;
  Timer? _retryTimer;
  bool _isRefreshing = false;
  bool _isAdInteracted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadInitialAd();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isAdInteracted = false;
      _scheduleNextRefresh();
    } else {
      _cancelTimers();
    }
  }

  void _cancelTimers() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _scheduleNextRefresh() {
    _refreshTimer?.cancel();
    if (!mounted || _isAdInteracted) return;

    _refreshTimer = Timer(AdService.bannerRefreshInterval, () {
      if (mounted && !_isAdInteracted && !AdService.isOperationInProgress) {
        final isCurrentRoute = ModalRoute.of(context)?.isCurrent ?? true;
        if (!isCurrentRoute) {
          // Route is not visible (covered by another screen); re-check later
          _scheduleNextRefresh();
          return;
        }
        _refreshAd();
      }
    });
  }

  void _loadInitialAd() {
    _cancelTimers();
    _bannerAd?.dispose();

    _bannerAd = BannerAd(
      adUnitId: widget.adUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint('[AppBannerAd] Banner loaded successfully: $ad');
          if (!mounted) {
            ad.dispose();
            return;
          }
          AdService.recordLoadSuccess('banner');
          setState(() {
            _bannerAd = ad as BannerAd;
            _isLoaded = true;
          });
          _scheduleNextRefresh();
        },
        onAdFailedToLoad: (ad, err) {
          debugPrint('[AppBannerAd] Failed to load: ${err.message} (Code: ${err.code})');
          AdService.recordLoadFailure('banner', err);
          ad.dispose();
          if (!mounted) return;
          // Retry after 5 seconds if not yet loaded
          _retryTimer?.cancel();
          _retryTimer = Timer(const Duration(seconds: 5), () {
            if (mounted && !_isAdInteracted && _bannerAd == null) {
              _loadInitialAd();
            }
          });
        },
        onAdImpression: (ad) {
          AdService.recordImpression('banner', widget.adUnitId);
        },
        onAdClicked: (ad) {
          debugPrint('[AppBannerAd] Ad clicked - pausing auto-refresh.');
          _isAdInteracted = true;
          _cancelTimers();
        },
        onAdOpened: (ad) {
          debugPrint('[AppBannerAd] Ad opened - pausing auto-refresh.');
          _isAdInteracted = true;
          _cancelTimers();
        },
        onAdClosed: (ad) {
          debugPrint('[AppBannerAd] Ad closed - resuming auto-refresh.');
          _isAdInteracted = false;
          _scheduleNextRefresh();
        },
        onAdWillDismissScreen: (ad) {
          _isAdInteracted = false;
          _scheduleNextRefresh();
        },
      ),
    )..load();
  }

  /// Seamlessly loads the next banner ad in the background before swapping
  void _refreshAd() {
    if (_isRefreshing || _isAdInteracted || !mounted || AdService.isOperationInProgress) return;
    final isCurrentRoute = ModalRoute.of(context)?.isCurrent ?? true;
    if (!isCurrentRoute) {
      _scheduleNextRefresh();
      return;
    }
    _isRefreshing = true;

    BannerAd? nextBannerAd;
    nextBannerAd = BannerAd(
      adUnitId: widget.adUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          _isRefreshing = false;
          if (!mounted || _isAdInteracted) {
            ad.dispose();
            return;
          }
          AdService.recordLoadSuccess('banner');
          final oldAd = _bannerAd;
          setState(() {
            _bannerAd = ad as BannerAd;
            _isLoaded = true;
          });
          // Safely dispose old ad after next frame so Flutter has bound the new platform view
          if (oldAd != null && oldAd != ad) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              oldAd.dispose();
            });
          }
          _scheduleNextRefresh();
        },
        onAdFailedToLoad: (ad, err) {
          _isRefreshing = false;
          debugPrint('[AppBannerAd] Refresh failed: ${err.message}');
          AdService.recordLoadFailure('banner', err);
          ad.dispose();
          // Keep current ad visible and schedule retry
          _scheduleNextRefresh();
        },
        onAdImpression: (ad) {
          AdService.recordImpression('banner', widget.adUnitId);
        },
        onAdClicked: (ad) {
          debugPrint('[AppBannerAd] Ad clicked - pausing auto-refresh.');
          _isAdInteracted = true;
          _cancelTimers();
        },
        onAdOpened: (ad) {
          debugPrint('[AppBannerAd] Ad opened - pausing auto-refresh.');
          _isAdInteracted = true;
          _cancelTimers();
        },
        onAdClosed: (ad) {
          debugPrint('[AppBannerAd] Ad closed - resuming auto-refresh.');
          _isAdInteracted = false;
          _scheduleNextRefresh();
        },
        onAdWillDismissScreen: (ad) {
          _isAdInteracted = false;
          _scheduleNextRefresh();
        },
      ),
    );

    nextBannerAd.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelTimers();
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_bannerAd == null || !_isLoaded) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.darkSurfaceVariant : Colors.white;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: _bannerAd!.size.width.toDouble(),
                  height: _bannerAd!.size.height.toDouble(),
                  child: AdWidget(
                    key: ValueKey(_bannerAd.hashCode),
                    ad: _bannerAd!,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

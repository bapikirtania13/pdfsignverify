import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_service.dart';
import '../theme/app_theme.dart';

/// Premium floating card banner ad widget.
///
/// Features:
/// - Sleek, professional rounded card frame with ambient shadows and subtle borders.
/// - Sits neatly at the bottom without taking up excessive screen or body space.
/// - Lets Google AdMob's native SDK manage optimal refresh timing automatically
///   ("Google optimized" in AdMob console), maximizing legitimate viewability and eCPM.
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

class _AppBannerAdWidgetState extends State<AppBannerAdWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _loadInitialAd();
  }

  Future<void> _loadInitialAd() async {
    _retryTimer?.cancel();
    _bannerAd?.dispose();

    await AdService.waitForInit;
    if (!mounted) return;

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
        },
        onAdFailedToLoad: (ad, err) {
          debugPrint('[AppBannerAd] Failed to load: ${err.message} (Code: ${err.code})');
          AdService.recordLoadFailure('banner', err);
          ad.dispose();
          if (!mounted) return;
          // Retry after 5 seconds if not yet loaded
          _retryTimer?.cancel();
          _retryTimer = Timer(const Duration(seconds: 5), () {
            if (mounted && (_bannerAd == null || !_isLoaded)) {
              _loadInitialAd();
            }
          });
        },
        onAdImpression: (ad) {
          AdService.recordImpression('banner', widget.adUnitId);
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
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

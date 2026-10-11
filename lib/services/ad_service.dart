import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  // Provided Ad Unit IDs
  static const String homeBannerId = 'ca-app-pub-1284309397637088/6361057428';
  static const String verifyBannerId = 'ca-app-pub-1284309397637088/3675184336';
  static const String nativeAdId = 'ca-app-pub-1284309397637088/6609303586';
  static const String rewardedInterstitialId = 'ca-app-pub-1284309397637088/4693761691';

  /// Policy-compliant 35-second automatic refresh interval for banner ads
  /// (Strictly exceeds Google AdMob's minimum 30s requirement, maximizing eCPM & viewability)
  static const Duration bannerRefreshInterval = Duration(seconds: 35);

  /// Policy-compliant 45-second automatic refresh interval for native ads
  /// (Eliminates layout shifts and preserves optimal viewability)
  static const Duration nativeRefreshInterval = Duration(seconds: 45);

  /// Global flag to pause ad refresh during critical user flows
  /// (e.g. PDF cryptographic verification, signing, report generation)
  static bool isOperationInProgress = false;

  // Ad Performance & Revenue Optimization Metrics
  static int bannerImpressions = 0;
  static int bannerLoadSuccesses = 0;
  static int bannerLoadFailures = 0;

  static int nativeImpressions = 0;
  static int nativeLoadSuccesses = 0;
  static int nativeLoadFailures = 0;

  static void recordImpression(String format, String adUnitId) {
    if (format == 'banner') {
      bannerImpressions++;
    } else if (format == 'native') {
      nativeImpressions++;
    }
    debugPrint('[AdService] Impression recorded for $format ($adUnitId). Total $format impressions: ${format == 'banner' ? bannerImpressions : nativeImpressions}');
  }

  static void recordLoadSuccess(String format) {
    if (format == 'banner') {
      bannerLoadSuccesses++;
    } else if (format == 'native') {
      nativeLoadSuccesses++;
    }
  }

  static void recordLoadFailure(String format, LoadAdError error) {
    if (format == 'banner') {
      bannerLoadFailures++;
    } else if (format == 'native') {
      nativeLoadFailures++;
    }
    debugPrint('[AdService] $format load failure: ${error.message} (Code: ${error.code})');
  }

  static RewardedInterstitialAd? _rewardedInterstitialAd;
  static bool _isLoadingRewarded = false;
  static int _rewardedRetryCount = 0;

  /// Initialize Mobile Ads SDK and preload rewarded interstitial
  static Future<void> initialize() async {
    try {
      await MobileAds.instance.initialize();
      loadRewardedInterstitial();
    } catch (e) {
      debugPrint('AdService initialization error: $e');
    }
  }

  /// Preload Rewarded Interstitial Ad
  static void loadRewardedInterstitial() {
    if (_rewardedInterstitialAd != null || _isLoadingRewarded) return;
    _isLoadingRewarded = true;

    RewardedInterstitialAd.load(
      adUnitId: rewardedInterstitialId,
      request: const AdRequest(),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedInterstitialAd = ad;
          _isLoadingRewarded = false;
          _rewardedRetryCount = 0;
          debugPrint('[AdService] Rewarded interstitial preloaded successfully.');
        },
        onAdFailedToLoad: (error) {
          debugPrint('RewardedInterstitialAd failed to load: ${error.message}');
          _rewardedInterstitialAd = null;
          _isLoadingRewarded = false;
          // Retry up to 3 times with exponential delay
          if (_rewardedRetryCount < 3) {
            _rewardedRetryCount++;
            Future.delayed(Duration(seconds: 5 * _rewardedRetryCount), () {
              loadRewardedInterstitial();
            });
          }
        },
      ),
    );
  }

  /// Shows the Rewarded Interstitial Ad ONLY IF the document is verified and valid.
  /// If the document is NOT verified, or if the ad is not ready, proceeds immediately.
  static void showRewardedIfVerified({
    required bool isVerified,
    required VoidCallback onProceed,
  }) {
    // If not verified, DO NOT show the ad.
    if (!isVerified) {
      onProceed();
      return;
    }

    if (_rewardedInterstitialAd != null) {
      final ad = _rewardedInterstitialAd!;
      _rewardedInterstitialAd = null; // Mark consumed
      isOperationInProgress = true;

      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          isOperationInProgress = false;
          ad.dispose();
          loadRewardedInterstitial(); // Preload next
          onProceed();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          isOperationInProgress = false;
          debugPrint('Rewarded interstitial failed to show: ${error.message}');
          ad.dispose();
          loadRewardedInterstitial();
          onProceed();
        },
      );

      ad.show(
        onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
          debugPrint('User earned reward: ${reward.amount} ${reward.type}');
        },
      );
    } else {
      // Ad wasn't ready yet: proceed without blocking user, and attempt reload
      loadRewardedInterstitial();
      onProceed();
    }
  }
}

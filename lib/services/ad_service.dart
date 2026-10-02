import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  // Provided Ad Unit IDs
  static const String homeBannerId = 'ca-app-pub-1284309397637088/6361057428';
  static const String verifyBannerId = 'ca-app-pub-1284309397637088/3675184336';
  static const String nativeAdId = 'ca-app-pub-1284309397637088/6609303586';
  static const String rewardedInterstitialId = 'ca-app-pub-1284309397637088/4693761691';

  static RewardedInterstitialAd? _rewardedInterstitialAd;
  static bool _isLoadingRewarded = false;

  /// Initialize Mobile Ads SDK and preload rewarded interstitial
  static Future<void> initialize() async {
    try {
      await MobileAds.instance.initialize();
      loadRewardedInterstitial();
    } catch (e) {
      debugPrint('AdService initialization error: $e');
    }
  }

  static int _rewardedRetryCount = 0;

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
        },
        onAdFailedToLoad: (error) {
          debugPrint('RewardedInterstitialAd failed to load: ${error.message}');
          _rewardedInterstitialAd = null;
          _isLoadingRewarded = false;
          // Retry up to 3 times with increasing delay
          if (_rewardedRetryCount < 3) {
            _rewardedRetryCount++;
            Future.delayed(Duration(seconds: 3 * _rewardedRetryCount), () {
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

      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          loadRewardedInterstitial(); // Preload next
          onProceed();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
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

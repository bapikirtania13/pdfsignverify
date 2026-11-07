import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  // Production Ad Unit IDs
  static const String homeBannerId = 'ca-app-pub-1284309397637088/6361057428';
  static const String verifyBannerId = 'ca-app-pub-1284309397637088/3675184336';
  static const String nativeAdId = 'ca-app-pub-1284309397637088/6609303586';
  static const String rewardedInterstitialId = 'ca-app-pub-1284309397637088/4693761691';

  // Official Google AdMob Test Ad Unit IDs (used as fallback in debug mode only)
  static const String testBannerId = 'ca-app-pub-3940256099942544/6300978111';
  static const String testNativeId = 'ca-app-pub-3940256099942544/2247696110';
  static const String testRewardedInterstitialId = 'ca-app-pub-3940256099942544/5354046379';

  static final Completer<void> _initCompleter = Completer<void>();
  static Future<void> get waitForInit => _initCompleter.isCompleted ? Future.value() : _initCompleter.future;

  /// Policy-compliant 45-second automatic refresh interval for banner ads
  /// (Strictly complies with Google AdMob minimum 30s requirement, maximizing eCPM & viewability)
  static const Duration bannerRefreshInterval = Duration(seconds: 45);

  /// Retry interval when an ad fails to load (no fill / network glitch)
  static const Duration retryInterval = Duration(seconds: 45);

  /// Native ad freshness TTL (90s window like Crypto-Test, prevents rapid timer flipping)
  static const Duration nativeCacheTtl = Duration(seconds: 90);

  /// High-inventory contextual keywords to maximize AdMob advertiser fill rate
  static const List<String> contextualKeywords = [
    'pdf',
    'document',
    'scanner',
    'tools',
    'business',
    'office',
    'productivity',
    'utilities',
    'finance',
    'security',
    'digital signature',
  ];

  /// Checks if the device has an active network connection and reachability to the internet.
  static Future<bool> hasInternetConnection() async {
    try {
      final lookup = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      return lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

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
      final initStatus = await MobileAds.instance.initialize();
      initStatus.adapterStatuses.forEach((adapter, status) {
        debugPrint(
          '[AdService] Mediation Adapter: $adapter | State: ${status.state} | Description: ${status.description}',
        );
      });
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }
      loadRewardedInterstitial();
    } catch (e) {
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }
      debugPrint('AdService initialization error: $e');
    }
  }

  /// Preload Rewarded Interstitial Ad with automatic fallback to test unit if production is unfilled
  static void loadRewardedInterstitial() {
    if (_rewardedInterstitialAd != null || _isLoadingRewarded) return;
    _isLoadingRewarded = true;

    final targetUnitId = kDebugMode ? testRewardedInterstitialId : rewardedInterstitialId;
    _loadRewardedInterstitialWithFallback(targetUnitId);
  }

  static void _loadRewardedInterstitialWithFallback(String targetUnitId) {
    RewardedInterstitialAd.load(
      adUnitId: targetUnitId,
      request: const AdRequest(keywords: contextualKeywords),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedInterstitialAd = ad;
          _isLoadingRewarded = false;
          _rewardedRetryCount = 0;
          debugPrint('[AdService] Rewarded interstitial preloaded successfully ($targetUnitId).');
        },
        onAdFailedToLoad: (error) {
          debugPrint(
            'RewardedInterstitialAd failed to load ($targetUnitId): ${error.message} (code ${error.code})',
          );
          _rewardedInterstitialAd = null;
          _isLoadingRewarded = false;

          // NEVER show test ads in release mode. Only in debug mode can test ad fallback be used.
          if (kDebugMode && targetUnitId != testRewardedInterstitialId) {
            debugPrint('[AdService] Debug mode: falling back to test rewarded interstitial ad...');
            _loadRewardedInterstitialWithFallback(testRewardedInterstitialId);
            return;
          }

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

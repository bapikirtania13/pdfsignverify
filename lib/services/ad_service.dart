import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  // Production Ad Unit IDs
  // Banner Ad ID (Home and Verification screens share this unit ID)
  static const String homeBannerId = 'ca-app-pub-1284309397637088/6361057428';
  static const String verifyBannerId = 'ca-app-pub-1284309397637088/6361057428';

  // Native Ad ID
  static const String nativeAdId = 'ca-app-pub-1284309397637088/6609303586';

  // App Open Ad ID (shown when opening or resuming the app)
  static const String appOpenAdId = 'ca-app-pub-1284309397637088/6870966920';

  // Interstitial Ad ID (shown at natural transition points like verification complete)
  static const String interstitialAdId = 'ca-app-pub-1284309397637088/7992476909';

  // Rewarded Interstitial Ad ID (for downloading verified PDF)
  static const String rewardedInterstitialId = 'ca-app-pub-1284309397637088/4693761691';

  // Rewarded Ad ID (for sharing verified PDF via other apps)
  static const String rewardedShareId = 'ca-app-pub-1284309397637088/1935489961';

  static final Completer<void> _initCompleter = Completer<void>();
  static Future<void> get waitForInit => _initCompleter.isCompleted ? Future.value() : _initCompleter.future;

  /// Policy-compliant 45-second automatic refresh interval for banner ads
  /// (Strictly complies with Google AdMob minimum 30s requirement, maximizing eCPM & viewability)
  static const Duration bannerRefreshInterval = Duration(seconds: 45);

  /// Retry interval when an ad fails to load (no fill / network glitch)
  static const Duration retryInterval = Duration(seconds: 45);

  /// Native ad freshness TTL (90s window, prevents rapid timer flipping)
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

  /// Global flag indicating a full-screen ad is currently active (prevents overlapping ads)
  static bool isShowingFullScreenAd = false;

  /// Timestamp of the last dismissed full-screen ad (prevents showing ads back-to-back)
  static DateTime? lastFullScreenAdDismissed;

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

  // ---------------------------------------------------------------------------
  // SDK INITIALIZATION & PRELOAD
  // ---------------------------------------------------------------------------

  /// Initialize Mobile Ads SDK and preload all full-screen formats
  static Future<void> initialize() async {
    try {
      final initStatus = await MobileAds.instance.initialize();
      initStatus.adapterStatuses.forEach((adapter, status) {
        debugPrint(
          '[AdService] Mediation Adapter: $adapter | State: ${status.state} | Description: ${status.description}',
        );
      });

      // Enforce live ads: empty testDeviceIds ensures test ads are never returned
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(
          testDeviceIds: const <String>[],
        ),
      );

      // Start listening for app lifecycle events (foregrounding / app resume)
      try {
        await AppStateEventNotifier.startListening();
        AppStateEventNotifier.appStateStream.listen((state) {
          if (state == AppState.foreground) {
            debugPrint('[AdService] App foregrounded -> checking App Open Ad...');
            showAppOpenAdIfAvailable();
          }
        });
      } catch (e) {
        debugPrint('[AdService] AppStateEventNotifier initialization error: $e');
      }

      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }

      // Preload all full-screen ad types concurrently
      loadAppOpenAd();
      loadInterstitialAd();
      loadRewardedInterstitial();
      loadRewardedShareAd();
    } catch (e) {
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }
      debugPrint('AdService initialization error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // 1. APP OPEN AD (ca-app-pub-1284309397637088/6870966920)
  // ---------------------------------------------------------------------------
  static AppOpenAd? _appOpenAd;
  static bool _isLoadingAppOpen = false;
  static DateTime? _appOpenLoadTime;
  static int _appOpenRetryCount = 0;
  static Completer<bool>? _firstAppOpenCompleter;

  /// Waits for the initial App Open Ad to finish loading (returns true if loaded, false if timed out or failed).
  static Future<bool> waitForFirstAppOpenAd({
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    if (isAppOpenAdAvailable) return true;
    _firstAppOpenCompleter ??= Completer<bool>();
    try {
      return await _firstAppOpenCompleter!.future.timeout(
        timeout,
        onTimeout: () => false,
      );
    } catch (_) {
      return false;
    }
  }

  /// Preload App Open Ad
  static void loadAppOpenAd() {
    if (_appOpenAd != null || _isLoadingAppOpen) return;
    _isLoadingAppOpen = true;

    AppOpenAd.load(
      adUnitId: appOpenAdId,
      request: const AdRequest(keywords: contextualKeywords),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _appOpenAd = ad;
          _isLoadingAppOpen = false;
          _appOpenLoadTime = DateTime.now();
          _appOpenRetryCount = 0;
          debugPrint('[AdService] App Open ad preloaded successfully ($appOpenAdId).');

          if (_firstAppOpenCompleter != null && !_firstAppOpenCompleter!.isCompleted) {
            _firstAppOpenCompleter!.complete(true);
          }
        },
        onAdFailedToLoad: (error) {
          debugPrint('AppOpenAd failed to load ($appOpenAdId): ${error.message} (code ${error.code})');
          _appOpenAd = null;
          _isLoadingAppOpen = false;

          if (_firstAppOpenCompleter != null && !_firstAppOpenCompleter!.isCompleted) {
            _firstAppOpenCompleter!.complete(false);
          }

          if (_appOpenRetryCount < 3) {
            _appOpenRetryCount++;
            Future.delayed(Duration(seconds: 5 * _appOpenRetryCount), () {
              loadAppOpenAd();
            });
          }
        },
      ),
    );
  }

  /// Whether an App Open Ad is cached and still fresh (< 4 hours per AdMob policy)
  static bool get isAppOpenAdAvailable {
    if (_appOpenAd == null || _appOpenLoadTime == null) return false;
    final isExpired = DateTime.now().difference(_appOpenLoadTime!) > const Duration(hours: 4);
    if (isExpired) {
      _appOpenAd?.dispose();
      _appOpenAd = null;
      loadAppOpenAd();
      return false;
    }
    return true;
  }

  /// Shows the App Open Ad when opening the app or returning from background.
  static void showAppOpenAdIfAvailable({VoidCallback? onDismissed}) {
    if (isShowingFullScreenAd || isOperationInProgress) {
      debugPrint('[AdService] Skipped App Open Ad: operation or full-screen ad already active.');
      onDismissed?.call();
      return;
    }

    // Cooldown check: do not show if another full-screen ad was dismissed within 15 seconds
    if (lastFullScreenAdDismissed != null &&
        DateTime.now().difference(lastFullScreenAdDismissed!) < const Duration(seconds: 15)) {
      debugPrint('[AdService] Skipped App Open Ad: 15s cooldown active.');
      onDismissed?.call();
      return;
    }

    if (!isAppOpenAdAvailable) {
      debugPrint('[AdService] App Open Ad not ready yet; initiating load.');
      loadAppOpenAd();
      onDismissed?.call();
      return;
    }

    final ad = _appOpenAd!;
    _appOpenAd = null; // Mark consumed
    isShowingFullScreenAd = true;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        debugPrint('[AdService] App Open ad displaying full screen.');
      },
      onAdDismissedFullScreenContent: (ad) {
        debugPrint('[AdService] App Open ad dismissed.');
        isShowingFullScreenAd = false;
        lastFullScreenAdDismissed = DateTime.now();
        ad.dispose();
        loadAppOpenAd(); // Preload next
        onDismissed?.call();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('[AdService] App Open ad failed to show: ${error.message}');
        isShowingFullScreenAd = false;
        lastFullScreenAdDismissed = DateTime.now();
        ad.dispose();
        loadAppOpenAd();
        onDismissed?.call();
      },
    );

    try {
      ad.show();
    } catch (e) {
      debugPrint('[AdService] Exception displaying App Open Ad: $e');
      isShowingFullScreenAd = false;
      lastFullScreenAdDismissed = DateTime.now();
      ad.dispose();
      loadAppOpenAd();
      onDismissed?.call();
    }
  }

  // ---------------------------------------------------------------------------
  // 2. INTERSTITIAL AD (ca-app-pub-1284309397637088/7992476909)
  // ---------------------------------------------------------------------------
  static InterstitialAd? _interstitialAd;
  static bool _isLoadingInterstitial = false;
  static int _interstitialRetryCount = 0;

  /// Preload Interstitial Ad
  static void loadInterstitialAd() {
    if (_interstitialAd != null || _isLoadingInterstitial) return;
    _isLoadingInterstitial = true;

    InterstitialAd.load(
      adUnitId: interstitialAdId,
      request: const AdRequest(keywords: contextualKeywords),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isLoadingInterstitial = false;
          _interstitialRetryCount = 0;
          debugPrint('[AdService] Interstitial ad preloaded successfully ($interstitialAdId).');
        },
        onAdFailedToLoad: (error) {
          debugPrint('InterstitialAd failed to load ($interstitialAdId): ${error.message} (code ${error.code})');
          _interstitialAd = null;
          _isLoadingInterstitial = false;

          if (_interstitialRetryCount < 3) {
            _interstitialRetryCount++;
            Future.delayed(Duration(seconds: 5 * _interstitialRetryCount), () {
              loadInterstitialAd();
            });
          }
        },
      ),
    );
  }

  /// Shows the Interstitial Ad at natural completion milestones (e.g. after verification finishes).
  /// Proceeds immediately if not ready or in cooldown to guarantee uninterrupted UX.
  static void showInterstitialAd({required VoidCallback onProceed}) {
    if (_interstitialAd != null && !isShowingFullScreenAd) {
      final ad = _interstitialAd!;
      _interstitialAd = null; // Mark consumed
      isShowingFullScreenAd = true;
      isOperationInProgress = true;

      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          isShowingFullScreenAd = false;
          isOperationInProgress = false;
          lastFullScreenAdDismissed = DateTime.now();
          ad.dispose();
          loadInterstitialAd(); // Preload next
          onProceed();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          isShowingFullScreenAd = false;
          isOperationInProgress = false;
          lastFullScreenAdDismissed = DateTime.now();
          debugPrint('[AdService] Interstitial ad failed to show: ${error.message}');
          ad.dispose();
          loadInterstitialAd();
          onProceed();
        },
      );

      ad.show();
    } else {
      // Ad not ready: proceed smoothly without blocking the user
      loadInterstitialAd();
      onProceed();
    }
  }

  // ---------------------------------------------------------------------------
  // 3. REWARDED INTERSTITIAL AD (ca-app-pub-1284309397637088/4693761691)
  // Used specifically for downloading the verified PDF with green tick details
  // ---------------------------------------------------------------------------
  static RewardedInterstitialAd? _rewardedInterstitialAd;
  static bool _isLoadingRewarded = false;
  static int _rewardedRetryCount = 0;

  /// Preload Rewarded Interstitial Ad
  static void loadRewardedInterstitial() {
    if (_rewardedInterstitialAd != null || _isLoadingRewarded) return;
    _isLoadingRewarded = true;

    RewardedInterstitialAd.load(
      adUnitId: rewardedInterstitialId,
      request: const AdRequest(keywords: contextualKeywords),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedInterstitialAd = ad;
          _isLoadingRewarded = false;
          _rewardedRetryCount = 0;
          debugPrint('[AdService] Rewarded interstitial preloaded successfully ($rewardedInterstitialId).');
        },
        onAdFailedToLoad: (error) {
          debugPrint(
            'RewardedInterstitialAd failed to load ($rewardedInterstitialId): ${error.message} (code ${error.code})',
          );
          _rewardedInterstitialAd = null;
          _isLoadingRewarded = false;

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

  /// Shows Rewarded Interstitial Ad ONLY IF the document is verified and valid.
  /// Used for saving/downloading verified PDF.
  static void showRewardedIfVerified({
    required bool isVerified,
    required VoidCallback onProceed,
  }) {
    if (!isVerified) {
      onProceed();
      return;
    }

    if (_rewardedInterstitialAd != null && !isShowingFullScreenAd) {
      final ad = _rewardedInterstitialAd!;
      _rewardedInterstitialAd = null; // Mark consumed
      isShowingFullScreenAd = true;
      isOperationInProgress = true;

      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          isShowingFullScreenAd = false;
          isOperationInProgress = false;
          lastFullScreenAdDismissed = DateTime.now();
          ad.dispose();
          loadRewardedInterstitial(); // Preload next
          onProceed();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          isShowingFullScreenAd = false;
          isOperationInProgress = false;
          lastFullScreenAdDismissed = DateTime.now();
          debugPrint('Rewarded interstitial failed to show: ${error.message}');
          ad.dispose();
          loadRewardedInterstitial();
          onProceed();
        },
      );

      ad.show(
        onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
          debugPrint('User earned reward for download: ${reward.amount} ${reward.type}');
        },
      );
    } else {
      // Ad wasn't ready yet: proceed without blocking user, and attempt reload
      loadRewardedInterstitial();
      onProceed();
    }
  }

  // ---------------------------------------------------------------------------
  // 4. REWARDED AD (ca-app-pub-1284309397637088/1935489961)
  // Used specifically for sharing verified PDF via other apps
  // ---------------------------------------------------------------------------
  static RewardedAd? _rewardedShareAd;
  static bool _isLoadingRewardedShare = false;
  static int _rewardedShareRetryCount = 0;

  /// Preload Rewarded Ad for sharing
  static void loadRewardedShareAd() {
    if (_rewardedShareAd != null || _isLoadingRewardedShare) return;
    _isLoadingRewardedShare = true;

    RewardedAd.load(
      adUnitId: rewardedShareId,
      request: const AdRequest(keywords: contextualKeywords),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedShareAd = ad;
          _isLoadingRewardedShare = false;
          _rewardedShareRetryCount = 0;
          debugPrint('[AdService] Rewarded Share ad preloaded successfully ($rewardedShareId).');
        },
        onAdFailedToLoad: (error) {
          debugPrint('RewardedAd (Share) failed to load ($rewardedShareId): ${error.message} (code ${error.code})');
          _rewardedShareAd = null;
          _isLoadingRewardedShare = false;

          if (_rewardedShareRetryCount < 3) {
            _rewardedShareRetryCount++;
            Future.delayed(Duration(seconds: 5 * _rewardedShareRetryCount), () {
              loadRewardedShareAd();
            });
          }
        },
      ),
    );
  }

  /// Shows the Rewarded Ad ONLY IF the document is verified.
  /// Used when user shares the verified PDF via other apps anywhere in the app.
  static void showRewardedForVerifiedShare({
    required bool isVerified,
    required VoidCallback onProceed,
  }) {
    if (!isVerified) {
      onProceed();
      return;
    }

    if (_rewardedShareAd != null && !isShowingFullScreenAd) {
      final ad = _rewardedShareAd!;
      _rewardedShareAd = null; // Mark consumed
      isShowingFullScreenAd = true;
      isOperationInProgress = true;

      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          isShowingFullScreenAd = false;
          isOperationInProgress = false;
          lastFullScreenAdDismissed = DateTime.now();
          ad.dispose();
          loadRewardedShareAd(); // Preload next
          onProceed();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          isShowingFullScreenAd = false;
          isOperationInProgress = false;
          lastFullScreenAdDismissed = DateTime.now();
          debugPrint('Rewarded Share ad failed to show: ${error.message}');
          ad.dispose();
          loadRewardedShareAd();
          onProceed();
        },
      );

      ad.show(
        onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
          debugPrint('User earned reward for sharing: ${reward.amount} ${reward.type}');
        },
      );
    } else {
      // Ad wasn't ready yet: proceed without blocking user, and attempt reload
      loadRewardedShareAd();
      onProceed();
    }
  }
}

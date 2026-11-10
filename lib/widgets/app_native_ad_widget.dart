import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_service.dart';
import '../theme/app_theme.dart';

/// A polished, modern, policy-compliant Native Ad Widget.
///
/// Features modeled after Crypto-Test and Trade-Test:
/// - Policy-compliant native ad lifecycle: no disruptive timer swapping while viewed.
/// - In-memory freshness window (90s TTL like Crypto-Test): refreshes stale ads seamlessly
///   upon returning to the foreground without flashing.
/// - Lifecycle awareness (WidgetsBindingObserver) pauses retry timers when backgrounded.
/// - Scroll keep-alive (AutomaticKeepAliveClientMixin) prevents re-rendering on list scrolling.
/// - Seamless swapping: loads new ad in background before disposing old ad to eliminate layout flicker.
/// - Auto-retry every 45s when no ad is loaded (network recovery / backoff).
/// - Contextual keyword targeting for document verification.
/// - Collapses to SizedBox.shrink() if no ad is loaded, avoiding empty blank spaces.
class AppNativeAdWidget extends StatefulWidget {
  final String adUnitId;
  final EdgeInsetsGeometry? margin;
  final bool keepAlive;

  const AppNativeAdWidget({
    super.key,
    required this.adUnitId,
    this.margin,
    this.keepAlive = true,
  });

  @override
  State<AppNativeAdWidget> createState() => _AppNativeAdWidgetState();
}

class _AppNativeAdWidgetState extends State<AppNativeAdWidget>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  NativeAd? _nativeAd;
  bool _isAdLoaded = false;
  bool _isLoading = false;
  bool _isInitialized = false;
  Timer? _retryTimer;
  bool _isPaused = false;

  @override
  bool get wantKeepAlive => widget.keepAlive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _isPaused = true;
      _retryTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _isPaused = false;
      // Per AdMob policy: if native ad is already loaded, it stays there (no auto-refresh).
      // If no ad is currently loaded, retry loading immediately.
      if (!_isAdLoaded) {
        _retryTimer?.cancel();
        _loadNativeAd(widget.adUnitId);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _isInitialized = true;
      _initAndLoad();
    }
  }

  Future<void> _initAndLoad() async {
    await AdService.waitForInit;
    if (!mounted) return;
    _loadNativeAd(widget.adUnitId);
  }

  /// Automatically retries loading native ad every 45 seconds until an ad arrives
  void _scheduleRetry() {
    _retryTimer?.cancel();
    if (_isPaused || !mounted || _isAdLoaded) return;

    _retryTimer = Timer(AdService.retryInterval, () {
      if (mounted && !_isPaused && !_isAdLoaded) {
        debugPrint('[AppNativeAd] Retrying native ad load after ${AdService.retryInterval.inSeconds}s until filled...');
        _loadNativeAd(widget.adUnitId);
      }
    });
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

  void _loadNativeAd(String targetAdUnitId) {
    if (_isLoading) return;

    // Do not load or refresh during heavy cryptographic verification
    if (AdService.isOperationInProgress && _isAdLoaded) {
      return;
    }

    _isLoading = true;
    final isDark = mounted ? Theme.of(context).brightness == Brightness.dark : false;

    final oldAd = _nativeAd;
    final newAd = NativeAd(
      adUnitId: targetAdUnitId,
      request: const AdRequest(
        keywords: AdService.contextualKeywords,
      ),
      nativeTemplateStyle: _buildNativeStyle(isDark),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          _isLoading = false;
          if (!mounted) {
            ad.dispose();
            return;
          }
          debugPrint('[AppNativeAd] Native ad loaded successfully ($targetAdUnitId)');
          _retryTimer?.cancel();
          _retryTimer = null;
          AdService.recordLoadSuccess('native');

          setState(() {
            _nativeAd = ad as NativeAd;
            _isAdLoaded = true;
          });
          oldAd?.dispose();
        },
        onAdFailedToLoad: (ad, error) {
          _isLoading = false;
          ad.dispose();
          debugPrint(
            '[AppNativeAd] Failed to load native ad ($targetAdUnitId): ${error.message} (code ${error.code})',
          );
          AdService.recordLoadFailure('native', error);

          if (_nativeAd == null) {
            if (mounted) {
              setState(() {
                _isAdLoaded = false;
              });
            }
            // No ad is showing: schedule periodic retry until filled
            _scheduleRetry();
          }
        },
        onAdImpression: (ad) {
          AdService.recordImpression('native', targetAdUnitId);
        },
      ),
    );

    try {
      newAd.load();
    } catch (e) {
      _isLoading = false;
      debugPrint('[AppNativeAd] Exception loading native ad: $e');
      if (_nativeAd == null) {
        _scheduleRetry();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // If genuinely no ad is loaded, the ad space is completely empty
    if (!_isAdLoaded || _nativeAd == null) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    const adHeight = 96.0;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: _isAdLoaded ? 1.0 : 0.0,
      child: Container(
        margin: widget.margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.grey.shade200,
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: adHeight,
          width: double.infinity,
          child: AdWidget(
            key: ValueKey(_nativeAd.hashCode),
            ad: _nativeAd!,
          ),
        ),
      ),
    );
  }
}

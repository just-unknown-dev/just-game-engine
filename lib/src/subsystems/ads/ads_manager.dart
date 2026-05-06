library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_signals/just_signals.dart';

import '../../ecs/ecs.dart';
import 'ad_events.dart';
import 'ad_types.dart';
import 'ads_provider.dart';

/// Engine-level façade for the ads subsystem.
///
/// Accessible via [Engine.ads]. Delegates all ad operations to the registered
/// [AdsProvider] (default: [NoOpAdsProvider]).
///
/// **Typical setup** (in app bootstrap, mobile only):
/// ```dart
/// if (Platform.isAndroid || Platform.isIOS) {
///   engine.ads.registerProvider(JustAdsProvider(config: JustAdsConfig(...)));
///   await engine.ads.initialize();
/// }
/// ```
class AdsManager {
  AdsProvider _provider = NoOpAdsProvider();
  World? _world;

  // ── Signals ────────────────────────────────────────────────────────────────

  final Signal<ConsentStatus> consentStatus =
      Signal<ConsentStatus>(ConsentStatus.unknown);
  final Signal<bool> isInitialized = Signal<bool>(false);
  final Signal<bool> isInterstitialReady = Signal<bool>(false);
  final Signal<bool> isRewardedReady = Signal<bool>(false);
  final Signal<bool> isAppOpenReady = Signal<bool>(false);

  // ── Setup ──────────────────────────────────────────────────────────────────

  /// Binds the ECS world so ad events are fired on its event bus.
  void bindWorld(World world) => _world = world;

  /// Replaces the current provider and resets [isInitialized] to `false`.
  ///
  /// The previous provider is disposed first.
  void registerProvider(AdsProvider provider) {
    _provider.dispose();
    _provider = provider;
    isInitialized.value = false;
  }

  /// Updates [consentStatus] and fires [AdConsentStatusChangedEvent].
  ///
  /// Called by the concrete provider (e.g. JustAdsProvider) after UMP completes.
  void updateConsentStatus(ConsentStatus status) {
    consentStatus.value = status;
    _world?.events.fire(AdConsentStatusChangedEvent(status: status));
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Runs the UMP consent flow then initialises the ad SDK.
  ///
  /// Idempotent — subsequent calls return immediately if already initialized.
  Future<void> initialize({ConsentConfig? consent}) async {
    if (isInitialized.value) return;
    try {
      await _provider.initialize(consent: consent);
      isInitialized.value = true;
    } catch (e) {
      debugPrint('AdsManager: initialization failed ($e)');
    }
  }

  void dispose() {
    _provider.dispose();
    consentStatus.dispose();
    isInitialized.dispose();
    isInterstitialReady.dispose();
    isRewardedReady.dispose();
    isAppOpenReady.dispose();
  }

  // ── Banner ─────────────────────────────────────────────────────────────────

  Future<BannerAdInstance?> createBannerAd(BannerAdConfig config) async {
    try {
      final instance = await _provider.createBannerAd(config);
      if (instance != null) {
        _world?.events.fire(AdLoadedEvent(adType: AdType.banner));
      }
      return instance;
    } catch (e) {
      _world?.events
          .fire(AdFailedToLoadEvent(adType: AdType.banner, error: '$e'));
      return null;
    }
  }

  // ── Interstitial ───────────────────────────────────────────────────────────

  Future<void> preloadInterstitialAd(String adUnitId) async {
    isInterstitialReady.value = false;
    try {
      await _provider.preloadInterstitialAd(adUnitId);
      isInterstitialReady.value = _provider.isInterstitialAdReady;
      if (isInterstitialReady.value) {
        _world?.events.fire(AdLoadedEvent(adType: AdType.interstitial));
      }
    } catch (e) {
      _world?.events.fire(
        AdFailedToLoadEvent(adType: AdType.interstitial, error: '$e'),
      );
    }
  }

  /// Shows the cached interstitial. Returns `false` if not ready.
  ///
  /// [adUnitId] is used to auto-preload the next ad after a successful show.
  Future<bool> showInterstitialAd({String? adUnitId}) async {
    final shown = await _provider.showInterstitialAd();
    if (shown) {
      isInterstitialReady.value = false;
      _world?.events.fire(AdShownEvent(adType: AdType.interstitial));
      if (adUnitId != null) unawaited(preloadInterstitialAd(adUnitId));
    }
    return shown;
  }

  bool get isInterstitialAdReady => _provider.isInterstitialAdReady;

  // ── Rewarded ───────────────────────────────────────────────────────────────

  Future<void> preloadRewardedAd(String adUnitId) async {
    isRewardedReady.value = false;
    try {
      await _provider.preloadRewardedAd(adUnitId);
      isRewardedReady.value = _provider.isRewardedAdReady;
      if (isRewardedReady.value) {
        _world?.events.fire(AdLoadedEvent(adType: AdType.rewarded));
      }
    } catch (e) {
      _world?.events.fire(
        AdFailedToLoadEvent(adType: AdType.rewarded, error: '$e'),
      );
    }
  }

  /// Shows the cached rewarded ad.
  ///
  /// Returns the [JustRewardItem] on reward, or `null` if skipped/not ready.
  /// [adUnitId] is used to auto-preload the next ad after the show.
  Future<JustRewardItem?> showRewardedAd({String? adUnitId}) async {
    final reward = await _provider.showRewardedAd();
    isRewardedReady.value = false;
    _world?.events.fire(AdShownEvent(adType: AdType.rewarded));
    if (reward != null) {
      _world?.events.fire(AdRewardedEvent(reward: reward));
    }
    if (adUnitId != null) unawaited(preloadRewardedAd(adUnitId));
    return reward;
  }

  bool get isRewardedAdReady => _provider.isRewardedAdReady;

  // ── App Open ───────────────────────────────────────────────────────────────

  Future<void> preloadAppOpenAd(String adUnitId) async {
    isAppOpenReady.value = false;
    try {
      await _provider.preloadAppOpenAd(adUnitId);
      isAppOpenReady.value = _provider.isAppOpenAdReady;
      if (isAppOpenReady.value) {
        _world?.events.fire(AdLoadedEvent(adType: AdType.appOpen));
      }
    } catch (e) {
      _world?.events.fire(
        AdFailedToLoadEvent(adType: AdType.appOpen, error: '$e'),
      );
    }
  }

  /// Shows the cached app-open ad. Returns `false` if not ready.
  ///
  /// [adUnitId] is used to auto-preload the next ad after a successful show.
  Future<bool> showAppOpenAd({String? adUnitId}) async {
    final shown = await _provider.showAppOpenAd();
    if (shown) {
      isAppOpenReady.value = false;
      _world?.events.fire(AdShownEvent(adType: AdType.appOpen));
      if (adUnitId != null) unawaited(preloadAppOpenAd(adUnitId));
    }
    return shown;
  }

  bool get isAppOpenAdReady => _provider.isAppOpenAdReady;
}

library;

import 'ad_types.dart';

/// Abstract contract for ad backends.
///
/// Implement this in a platform-specific package (e.g. `just_ads`) and register
/// an instance via [AdsManager.registerProvider].
abstract class AdsProvider {
  Future<void> initialize({ConsentConfig? consent});

  Future<BannerAdInstance?> createBannerAd(BannerAdConfig config);

  Future<void> preloadInterstitialAd(String adUnitId);
  Future<bool> showInterstitialAd();
  bool get isInterstitialAdReady;

  Future<void> preloadRewardedAd(String adUnitId);
  Future<JustRewardItem?> showRewardedAd();
  bool get isRewardedAdReady;

  Future<void> preloadAppOpenAd(String adUnitId);
  Future<bool> showAppOpenAd();
  bool get isAppOpenAdReady;

  void dispose();
}

/// Default no-op provider — all methods silently succeed, no ads are shown.
///
/// Active by default on all platforms until [AdsManager.registerProvider] is called.
class NoOpAdsProvider implements AdsProvider {
  @override
  Future<void> initialize({ConsentConfig? consent}) async {}

  @override
  Future<BannerAdInstance?> createBannerAd(BannerAdConfig config) async => null;

  @override
  Future<void> preloadInterstitialAd(String adUnitId) async {}

  @override
  Future<bool> showInterstitialAd() async => false;

  @override
  bool get isInterstitialAdReady => false;

  @override
  Future<void> preloadRewardedAd(String adUnitId) async {}

  @override
  Future<JustRewardItem?> showRewardedAd() async => null;

  @override
  bool get isRewardedAdReady => false;

  @override
  Future<void> preloadAppOpenAd(String adUnitId) async {}

  @override
  Future<bool> showAppOpenAd() async => false;

  @override
  bool get isAppOpenAdReady => false;

  @override
  void dispose() {}
}

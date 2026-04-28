library;

import '../../ecs/ecs.dart';
import 'ad_types.dart';

/// Distinguishes ad formats in events.
enum AdType { banner, interstitial, rewarded, appOpen }

/// Fired when an ad has finished loading.
class AdLoadedEvent extends GameEvent {
  AdLoadedEvent({required this.adType});
  final AdType adType;
}

/// Fired when an ad fails to load.
class AdFailedToLoadEvent extends GameEvent {
  AdFailedToLoadEvent({required this.adType, required this.error});
  final AdType adType;
  final String error;
}

/// Fired when an ad is displayed to the user.
class AdShownEvent extends GameEvent {
  AdShownEvent({required this.adType});
  final AdType adType;
}

/// Fired when an ad overlay is dismissed by the user.
class AdDismissedEvent extends GameEvent {
  AdDismissedEvent({required this.adType});
  final AdType adType;
}

/// Fired when a rewarded ad grants its reward.
class AdRewardedEvent extends GameEvent {
  AdRewardedEvent({required this.reward});
  final JustRewardItem reward;
}

/// Fired when the UMP consent status changes.
class AdConsentStatusChangedEvent extends GameEvent {
  AdConsentStatusChangedEvent({required this.status});
  final ConsentStatus status;
}

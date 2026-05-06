library;

import '../../ecs/ecs.dart';

class CurrencyChangedEvent extends GameEvent {
  final String currencyId;
  final int previousBalance;
  final int newBalance;

  CurrencyChangedEvent({
    required this.currencyId,
    required this.previousBalance,
    required this.newBalance,
  });
}

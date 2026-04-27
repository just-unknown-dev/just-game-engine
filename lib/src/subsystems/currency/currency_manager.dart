library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_database/just_database.dart';

import '../../ecs/ecs.dart';
import 'currency_events.dart';

class CurrencyManager {
  static const String _kTable = 'jge_currency';

  final Map<String, int> _balances = <String, int>{};
  JustDatabase? _db;
  World? _world;

  void bindWorld(World world) => _world = world;

  Future<void> initialize() async {
    try {
      _db = await DatabaseManager.open('jge_engine', persist: true);
      await _db!.execute(
        'CREATE TABLE IF NOT EXISTS $_kTable '
        '(currency_id TEXT PRIMARY KEY NOT NULL, '
        'balance INTEGER NOT NULL DEFAULT 0)',
      );
      await _loadState();
    } catch (e) {
      debugPrint('CurrencyManager: database unavailable ($e)');
    }
  }

  void dispose() {}

  int getBalance(String currencyId) => _balances[currencyId] ?? 0;

  Map<String, int> get allBalances => Map<String, int>.unmodifiable(_balances);

  void setBalance(String currencyId, int value) {
    final safe = _safeInt(value);
    final previous = getBalance(currencyId);
    if (safe == previous) return;
    _balances[currencyId] = safe;
    _notify(currencyId, previous, safe);
    unawaited(_save());
  }

  void add(String currencyId, int amount) {
    if (amount <= 0) return;
    setBalance(currencyId, _safeInt(getBalance(currencyId) + amount));
  }

  bool spend(String currencyId, int amount) {
    if (amount <= 0) return true;
    final current = getBalance(currencyId);
    if (current < amount) return false;
    setBalance(currencyId, current - amount);
    return true;
  }

  int _safeInt(num value) => value.clamp(0, 2147483647).toInt();

  void _notify(String currencyId, int previous, int next) {
    _world?.events.fire(
      CurrencyChangedEvent(
        currencyId: currencyId,
        previousBalance: previous,
        newBalance: next,
      ),
    );
  }

  Future<void> _save() async {
    final db = _db;
    if (db == null) return;
    try {
      for (final entry in _balances.entries) {
        final id = _esc(entry.key);
        final balance = _safeInt(entry.value);
        final upd = await db.execute(
          'UPDATE $_kTable SET balance = $balance WHERE currency_id = $id',
        );
        if (upd.affectedRows == 0) {
          await db.execute(
            'INSERT INTO $_kTable (currency_id, balance) '
            'VALUES ($id, $balance)',
          );
        }
      }
    } catch (e) {
      debugPrint('CurrencyManager: save failed ($e)');
    }
  }

  Future<void> _loadState() async {
    final db = _db;
    if (db == null) return;
    try {
      final result = await db.execute(
        'SELECT currency_id, balance FROM $_kTable',
      );
      for (final row in result.rows) {
        final currencyId = row['currency_id'] as String?;
        if (currencyId == null) continue;
        final value = (row['balance'] as num?)?.toInt() ?? 0;
        _balances[currencyId] = _safeInt(value);
      }
    } catch (e) {
      debugPrint('CurrencyManager: load failed ($e)');
    }
  }

  /// Wraps [value] in single quotes, escaping any embedded quotes.
  static String _esc(String value) => "'${value.replaceAll("'", "''")}'";
}

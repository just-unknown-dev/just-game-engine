library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_database/just_database.dart';

import '../../ecs/ecs.dart';
import 'inventory_events.dart';
import 'inventory_item.dart';

class InventoryManager {
  static const String _kTable = 'jge_inventory';

  final Map<String, InventoryItem> _definitions = <String, InventoryItem>{};
  final Map<String, int> _quantities = <String, int>{};

  JustDatabase? _db;
  World? _world;

  void bindWorld(World world) => _world = world;

  void define(InventoryItem item) {
    _definitions[item.id] = item;
    final current = _quantities[item.id] ?? 0;
    _quantities[item.id] = current.clamp(0, item.maxStack);
  }

  Future<void> initialize() async {
    try {
      _db = await DatabaseManager.open('jge_engine', persist: true);
      await _db!.execute(
        'CREATE TABLE IF NOT EXISTS $_kTable '
        '(item_id TEXT PRIMARY KEY NOT NULL, '
        'quantity INTEGER NOT NULL DEFAULT 0)',
      );
      await _loadState();
    } catch (e) {
      debugPrint('InventoryManager: database unavailable ($e)');
    }
  }

  void dispose() {}

  int getQuantity(String itemId) => _quantities[itemId] ?? 0;

  Map<String, int> get allQuantities =>
      Map<String, int>.unmodifiable(_quantities);

  bool addItem(String itemId, {int amount = 1}) {
    if (amount <= 0) return false;
    final maxStack = _definitions[itemId]?.maxStack ?? 999999;
    final current = getQuantity(itemId);
    final next = (current + amount).clamp(0, maxStack);
    if (next == current) return false;
    _quantities[itemId] = next;
    _notify(itemId, current, next);
    unawaited(_saveItem(itemId, next));
    return true;
  }

  bool consumeItem(String itemId, {int amount = 1}) {
    if (amount <= 0) return true;
    final current = getQuantity(itemId);
    if (current < amount) return false;
    final next = current - amount;
    _quantities[itemId] = next;
    _notify(itemId, current, next);
    unawaited(_saveItem(itemId, next));
    return true;
  }

  void setQuantity(String itemId, int value) {
    final maxStack = _definitions[itemId]?.maxStack ?? 999999;
    final next = value.clamp(0, maxStack);
    final current = getQuantity(itemId);
    if (next == current) return;
    _quantities[itemId] = next;
    _notify(itemId, current, next);
    unawaited(_saveItem(itemId, next));
  }

  void _notify(String itemId, int previous, int next) {
    _world?.events.fire(
      InventoryItemChangedEvent(
        itemId: itemId,
        previousQuantity: previous,
        newQuantity: next,
      ),
    );
  }

  Future<void> _saveItem(String itemId, int quantity) async {
    final db = _db;
    if (db == null) return;
    try {
      final id = _esc(itemId);
      final upd = await db.execute(
        'UPDATE $_kTable SET quantity = $quantity WHERE item_id = $id',
      );
      if (upd.affectedRows == 0) {
        await db.execute(
          'INSERT INTO $_kTable (item_id, quantity) VALUES ($id, $quantity)',
        );
      }
    } catch (e) {
      debugPrint('InventoryManager: save failed ($e)');
    }
  }

  Future<void> _loadState() async {
    final db = _db;
    if (db == null) return;
    try {
      final result = await db.execute('SELECT item_id, quantity FROM $_kTable');
      for (final row in result.rows) {
        final itemId = row['item_id'] as String?;
        if (itemId == null) continue;
        final value = (row['quantity'] as num?)?.toInt() ?? 0;
        final maxStack = _definitions[itemId]?.maxStack ?? 999999;
        _quantities[itemId] = value.clamp(0, maxStack);
      }
    } catch (e) {
      debugPrint('InventoryManager: load failed ($e)');
    }
  }

  /// Wraps [value] in single quotes, escaping any embedded quotes.
  static String _esc(String value) => "'${value.replaceAll("'", "''")}'";
}

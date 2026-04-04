/// Core ECS (Entity-Component-System) Architecture
///
/// Provides the foundational types for data-oriented game architecture:
/// - [Component] — pure data, no logic
/// - [Archetype] — cache-friendly dense storage grouped by component set
/// - [Entity] — lightweight handle (ID + component access)
/// - [System] — logic that operates on matching entities
/// - [World] — central manager for entities, systems, and queries
library;

import 'dart:collection';
import 'dart:math';
import 'package:flutter/material.dart';

part 'base/component.dart';
part 'base/archetype.dart';
part 'base/entity.dart';
part 'base/system.dart';
part 'base/world.dart';
part 'base/command_buffer.dart';
part 'base/event_bus.dart';
part 'base/entity_prefab.dart';

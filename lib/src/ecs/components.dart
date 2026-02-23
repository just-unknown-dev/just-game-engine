/// Built-in Components
///
/// Common component types that work with the engine's subsystems.
/// These provide data for position, rendering, physics, etc.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'ecs.dart';
import '../rendering/renderable.dart';

/// Transform component - Position, rotation, and scale
class TransformComponent extends Component {
  /// Entity position
  Offset position;

  /// Entity rotation (radians)
  double rotation;

  /// Entity scale
  double scale;

  /// Create a transform component
  TransformComponent({
    this.position = Offset.zero,
    this.rotation = 0.0,
    this.scale = 1.0,
  });

  /// Move by offset
  void translate(Offset offset) {
    position += offset;
  }

  /// Rotate by angle
  void rotate(double angle) {
    rotation += angle;
  }

  @override
  String toString() =>
      'Transform(pos: $position, rot: $rotation, scale: $scale)';
}

/// Velocity component - Linear velocity
class VelocityComponent extends Component {
  /// Velocity vector
  Offset velocity;

  /// Maximum speed (0 = unlimited)
  double maxSpeed;

  /// Create a velocity component
  VelocityComponent({this.velocity = Offset.zero, this.maxSpeed = 0.0});

  /// Get current speed
  double get speed => velocity.distance;

  /// Set velocity from angle and magnitude
  void setFromAngle(double angle, double magnitude) {
    velocity = Offset(magnitude * math.cos(angle), magnitude * math.sin(angle));
  }

  /// Clamp velocity to max speed
  void clampToMaxSpeed() {
    if (maxSpeed > 0 && speed > maxSpeed) {
      velocity = velocity / speed * maxSpeed;
    }
  }

  @override
  String toString() => 'Velocity($velocity)';
}

/// Renderable component - Links to a Renderable object
class RenderableComponent extends Component {
  /// The renderable object
  Renderable renderable;

  /// Whether to sync transform with entity
  bool syncTransform;

  /// Create a renderable component
  RenderableComponent({required this.renderable, this.syncTransform = true});

  @override
  String toString() => 'Renderable(${renderable.runtimeType})';
}

/// Physics body component - Collision and physics properties
class PhysicsBodyComponent extends Component {
  /// Collision radius
  double radius;

  /// Mass
  double mass;

  /// Restitution (bounciness, 0-1)
  double restitution;

  /// Drag coefficient
  double drag;

  /// Is this a static body (doesn't move)
  bool isStatic;

  /// Collision layer (for filtering)
  int layer;

  /// Layers this body can collide with
  int collisionMask;

  /// Create a physics body component
  PhysicsBodyComponent({
    required this.radius,
    this.mass = 1.0,
    this.restitution = 0.8,
    this.drag = 0.98,
    this.isStatic = false,
    this.layer = 1,
    this.collisionMask = -1, // All layers
  });

  /// Check if can collide with layer
  bool canCollideWith(int otherLayer) {
    return (collisionMask & otherLayer) != 0;
  }

  @override
  String toString() => 'PhysicsBody(r: $radius, m: $mass, static: $isStatic)';
}

/// Tag component - Simple marker component
class TagComponent extends Component {
  /// Tag name
  final String tag;

  /// Create a tag component
  TagComponent(this.tag);

  @override
  String toString() => 'Tag($tag)';
}

/// Lifetime component - Entity that expires after time
class LifetimeComponent extends Component {
  /// Time remaining (seconds)
  double timeRemaining;

  /// Initial lifetime
  final double initialLifetime;

  /// Create a lifetime component
  LifetimeComponent(this.initialLifetime) : timeRemaining = initialLifetime;

  /// Check if expired
  bool get isExpired => timeRemaining <= 0;

  /// Get progress (0 to 1)
  double get progress => 1.0 - (timeRemaining / initialLifetime);

  /// Update lifetime
  void update(double deltaTime) {
    timeRemaining -= deltaTime;
  }

  @override
  String toString() => 'Lifetime($timeRemaining / $initialLifetime)';
}

/// Health component - HP system
class HealthComponent extends Component {
  /// Current health
  double health;

  /// Maximum health
  double maxHealth;

  /// Is entity invulnerable
  bool isInvulnerable;

  /// Create a health component
  HealthComponent({
    required this.maxHealth,
    double? health,
    this.isInvulnerable = false,
  }) : health = health ?? maxHealth;

  /// Check if alive
  bool get isAlive => health > 0;

  /// Check if dead
  bool get isDead => health <= 0;

  /// Get health percentage (0 to 1)
  double get healthPercent => (health / maxHealth).clamp(0.0, 1.0);

  /// Damage the entity
  void damage(double amount) {
    if (!isInvulnerable) {
      health = (health - amount).clamp(0.0, maxHealth);
    }
  }

  /// Heal the entity
  void heal(double amount) {
    health = (health + amount).clamp(0.0, maxHealth);
  }

  /// Reset to full health
  void reset() {
    health = maxHealth;
  }

  @override
  String toString() => 'Health($health / $maxHealth)';
}

/// Parent-child component - Hierarchy relationships
class ParentComponent extends Component {
  /// Parent entity ID (null if root)
  EntityId? parentId;

  /// Local offset from parent
  Offset localOffset;

  /// Local rotation offset
  double localRotation;

  /// Create a parent component
  ParentComponent({
    this.parentId,
    this.localOffset = Offset.zero,
    this.localRotation = 0.0,
  });

  @override
  String toString() => 'Parent($parentId)';
}

/// Children component - Tracks child entities
class ChildrenComponent extends Component {
  /// List of child entity IDs
  final List<EntityId> childIds = [];

  /// Add a child
  void addChild(EntityId id) {
    if (!childIds.contains(id)) {
      childIds.add(id);
    }
  }

  /// Remove a child
  void removeChild(EntityId id) {
    childIds.remove(id);
  }

  @override
  String toString() => 'Children(${childIds.length})';
}

/// Input component - Tracks input state for an entity
class InputComponent extends Component {
  /// Movement direction (-1 to 1 for each axis)
  Offset moveDirection = Offset.zero;

  /// Action buttons state
  final Map<String, bool> buttons = {};

  /// Check if button is pressed
  bool isButtonPressed(String button) => buttons[button] ?? false;

  /// Set button state
  void setButton(String button, bool pressed) {
    buttons[button] = pressed;
  }

  @override
  String toString() =>
      'Input(move: $moveDirection, buttons: ${buttons.length})';
}

/// Animation state component - Tracks current animation
class AnimationStateComponent extends Component {
  /// Current animation name
  String currentAnimation;

  /// Animation time
  double time = 0.0;

  /// Is animation playing
  bool isPlaying = true;

  /// Should loop
  bool loop;

  /// Create animation state component
  AnimationStateComponent({required this.currentAnimation, this.loop = true});

  /// Play animation
  void play(String animation, {bool restart = false}) {
    if (currentAnimation != animation || restart) {
      currentAnimation = animation;
      time = 0.0;
      isPlaying = true;
    }
  }

  /// Stop animation
  void stop() {
    isPlaying = false;
  }

  @override
  String toString() => 'AnimationState($currentAnimation, t: $time)';
}

/// Sprite component - Sprite rendering data
class SpriteComponent extends Component {
  /// Sprite asset path
  String spritePath;

  /// Current frame (for sprite sheets)
  int frame;

  /// Flip horizontal
  bool flipX;

  /// Flip vertical
  bool flipY;

  /// Tint color
  Color? tint;

  /// Create sprite component
  SpriteComponent({
    required this.spritePath,
    this.frame = 0,
    this.flipX = false,
    this.flipY = false,
    this.tint,
  });

  @override
  String toString() => 'Sprite($spritePath, frame: $frame)';
}

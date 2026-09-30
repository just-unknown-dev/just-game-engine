/// Framing several things at once, and switching shots by where the player is.
library;

import 'package:flutter/painting.dart' show Offset, Rect;

import '../../../ecs/ecs.dart';

/// Who a target group keeps in shot: one entity, or every entity with a tag.
class CameraGroupMember {
  CameraGroupMember({
    EntityTarget target = EntityTarget.none,
    @Deprecated('Use target: EntityTarget.name(…).') String? name,
    @Deprecated('Use target: EntityTarget.tag(…).') String? tag,
    this.weight = 1.0,
    this.radius = 0.0,
  }) : target = name != null || tag != null
           ? EntityTarget.fromNameOrTag(name ?? '', tag ?? '')
           : target;

  /// Reads [toJson]'s shape, and the old `{name, tag}` one.
  factory CameraGroupMember.fromJson(Map<Object?, Object?> json) =>
      CameraGroupMember(
        target: json.containsKey('target')
            ? EntityTarget.fromJson(json['target'])
            : EntityTarget.fromNameOrTag(
                json['name'] as String? ?? '',
                json['tag'] as String? ?? '',
              ),
        weight: (json['weight'] as num?)?.toDouble() ?? 1.0,
        radius: (json['radius'] as num?)?.toDouble() ?? 0.0,
      );

  /// The entity by name, or every entity with a tag — one member, tag
  /// `player`, frames all the players however many have joined.
  EntityTarget target;

  /// The name [target] names, or empty.
  @Deprecated('Use target.')
  String get name => target.isName ? target.value : '';

  /// The tag [target] names, or empty.
  @Deprecated('Use target.')
  String get tag => target.isTag ? target.value : '';

  @Deprecated('Use target = EntityTarget.name(…).')
  set name(String value) => target = target.afterSettingName(value);

  @Deprecated('Use target = EntityTarget.tag(…).')
  set tag(String value) => target = target.afterSettingTag(value);

  /// How hard it pulls the centre. `0` keeps it in shot without pulling.
  double weight;

  /// How much room it needs around its position, in world units.
  double radius;

  Map<String, dynamic> toJson() => {
    'target': target.toJson(),
    'weight': weight,
    'radius': radius,
  };
}

/// Turns its entity into the weighted centre of several others.
///
/// The group is a *target*, not a camera: `CameraTargetGroupSystem` moves
/// this entity to the centre of its members each frame, so any virtual camera
/// frames the whole party by following this entity by name. Add a
/// [CameraGroupFramingComponent] to that camera to zoom out as they spread.
class CameraTargetGroupComponent extends Component {
  CameraTargetGroupComponent({List<CameraGroupMember>? members})
    : members = members ?? [];

  List<CameraGroupMember> members;

  /// The box around every member found this frame, radii included. Runtime
  /// only; empty until the system has run.
  Rect bounds = Rect.zero;

  /// How many members were found this frame.
  int resolved = 0;

  @override
  String toString() => 'CameraTargetGroup(${members.length})';
}

/// Body: sets the lens so a followed target group fits the view.
class CameraGroupFramingComponent extends Component {
  CameraGroupFramingComponent({
    this.padding = 0.25,
    this.minZoom = 0.4,
    this.maxZoom = 1.5,
    this.zoomDamping = 0.6,
  });

  /// Empty space around the group, as a fraction of its size.
  double padding;

  /// As far out as the lens may go — the group may leave the view past this.
  double minZoom;

  /// As close as it may go, however tightly the group huddles.
  double maxZoom;

  /// Seconds for the lens to settle.
  double zoomDamping;

  @override
  String toString() => 'CameraGroupFraming($minZoom–$maxZoom)';
}

/// What a trigger does to its camera while the target is inside.
enum CameraTriggerMode {
  /// The camera is enabled inside and disabled outside: a shot that exists
  /// only for one room.
  enableWhileInside,

  /// The camera's priority is raised by `amount` inside, and put back
  /// outside: a shot that is always a candidate but wins here.
  boostPriority,
}

/// A rectangle, centred on its entity, that switches a virtual camera by
/// whether a target is inside it.
class CameraTriggerComponent extends Component {
  CameraTriggerComponent({
    this.width = 640,
    this.height = 360,
    EntityTarget target = const EntityTarget.tag('player'),
    @Deprecated('Use target: EntityTarget.name(…).') String? targetName,
    @Deprecated('Use target: EntityTarget.tag(…).') String? targetTag,
    this.cameraName = '',
    this.mode = CameraTriggerMode.enableWhileInside,
    this.amount = 10,
    this.oneShot = false,
  }) : target = targetName != null || targetTag != null
           ? EntityTarget.fromNameOrTag(targetName ?? '', targetTag ?? '')
           : target;

  double width;
  double height;

  /// Who sets it off: one entity by name, or any entity with a tag.
  EntityTarget target;

  /// The name [target] names, or empty.
  @Deprecated('Use target.')
  String get targetName => target.isName ? target.value : '';

  /// The tag [target] names, or empty.
  @Deprecated('Use target.')
  String get targetTag => target.isTag ? target.value : '';

  @Deprecated('Use target = EntityTarget.name(…).')
  set targetName(String value) => target = target.afterSettingName(value);

  @Deprecated('Use target = EntityTarget.tag(…).')
  set targetTag(String value) => target = target.afterSettingTag(value);

  /// The camera it switches. Empty means the virtual camera on this same
  /// entity — a zone that carries its own shot.
  String cameraName;

  CameraTriggerMode mode;

  /// Priority added in [CameraTriggerMode.boostPriority].
  int amount;

  /// Once entered, it stays switched: a door that does not reopen.
  bool oneShot;

  /// Whether the target was inside last frame. Runtime only.
  bool isInside = false;

  /// Whether a priority boost is in force. Runtime only.
  bool isBoosted = false;

  /// Whether a one-shot trigger has gone off. Runtime only.
  bool hasFired = false;

  Rect regionAt(Offset centre) =>
      Rect.fromCenter(center: centre, width: width, height: height);

  @override
  String toString() => 'CameraTrigger($width×$height, ${mode.name})';
}

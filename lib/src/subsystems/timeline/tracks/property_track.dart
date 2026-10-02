/// A track that animates one field of one component — any field a
/// component's definition describes, on any entity.
library;

import '../../../ecs/ecs.dart';
import '../../../ecs/serialization/component_definition.dart';
import '../../../ecs/serialization/component_definition_registry.dart';
import '../../../ecs/serialization/field_type.dart';
import '../timeline_keys.dart';
import '../timeline_track.dart';

/// How a property track's keys are read.
enum PropertyTrackMode {
  /// The keys are the value.
  absolute,

  /// The keys are offsets from the value the field had when the timeline
  /// started playing — so one "slide up 64" timeline opens every door,
  /// wherever each one stands. Only numbers can be relative.
  relative,
}

/// A field, reached through its component's definition in the field's saved
/// (JSON) form. That form is the same for every field type — a number, a
/// bool, a string, an ARGB int, or a map of numbers like `{x, y}` — which is
/// why one track kind animates them all, a package's own types included.
class PropertyAccess {
  PropertyAccess._(this.component, this.field, this.channel);

  /// The component whose field this reaches.
  final Component component;

  /// The field, as the component's definition describes it.
  final SchemaField field;

  /// The key inside a map-valued field (`x`, `y`, `z`, `dx`, `dy`); empty
  /// for a field that is one value.
  final String channel;

  /// The field kinds whose saved form is a map of numbers, and their keys —
  /// for kinds that do not name them themselves ([FieldType.channels]).
  static const Map<String, List<String>> channelsByKind = {
    'vector2': ['x', 'y'],
    'vector3': ['x', 'y', 'z'],
    'offset': ['dx', 'dy'],
  };

  /// The field kinds a track can animate as one value.
  static const Set<String> scalarKinds = {
    'decimal',
    'integer',
    'boolean',
    'color',
    'text',
    'assetRef',
    'entityRef',
    'enumeration',
    'enum',
  };

  /// Whether [field] can be keyed at all.
  static bool canAnimate(SchemaField field) =>
      field.write != null &&
      (field.kind.channels.isNotEmpty ||
          channelsByKind.containsKey(field.kind.id) ||
          scalarKinds.contains(field.kind.id) ||
          field.kind is EnumFieldType);

  /// The channels [field] is keyed by; `['']` for a single value.
  static List<String> channelsOf(SchemaField field) {
    final own = field.kind.channels;
    if (own.isNotEmpty) return own;
    return channelsByKind[field.kind.id] ?? const [''];
  }

  /// Whether the field holds an ARGB colour (its kind is `color`).
  bool get isColor => field.kind.id == 'color';

  /// Whether the field holds an int (its kind is `integer`); [write]
  /// rounds a number to one.
  bool get isInteger => field.kind.id == 'integer';

  /// The component of [entity] saved as [componentType], and its [fieldName]
  /// — or null when the entity has no such component, the type no such
  /// field, or the field cannot be written.
  static PropertyAccess? of(
    Entity entity,
    String componentType,
    String fieldName, [
    String channel = '',
    ComponentDefinitionRegistry? registry,
  ]) {
    final definitions = registry ?? entity.world?.context.definitions;
    if (definitions == null) return null;
    final wanted = definitions.definitionByType(componentType);
    if (wanted == null) return null;
    for (final component in entity.components) {
      // The definition the component itself resolves to, so a subclass with
      // its own definition is not mistaken for its base.
      if (definitions.definitionFor(component)?.type != wanted.type) continue;
      for (final field in wanted.fields) {
        if (field.name != fieldName) continue;
        if (field.write == null) return null;
        return PropertyAccess._(component, field, channel);
      }
      return null;
    }
    return null;
  }

  /// The value now, in key form: a num, bool, String, ARGB int — or null
  /// when the field is unset or [channel] is not in it.
  Object? read() {
    final saved = field.encodeFrom(component);
    if (channel.isEmpty) return saved;
    return saved is Map ? saved[channel] : null;
  }

  /// Writes [value], in key form, into the field through its definition. A
  /// number is rounded for an integer field, and read as `>= 0.5` for a
  /// boolean one. On a [channel] the others keep their values; nothing is
  /// written when the field is not a map or the channel already holds it.
  void write(Object value) {
    Object out = value;
    if (isInteger && value is num) out = value.round();
    if (field.kind.id == 'boolean' && value is num) out = value >= 0.5;
    if (channel.isEmpty) {
      field.decodeInto(component, out);
      return;
    }
    final saved = field.encodeFrom(component);
    if (saved is! Map) return;
    // One channel of several: the others keep their values. A channel
    // that already holds the value leaves the field alone.
    if (saved[channel] == out) return;
    if (_ownsEncoding && out is num) {
      // The engine's own map kinds encode into a fresh map of doubles every
      // time: change it in place rather than copying it.
      saved[channel] = out.toDouble();
      field.decodeInto(component, saved);
      return;
    }
    field.decodeInto(component, {...saved, channel: out});
  }

  /// Whether [field]'s kind is one of the engine's map kinds, whose saved
  /// form is a new, writable map of doubles each time it is read.
  late final bool _ownsEncoding = _freshMapKinds.contains(field.kind.id);

  static const Set<String> _freshMapKinds = {
    'vector2',
    'vector3',
    'euler',
    'offset',
  };
}

/// Animates one field of one component on the bound entity along a
/// [curve] of keys. The field is named by saved names — [component],
/// [field], and [channel] for one number of a map-valued field — so the
/// track fits any entity that has it.
class PropertyTrack extends TimelineTrack {
  /// A track keying [field] of the component saved as [component]:
  /// absolute, not a colour, and with no keys unless given.
  PropertyTrack({
    required this.component,
    required this.field,
    this.channel = '',
    this.mode = PropertyTrackMode.absolute,
    KeyCurve? curve,
    this.isColor = false,
    super.name,
    super.binding,
    super.muted,
    super.locked,
  }) : curve = curve ?? KeyCurve.empty;

  /// `property`: the `kind` this track is saved as in a `.timeline.json`,
  /// and the id [TimelineTrackKinds] reads it by.
  static const String kindId = 'property';

  /// The component's saved type name, e.g. `TransformComponent`.
  final String component;

  /// The field's name in the component's definition, e.g. `position`.
  final String field;

  /// See [PropertyAccess.channel].
  final String channel;

  /// Whether the keys are the value or offsets from it; see [isRelative].
  final PropertyTrackMode mode;

  /// The keys, and the value between them.
  final KeyCurve curve;

  /// The keys are ARGB colours, blended channel by channel. Saved with the
  /// track so it plays right even where the definition is not registered
  /// yet.
  final bool isColor;

  @override
  String get kind => kindId;

  @override
  double get end => curve.end;

  /// `TransformComponent.position.x` — what the track animates, and what
  /// tells two tracks apart.
  String get path => '$component.$field${channel.isEmpty ? '' : '.$channel'}';

  @override
  String get summary => path;

  /// Whether the keys are added to the field's value as a play first finds
  /// it: [PropertyTrackMode.relative] on a track that is not a colour one.
  bool get isRelative => mode == PropertyTrackMode.relative && !isColor;

  @override
  TrackRunner createRunner() => PropertyTrackRunner(this);

  /// A copy with the keys, the mode or the shared properties replaced.
  /// What it animates — component, field, channel, colour — stays.
  PropertyTrack copyWith({
    KeyCurve? curve,
    PropertyTrackMode? mode,
    String? name,
    TrackBinding? binding,
    bool? muted,
    bool? locked,
  }) => PropertyTrack(
    component: component,
    field: field,
    channel: channel,
    mode: mode ?? this.mode,
    curve: curve ?? this.curve,
    isColor: isColor,
    name: name ?? this.name,
    binding: binding ?? this.binding,
    muted: muted ?? this.muted,
    locked: locked ?? this.locked,
  );

  @override
  TimelineTrack withBase({
    String? name,
    TrackBinding? binding,
    bool? muted,
    bool? locked,
  }) => copyWith(name: name, binding: binding, muted: muted, locked: locked);

  @override
  Map<String, dynamic> bodyToJson() => {
    'component': component,
    'field': field,
    if (channel.isNotEmpty) 'channel': channel,
    if (mode != PropertyTrackMode.absolute) 'mode': mode.name,
    if (isColor) 'color': true,
    'keys': curve.toJson(),
  };

  /// Reads a saved track of this kind ([toJson]'s shape: `component`,
  /// `field`, `channel`, `mode`, `color` and `keys` beside the shared
  /// keys); a missing key takes its default.
  factory PropertyTrack.fromJson(Map<String, dynamic> json) => PropertyTrack(
    component: json['component'] as String? ?? '',
    field: json['field'] as String? ?? '',
    channel: json['channel'] as String? ?? '',
    mode:
        PropertyTrackMode.values.asNameMap()[json['mode']] ??
        PropertyTrackMode.absolute,
    isColor: json['color'] == true,
    curve: KeyCurve.fromJson(json['keys']),
    name: json['name'] as String? ?? '',
    binding: TrackBinding.fromJson(json['binding']),
    muted: json['muted'] == true,
    locked: json['locked'] == true,
  );
}

/// The running half of a [PropertyTrack]: finds the field on the bound
/// entity — again when the entity or its components change — and writes
/// the curve's value there on every apply.
class PropertyTrackRunner extends TrackRunner {
  /// A runner for [track]; [PropertyTrack.createRunner] makes one per
  /// playback.
  PropertyTrackRunner(this.track);

  /// The track this runs.
  final PropertyTrack track;

  Entity? _entity;
  PropertyAccess? _access;

  // The world's structure when [_access] was last known to be on [_entity]:
  // until a component is added or removed, it still is.
  int _checkedAt = -1;

  /// What a relative track's keys are added to: the field's value when this
  /// play first reached it. Null before then, and for an absolute track.
  ///
  /// An editor previewing a timeline sets it, since it already knows the
  /// value the field had before it started scrubbing.
  double? base;

  @override
  void begin(TimelineContext context) {
    _entity = null;
    _access = null;
    base = null;
  }

  @override
  void apply(TimelineContext context, double time) {
    if (track.curve.isEmpty) return;
    final entity = context.resolve(track.binding);
    if (entity == null) return;
    final version = context.world.structureVersion;
    if (!identical(entity, _entity) ||
        _access == null ||
        (version != _checkedAt &&
            !entity.components.contains(_access!.component))) {
      _entity = entity;
      _access = PropertyAccess.of(
        entity,
        track.component,
        track.field,
        track.channel,
      );
      base = null;
      final found = _access;
      if (found != null) context.willWrite(found.component, found.field);
    }
    _checkedAt = version;
    final access = _access;
    if (access == null) return;

    final value = track.curve.valueAt(
      time,
      isColor: track.isColor,
      easings: context.world.context.easings,
    );
    if (value == null) return;
    if (track.isRelative && value is num) {
      final from = base ??= (access.read() as num?)?.toDouble() ?? 0.0;
      access.write(from + value);
    } else {
      access.write(value);
    }
  }
}

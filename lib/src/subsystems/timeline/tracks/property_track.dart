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

  final Component component;
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

  bool get isColor => field.kind.id == 'color';
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
    final definitions = registry ?? ComponentDefinitionRegistry.instance;
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
    field.decodeInto(component, {...saved, channel: out});
  }
}

class PropertyTrack extends TimelineTrack {
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

  static const String kindId = 'property';

  /// The component's saved type name, e.g. `TransformComponent`.
  final String component;
  final String field;

  /// See [PropertyAccess.channel].
  final String channel;
  final PropertyTrackMode mode;
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

  bool get isRelative => mode == PropertyTrackMode.relative && !isColor;

  @override
  TrackRunner createRunner() => PropertyTrackRunner(this);

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

class PropertyTrackRunner extends TrackRunner {
  PropertyTrackRunner(this.track);

  final PropertyTrack track;

  Entity? _entity;
  PropertyAccess? _access;
  double? _base;

  /// What a relative track's keys are added to: the field's value when this
  /// play first reached it. Null before then, and for an absolute track.
  double? get base => _base;

  /// An editor previewing a timeline already knows the value the field had
  /// before it started scrubbing.
  set base(double? value) => _base = value;

  @override
  void begin(TimelineContext context) {
    _entity = null;
    _access = null;
    _base = null;
  }

  @override
  void apply(TimelineContext context, double time) {
    if (track.curve.isEmpty) return;
    final entity = context.resolve(track.binding);
    if (entity == null) return;
    if (!identical(entity, _entity) ||
        _access == null ||
        !entity.components.contains(_access!.component)) {
      _entity = entity;
      _access = PropertyAccess.of(
        entity,
        track.component,
        track.field,
        track.channel,
      );
      _base = null;
      final found = _access;
      if (found != null) context.willWrite(found.component, found.field);
    }
    final access = _access;
    if (access == null) return;

    final value = track.curve.valueAt(time, isColor: track.isColor);
    if (value == null) return;
    if (track.isRelative && value is num) {
      final base = _base ??= (access.read() as num?)?.toDouble() ?? 0.0;
      access.write(base + value);
    } else {
      access.write(value);
    }
  }
}

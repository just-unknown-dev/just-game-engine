/// The tags a project knows about, and the file they are kept in.
library;

import 'dart:ui' show Color;

import '../ecs.dart' show TagNames;
import '../../foundation/unsupported_format_version.dart';

/// One tag a project knows: its name, and how an editor shows it.
class TagDefinition {
  /// The tag called [name]. By default it has no colour or description and
  /// is a person's own, not declared by a package ([declaredBy]).
  const TagDefinition(
    this.name, {
    this.color,
    this.description = '',
    this.declaredBy,
  });

  /// The tag itself, as entities carry it and targets name it.
  final String name;

  /// The chip colour; [TagLibrary.colorFor] picks one when unset.
  final Color? color;

  /// What the tag is for, for an editor to show; empty for nothing.
  final String description;

  /// The package whose code relies on this tag — `'just_game_engine'` — or
  /// null for one a person made. Code finds a declared tag by its name, so
  /// an editor does not let one be renamed or deleted.
  final String? declaredBy;

  /// Whether code relies on the tag (see [declaredBy]).
  bool get isDeclared => declaredBy != null;

  /// A copy with the values given replaced; [clearColor] removes the colour
  /// instead. [declaredBy] is always kept.
  TagDefinition copyWith({
    String? name,
    Color? color,
    bool clearColor = false,
    String? description,
  }) => TagDefinition(
    name ?? this.name,
    color: clearColor ? null : (color ?? this.color),
    description: description ?? this.description,
    declaredBy: declaredBy,
  );

  /// What the project file keeps. [declaredBy] is not saved: it comes from
  /// the code that declares the tag, every time.
  Map<String, dynamic> toJson() => {
    'name': name,
    if (color != null) 'color': color!.toARGB32(),
    if (description.isNotEmpty) 'description': description,
  };

  /// Reads what [toJson] wrote, or a bare name string; the name is
  /// trimmed. Null for anything with no name. Never marked declared.
  static TagDefinition? fromJson(Object? json) {
    if (json is String && json.trim().isNotEmpty) {
      return TagDefinition(json.trim());
    }
    if (json is! Map) return null;
    final name = (json['name'] as String? ?? '').trim();
    if (name.isEmpty) return null;
    final color = json['color'];
    return TagDefinition(
      name,
      color: color is int ? Color(color) : null,
      description: json['description'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TagDefinition &&
      other.name == name &&
      other.color == color &&
      other.description == description &&
      other.declaredBy == declaredBy;

  @override
  int get hashCode => Object.hash(name, color, description, declaredBy);

  @override
  String toString() => 'TagDefinition($name)';
}

/// The project's tags, in the order they are listed. Immutable: every change
/// returns a new library.
///
/// Kept in [defaultPath]. The file holds the tags people made and what they
/// set on declared ones (a colour, a description); which tags are declared
/// is never read from it — packages say so in code, and [withDeclared]
/// merges that in.
class TagLibrary {
  /// A library of [tags], in order; blank names are dropped, and of two
  /// with one name only the first is kept.
  TagLibrary([Iterable<TagDefinition> tags = const []])
    : _tags = List.unmodifiable(_dedupe(tags));

  /// The file format [toJson] writes; [fromJson] refuses newer ones.
  static const int formatVersion = 1;

  /// Where a project keeps its tags.
  static const String defaultPath = 'assets/project/tags.json';

  /// A library with no tags.
  static final TagLibrary empty = TagLibrary();

  final List<TagDefinition> _tags;

  /// Every tag, in list order. Unmodifiable.
  List<TagDefinition> get tags => _tags;

  /// Every tag's name, in list order.
  Iterable<String> get names => _tags.map((t) => t.name);

  /// Whether the library lists no tags.
  bool get isEmpty => _tags.isEmpty;

  /// How many tags it lists.
  int get length => _tags.length;

  /// Whether a tag called [name] is listed (names match exactly).
  bool contains(String name) => this[name] != null;

  /// The tag called exactly [name], or null.
  TagDefinition? operator [](String name) {
    for (final t in _tags) {
      if (t.name == name) return t;
    }
    return null;
  }

  /// [name]'s chip colour: its own, or one picked from its name.
  Color colorOf(String name) => this[name]?.color ?? colorFor(name);

  /// The listed tag that [name] is a near duplicate of — `Players` when
  /// `player` exists — or null.
  String? nearDuplicateOf(String name) {
    for (final existing in names) {
      if (TagNames.areNearDuplicates(name, existing)) return existing;
    }
    return null;
  }

  /// [tag] added at the end, or put in place of the one with its name.
  /// A declared tag keeps being declared.
  TagLibrary put(TagDefinition tag) {
    final i = _tags.indexWhere((t) => t.name == tag.name);
    if (i < 0) return TagLibrary([..._tags, tag]);
    final declaredBy = _tags[i].declaredBy;
    final next = [..._tags];
    next[i] = TagDefinition(
      tag.name,
      color: tag.color,
      description: tag.description,
      declaredBy: tag.declaredBy ?? declaredBy,
    );
    return TagLibrary(next);
  }

  /// Without [name].
  TagLibrary remove(String name) =>
      TagLibrary(_tags.where((t) => t.name != name));

  /// [from] renamed [to], where it was in the list. If [to] already exists
  /// the two merge, keeping [to]'s look.
  TagLibrary rename(String from, String to) {
    final old = this[from];
    if (old == null || from == to) return this;
    if (contains(to)) return remove(from);
    return TagLibrary([
      for (final t in _tags) t.name == from ? t.copyWith(name: to) : t,
    ]);
  }

  /// [declared] merged in: a declared tag the file lists keeps its place and
  /// the file's colour and description (falling back to the declaration's),
  /// and is marked declared; one it does not list is added at the end.
  TagLibrary withDeclared(Iterable<TagDefinition> declared) {
    final byName = <String, TagDefinition>{};
    for (final d in declared) {
      byName.putIfAbsent(d.name, () => d);
    }
    final out = <TagDefinition>[
      for (final t in _tags)
        if (byName[t.name] case final d?)
          TagDefinition(
            t.name,
            color: t.color ?? d.color,
            description: t.description.isNotEmpty
                ? t.description
                : d.description,
            declaredBy: d.declaredBy ?? 'code',
          )
        else
          t,
    ];
    for (final d in byName.values) {
      if (!out.any((t) => t.name == d.name)) {
        out.add(
          d.declaredBy == null
              ? TagDefinition(
                  d.name,
                  color: d.color,
                  description: d.description,
                  declaredBy: 'code',
                )
              : d,
        );
      }
    }
    return TagLibrary(out);
  }

  /// [names] added at the end, as plain tags, where missing — for tags a
  /// project's scenes already use when it first gets a tag file.
  TagLibrary withNames(Iterable<String> names) {
    final missing = [
      for (final n in TagNames.normalize(names))
        if (!contains(n)) TagDefinition(n),
    ];
    return missing.isEmpty ? this : TagLibrary([..._tags, ...missing]);
  }

  /// The tag file: `{version, tags}`, each tag as [TagDefinition.toJson]
  /// writes it.
  Map<String, dynamic> toJson() => {
    'version': formatVersion,
    'tags': [for (final t in _tags) t.toJson()],
  };

  /// Reads what [toJson] wrote (or a bare list of tags, the oldest form).
  ///
  /// Throws [UnsupportedFormatVersionException] for a file saved in a
  /// format newer than [formatVersion].
  static TagLibrary fromJson(Object? json) {
    if (json is Map) {
      final version = (json['version'] as num?)?.toInt() ?? formatVersion;
      if (version > formatVersion) {
        throw UnsupportedFormatVersionException(
          'tag library',
          version,
          formatVersion,
        );
      }
    }
    final list = json is Map ? json['tags'] : json;
    if (list is! List) return empty;
    return TagLibrary([for (final item in list) ?TagDefinition.fromJson(item)]);
  }

  /// A colour for a tag with none of its own: picked from its name, so a
  /// tag keeps its colour from one run to the next.
  static Color colorFor(String name) {
    var h = 0;
    for (final unit in name.codeUnits) {
      h = (h * 31 + unit) & 0x7fffffff;
    }
    return _palette[h % _palette.length];
  }

  static const List<Color> _palette = [
    Color(0xFF4FC3F7),
    Color(0xFFFF8A65),
    Color(0xFF81C784),
    Color(0xFFBA68C8),
    Color(0xFFFFD54F),
    Color(0xFF4DB6AC),
    Color(0xFFF06292),
    Color(0xFF9575CD),
    Color(0xFFAED581),
    Color(0xFF7986CB),
  ];

  static List<TagDefinition> _dedupe(Iterable<TagDefinition> tags) {
    final seen = <String>{};
    return [
      for (final t in tags)
        if (t.name.trim().isNotEmpty && seen.add(t.name)) t,
    ];
  }

  @override
  bool operator ==(Object other) {
    if (other is! TagLibrary || other._tags.length != _tags.length) {
      return false;
    }
    for (var i = 0; i < _tags.length; i++) {
      if (other._tags[i] != _tags[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_tags);
}

/// Tags the engine's own code looks for.
abstract final class EngineTags {
  /// Whoever is being played. Cameras, trigger zones, checkpoints and
  /// dialogue look for it unless told otherwise.
  static const String player = 'player';

  /// The tags the engine declares — just [player] — as merged into a
  /// project's library by [TagLibrary.withDeclared].
  static const List<TagDefinition> declared = [
    TagDefinition(
      player,
      color: Color(0xFF4FC3F7),
      description:
          'Whoever is being played. Cameras, triggers and checkpoints look '
          'for it unless told otherwise.',
      declaredBy: 'just_game_engine',
    ),
  ];
}

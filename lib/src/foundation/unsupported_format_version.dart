/// The error for a saved file newer than this engine can read.
library;

/// A saved file declares a format version newer than this engine reads.
///
/// Thrown instead of loading such a file as though it were current: a newer
/// format may store things this engine would quietly misread or drop — and
/// a file loaded that way and saved again loses them for good.
///
/// Scenes (`SceneFormat`), the project tag library (`TagLibrary`) and the
/// engine's other versioned files throw it. It is a [FormatException], so
/// code already catching those for a broken file catches this too.
///
/// ```dart
/// try {
///   SceneLoader.load(world, json);
/// } on UnsupportedFormatVersionException catch (e) {
///   print(e.message); // "This scene was saved in format v9, ..."
/// }
/// ```
class UnsupportedFormatVersionException implements FormatException {
  /// [kind] names the file for a person — `'scene'`, `'tag library'`,
  /// `'timeline'`; [found] is the version it declares, [supported] the
  /// newest this engine reads.
  const UnsupportedFormatVersionException(
    this.kind,
    this.found,
    this.supported, {
    this.source,
  });

  /// What sort of file it is, as a person would say it: `'scene'`.
  final String kind;

  /// The format version the file declares.
  final int found;

  /// The newest format version this engine reads.
  final int supported;

  /// Where the file came from — a path or a name — when the thrower knows.
  @override
  final Object? source;

  @override
  String get message =>
      'This $kind was saved in format v$found, but this version of '
      'just_game_engine reads formats up to v$supported. Update '
      'just_game_engine to open it.';

  @override
  int? get offset => null;

  @override
  String toString() =>
      'UnsupportedFormatVersionException: $message'
      '${source == null ? '' : ' ($source)'}';
}

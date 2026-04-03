part of '../effect_system.dart';

/// Compact binary codec for [EffectSnapshot].
///
/// Produces a smaller payload than JSON — useful for production multiplayer
/// transport layers where bandwidth matters. The format is versioned so
/// future changes remain detectable.
///
/// ### Wire format (little-endian)
///
/// ```
/// Header:
///   [1 byte]  version   (currently 0x01)
///   [4 bytes] tick      (int32)
///   [4 bytes] entityCount (int32)
///
/// Per entity:
///   [4 bytes] entityId   (int32)
///   [4 bytes] effectCount (int32)
///
/// Per effect:
///   [4 bytes] startTick      (int32)
///   [4 bytes] processedElapsed (int32)
///   JSON-encoded effect map encoded as UTF-8 string:
///     [4 bytes] byteLength (int32)
///     [N bytes] UTF-8 JSON bytes
/// ```
///
/// The effect payload reuses the JSON serialiser for simplicity and forward-
/// compatibility. Switch to a fully binary per-type encoding if profiling
/// shows the JSON overhead is significant.
abstract final class EffectBinaryCodec {
  static const int _version = 0x01;

  /// Encode [snapshot] to a compact byte array.
  static Uint8List encode(EffectSnapshot snapshot) {
    final w = _ByteWriter();
    w.writeUint8(_version);
    w.writeInt32(snapshot.tick);
    w.writeInt32(snapshot.entityEffects.length);

    for (final entry in snapshot.entityEffects.entries) {
      w.writeInt32(entry.key); // entityId
      w.writeInt32(entry.value.length); // effectCount
      for (final effectMap in entry.value) {
        w.writeInt32(effectMap['startTick'] as int);
        w.writeInt32(effectMap['processedElapsed'] as int);
        // Encode the effect JSON blob.
        final effectJson = jsonEncode(effectMap['effect']);
        final effectBytes = utf8.encode(effectJson);
        w.writeInt32(effectBytes.length);
        w.writeBytes(effectBytes);
      }
    }
    return w.build();
  }

  /// Decode a byte array produced by [encode] back to an [EffectSnapshot].
  ///
  /// Throws [FormatException] if the version byte does not match.
  static EffectSnapshot decode(Uint8List bytes) {
    final r = _ByteReader(bytes);
    final version = r.readUint8();
    if (version != _version) {
      throw FormatException(
        'EffectBinaryCodec: unsupported version $version (expected $_version)',
      );
    }

    final tick = r.readInt32();
    final entityCount = r.readInt32();
    final entityEffects = <EntityId, List<Map<String, dynamic>>>{};

    for (int e = 0; e < entityCount; e++) {
      final entityId = r.readInt32();
      final effectCount = r.readInt32();
      final effects = <Map<String, dynamic>>[];

      for (int i = 0; i < effectCount; i++) {
        final startTick = r.readInt32();
        final processedElapsed = r.readInt32();
        final byteLength = r.readInt32();
        final effectJson = utf8.decode(r.readBytes(byteLength));
        final effectMap = jsonDecode(effectJson) as Map<String, dynamic>;
        effects.add({
          'startTick': startTick,
          'processedElapsed': processedElapsed,
          'effect': effectMap,
        });
      }
      entityEffects[entityId] = effects;
    }

    return EffectSnapshot(tick: tick, entityEffects: entityEffects);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal helpers
// ─────────────────────────────────────────────────────────────────────────────

class _ByteWriter {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  void writeUint8(int v) => _builder.addByte(v & 0xFF);

  void writeInt32(int v) {
    final d = ByteData(4)..setInt32(0, v, Endian.little);
    _builder.add(d.buffer.asUint8List());
  }

  void writeBytes(List<int> bytes) => _builder.add(bytes);

  Uint8List build() => _builder.toBytes();
}

class _ByteReader {
  final ByteData _data;
  int _offset = 0;

  _ByteReader(Uint8List bytes)
    : _data = ByteData.view(
        bytes.buffer,
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );

  int readUint8() => _data.getUint8(_offset++);

  int readInt32() {
    final v = _data.getInt32(_offset, Endian.little);
    _offset += 4;
    return v;
  }

  Uint8List readBytes(int count) {
    final result = Uint8List.view(
      _data.buffer,
      _data.offsetInBytes + _offset,
      count,
    );
    _offset += count;
    return result;
  }
}

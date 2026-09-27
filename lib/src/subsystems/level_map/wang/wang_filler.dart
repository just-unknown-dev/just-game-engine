/// Terrain painting: choosing the tiles that make terrains meet cleanly.
library;

import 'dart:math' as math;
import 'dart:ui';

import '../tile_cell.dart';
import '../tile_chunks.dart';
import '../map_geometry.dart';
import '../tileset_data.dart';

/// What a terrain brush stroke touches: a corner, an edge, or a whole cell.
enum WangFeatureKind { corner, edge, cell }

/// One place a terrain brush paints, on the map's lattice (see
/// [MapGeometry.toLattice]).
///
/// A corner is named by the cell it is the top-left corner of; an edge by
/// the cell it is the top ([horizontal]) or left edge of.
class WangTarget {
  const WangTarget.corner(this.at)
    : kind = WangFeatureKind.corner,
      horizontal = false;
  const WangTarget.edge(this.at, {required this.horizontal})
    : kind = WangFeatureKind.edge;
  const WangTarget.cell(this.at)
    : kind = WangFeatureKind.cell,
      horizontal = false;

  final WangFeatureKind kind;
  final TileCoord at;
  final bool horizontal;

  @override
  bool operator ==(Object other) =>
      other is WangTarget &&
      other.kind == kind &&
      other.at == at &&
      other.horizontal == horizontal;

  @override
  int get hashCode => Object.hash(kind, at, horizontal);
}

/// The result of a terrain stroke.
class WangResult {
  const WangResult(this.changes, this.unmatched);

  /// New cell values, by map cell.
  final Map<TileCoord, int> changes;

  /// Cells no tile of the set fits exactly: the set lacks that combination.
  /// They were given the closest tile there is.
  final Set<TileCoord> unmatched;
}

class _Candidate {
  const _Candidate(this.cell, this.id, this.weight, this.transformed);
  final int cell;
  final List<int> id;
  final double weight;
  final bool transformed;
}

/// Paints terrains with one Wang set of one tileset, the way Tiled's
/// terrain brush does.
///
/// Painting sets a colour on corners (corner sets), edges (edge sets) or
/// both (mixed). Every cell touching what was painted then gets the tile
/// whose Wang id matches what surrounds it: the painted colours exactly,
/// and — as closely as the set allows — the colours its neighbours already
/// show, so a stroke joins the terrain around it. Among equally good tiles,
/// one is chosen at random by probability, which is what makes a patch of
/// grass not repeat the same tile.
///
/// Works on the map's square lattice, so on orthogonal, isometric and
/// staggered maps alike. Hexagonal maps have no lattice, and Tiled's
/// eight-slot Wang ids do not describe six-sided cells; the filler refuses
/// them.
class WangFiller {
  WangFiller({
    required this.set,
    required this.tileset,
    required this.slot,
    required this.geometry,
    math.Random? random,
  }) : _random = random ?? math.Random() {
    if (!geometry.hasLattice) {
      throw UnsupportedError(
        'Terrain painting needs a square lattice; '
        '${geometry.orientation.name} maps have none',
      );
    }
  }

  /// The terrains painted with.
  final WangSetData set;

  /// The tileset [set] belongs to: its probabilities and transformations.
  final TilesetData tileset;

  /// The map's slot for [tileset].
  final int slot;

  final MapGeometry geometry;
  final math.Random _random;

  // Slot positions: which of a cell's slots a corner or edge is.
  static const int _top = WangSetData.top;
  static const int _right = WangSetData.right;
  static const int _bottom = WangSetData.bottom;
  static const int _left = WangSetData.left;
  static const int _topRight = WangSetData.topRight;
  static const int _bottomRight = WangSetData.bottomRight;
  static const int _bottomLeft = WangSetData.bottomLeft;
  static const int _topLeft = WangSetData.topLeft;

  // ── Reading tiles ────────────────────────────────────────────────────────

  /// [id] as it reads on a cell turned by [flags]: Tiled mirrors across the
  /// diagonal, then horizontally, then vertically.
  static List<int> transformId(List<int> id, int flags) {
    var out = List<int>.of(id);
    if (TileCell.isFlippedD(flags)) {
      out = [for (var j = 0; j < 8; j++) out[(14 - j) % 8]];
    }
    if (TileCell.isFlippedH(flags)) {
      out = [for (var j = 0; j < 8; j++) out[(8 - j) % 8]];
    }
    if (TileCell.isFlippedV(flags)) {
      out = [for (var j = 0; j < 8; j++) out[(12 - j) % 8]];
    }
    return out;
  }

  /// The Wang id [cell] shows, or null when it is not a tile of [set].
  List<int>? wangIdOf(int cell) {
    if (TileCell.isEmpty(cell) || TileCell.slotOf(cell) != slot) return null;
    final base = set.wangIds[TileCell.localIdOf(cell)];
    return base == null ? null : transformId(base, TileCell.flagsOf(cell));
  }

  late final List<_Candidate> _candidates = _buildCandidates();

  List<_Candidate> _buildCandidates() {
    final t = tileset.transformations;
    final out = <_Candidate>[];
    for (final entry in set.wangIds.entries) {
      final tileId = entry.key;
      if (entry.value.every((c) => c == 0)) continue;
      final plain = TileCell.make(slot, tileId);
      final variants = <int>{plain};
      if (t.rotate) {
        var turned = plain;
        for (var i = 0; i < 3; i++) {
          turned = TileCell.rotatedRight(turned);
          variants.add(turned);
        }
      }
      if (t.hflip) {
        variants.addAll([
          for (final v in variants.toList()) TileCell.mirroredH(v),
        ]);
      }
      if (t.vflip) {
        variants.addAll([
          for (final v in variants.toList()) TileCell.mirroredV(v),
        ]);
      }
      final probability = tileset.tile(tileId)?.probability ?? 1;
      final seen = <String>{};
      for (final cell in variants) {
        final id = transformId(entry.value, TileCell.flagsOf(cell));
        // Two ways of turning a symmetric tile can read the same; keep one,
        // preferring the untransformed.
        if (!seen.add(id.join(','))) continue;
        out.add(
          _Candidate(
            cell,
            id,
            probability * _colorWeight(id),
            TileCell.flagsOf(cell) != 0,
          ),
        );
      }
    }
    return out;
  }

  double _colorWeight(List<int> id) {
    var weight = 1.0;
    for (final s in set.slots) {
      final c = id[s];
      if (c > 0 && c <= set.colors.length) {
        weight *= set.colors[c - 1].probability;
      }
    }
    return weight;
  }

  // ── Where the pointer is ─────────────────────────────────────────────────

  /// What a terrain brush of [type] paints with the pointer at [point]
  /// (map-local): the nearest corner, the nearest edge, or — mixed sets,
  /// pointer near the middle — the whole cell.
  static WangTarget targetAt(
    MapGeometry geometry,
    Offset point,
    WangType type,
  ) {
    final cell = geometry.cellAt(point);
    final l = geometry.toLattice(cell);
    // The outline runs top-left, top-right, bottom-right, bottom-left in
    // lattice terms, whatever it looks like on screen.
    final poly = geometry.cellPolygon(cell.x, cell.y);
    final corners = [
      (poly[0], WangTarget.corner(l)),
      (poly[1], WangTarget.corner(TileCoord(l.x + 1, l.y))),
      (poly[2], WangTarget.corner(TileCoord(l.x + 1, l.y + 1))),
      (poly[3], WangTarget.corner(TileCoord(l.x, l.y + 1))),
    ];
    Offset mid(Offset a, Offset b) => (a + b) / 2;
    final edges = [
      (mid(poly[0], poly[1]), WangTarget.edge(l, horizontal: true)),
      (
        mid(poly[1], poly[2]),
        WangTarget.edge(TileCoord(l.x + 1, l.y), horizontal: false),
      ),
      (
        mid(poly[2], poly[3]),
        WangTarget.edge(TileCoord(l.x, l.y + 1), horizontal: true),
      ),
      (mid(poly[3], poly[0]), WangTarget.edge(l, horizontal: false)),
    ];
    final centre = (poly[0] + poly[1] + poly[2] + poly[3]) / 4;
    final options = switch (type) {
      WangType.corner => corners,
      WangType.edge => edges,
      WangType.mixed => [...corners, ...edges, (centre, WangTarget.cell(l))],
    };
    var best = options.first;
    var bestD = double.infinity;
    for (final o in options) {
      final d = (o.$1 - point).distanceSquared;
      if (d < bestD) {
        bestD = d;
        best = o;
      }
    }
    return best.$2;
  }

  // ── Painting ─────────────────────────────────────────────────────────────

  /// Paints [color] (1-based) at each of [targets] on [layer], and works out
  /// every cell that has to change. Nothing is written: the caller applies
  /// [WangResult.changes], so a stroke can be one undo step.
  WangResult paint(
    TileChunkStore layer,
    Iterable<WangTarget> targets,
    int color,
  ) {
    // What is being painted, as corner and edge colours.
    final corners = <TileCoord, int>{};
    final hEdges = <TileCoord, int>{};
    final vEdges = <TileCoord, int>{};
    final usesCorners = set.type != WangType.edge;
    final usesEdges = set.type != WangType.corner;
    for (final t in targets) {
      switch (t.kind) {
        case WangFeatureKind.corner:
          if (usesCorners) corners[t.at] = color;
        case WangFeatureKind.edge:
          if (usesEdges) (t.horizontal ? hEdges : vEdges)[t.at] = color;
        case WangFeatureKind.cell:
          final u = t.at.x;
          final v = t.at.y;
          if (usesCorners) {
            for (final c in [
              TileCoord(u, v),
              TileCoord(u + 1, v),
              TileCoord(u + 1, v + 1),
              TileCoord(u, v + 1),
            ]) {
              corners[c] = color;
            }
          }
          if (usesEdges) {
            hEdges[TileCoord(u, v)] = color;
            hEdges[TileCoord(u, v + 1)] = color;
            vEdges[TileCoord(u, v)] = color;
            vEdges[TileCoord(u + 1, v)] = color;
          }
      }
    }

    // Every lattice cell touching something painted.
    final affected = <TileCoord>{};
    for (final c in corners.keys) {
      affected
        ..add(TileCoord(c.x - 1, c.y - 1))
        ..add(TileCoord(c.x, c.y - 1))
        ..add(TileCoord(c.x - 1, c.y))
        ..add(c);
    }
    for (final e in hEdges.keys) {
      affected
        ..add(e)
        ..add(TileCoord(e.x, e.y - 1));
    }
    for (final e in vEdges.keys) {
      affected
        ..add(e)
        ..add(TileCoord(e.x - 1, e.y));
    }

    List<int>? idAt(TileCoord l) {
      final m = geometry.fromLattice(l);
      return wangIdOf(layer.cellAt(m.x, m.y));
    }

    // The colour a corner or edge shows now, read from the cells around it
    // — first the ones that will not change, since those are what the new
    // tiles must meet.
    int shown(List<(TileCoord, int)> sharers) {
      for (final pass in [false, true]) {
        for (final (cell, s) in sharers) {
          if (affected.contains(cell) != pass) continue;
          final id = idAt(cell);
          if (id != null && id[s] != 0) return id[s];
        }
      }
      return 0;
    }

    int cornerColor(TileCoord c) =>
        corners[c] ??
        shown([
          (TileCoord(c.x - 1, c.y - 1), _bottomRight),
          (TileCoord(c.x, c.y - 1), _bottomLeft),
          (TileCoord(c.x - 1, c.y), _topRight),
          (c, _topLeft),
        ]);
    int hEdgeColor(TileCoord e) =>
        hEdges[e] ?? shown([(e, _top), (TileCoord(e.x, e.y - 1), _bottom)]);
    int vEdgeColor(TileCoord e) =>
        vEdges[e] ?? shown([(e, _left), (TileCoord(e.x - 1, e.y), _right)]);

    final changes = <TileCoord, int>{};
    final unmatched = <TileCoord>{};
    for (final l in affected) {
      final u = l.x;
      final v = l.y;
      final want = List<int>.filled(8, 0);
      final hard = List<bool>.filled(8, false);
      if (usesCorners) {
        void corner(int s, TileCoord c) {
          want[s] = cornerColor(c);
          hard[s] = corners.containsKey(c);
        }

        corner(_topLeft, TileCoord(u, v));
        corner(_topRight, TileCoord(u + 1, v));
        corner(_bottomRight, TileCoord(u + 1, v + 1));
        corner(_bottomLeft, TileCoord(u, v + 1));
      }
      if (usesEdges) {
        want[_top] = hEdgeColor(TileCoord(u, v));
        hard[_top] = hEdges.containsKey(TileCoord(u, v));
        want[_bottom] = hEdgeColor(TileCoord(u, v + 1));
        hard[_bottom] = hEdges.containsKey(TileCoord(u, v + 1));
        want[_left] = vEdgeColor(TileCoord(u, v));
        hard[_left] = vEdges.containsKey(TileCoord(u, v));
        want[_right] = vEdgeColor(TileCoord(u + 1, v));
        hard[_right] = vEdges.containsKey(TileCoord(u + 1, v));
      }
      if (want.every((c) => c == 0)) continue;

      final (pick, exact) = _choose(want, hard);
      final at = geometry.fromLattice(l);
      if (pick == null) continue;
      if (!exact) unmatched.add(at);
      if (layer.cellAt(at.x, at.y) != pick.cell) changes[at] = pick.cell;
    }
    return WangResult(changes, unmatched);
  }

  /// The best tile for [want] — every [hard] slot matched, as many others as
  /// possible — and whether it matched everything asked of it.
  (_Candidate?, bool) _choose(List<int> want, List<bool> hard) {
    double score(_Candidate c, {required bool strict}) {
      var penalty = 0.0;
      for (final s in set.slots) {
        final w = want[s];
        if (w == 0) {
          // Nothing there says what this slot should be. Lean towards
          // nothing, so one stroke of road on bare ground is a road end,
          // not a crossroads — too little to outweigh a real mismatch.
          if (c.id[s] != 0) penalty += 0.01;
          continue;
        }
        if (c.id[s] == w) continue;
        if (hard[s]) {
          if (strict) return double.infinity;
          penalty += 100;
        } else {
          penalty += 1;
        }
      }
      if (c.transformed && tileset.transformations.preferUntransformed) {
        penalty += 0.5;
      }
      return penalty;
    }

    for (final strict in [true, false]) {
      var best = double.infinity;
      final ties = <_Candidate>[];
      for (final c in _candidates) {
        final s = score(c, strict: strict);
        if (s < best) {
          best = s;
          ties
            ..clear()
            ..add(c);
        } else if (s == best && s.isFinite) {
          ties.add(c);
        }
      }
      if (ties.isEmpty || !best.isFinite) continue;
      final exact = best < 1;
      return (_weighted(ties), exact);
    }
    return (null, false);
  }

  _Candidate _weighted(List<_Candidate> options) {
    if (options.length == 1) return options.first;
    final total = options.fold<double>(0, (a, c) => a + math.max(0, c.weight));
    if (total <= 0) return options[_random.nextInt(options.length)];
    var roll = _random.nextDouble() * total;
    for (final c in options) {
      roll -= math.max(0, c.weight);
      if (roll <= 0) return c;
    }
    return options.last;
  }
}

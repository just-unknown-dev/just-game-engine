import 'package:just_dart/just_dart.dart' show Matrix4;
import 'package:just_graphics_engine/renderer.dart';

import '../ecs/base/engine_context.dart';
import '../ecs/ecs.dart';
import 'graphics_models.dart';
import 'graphics_shapes.dart';

/// What a [RenderProvider] builds with: the uploader that makes GPU
/// meshes, the models and the shapes' materials it may share, and the
/// stand-in textures.
final class RenderProviderContext {
  /// The 3-D scene renderer's own.
  const RenderProviderContext({
    required this.uploader,
    required this.models,
    required this.shapes,
  });

  /// Makes meshes and materials on the renderer's device.
  final ModelUploader uploader;

  /// The models loaded, to draw copies of one.
  final GraphicsModels models;

  /// The shapes' meshes and materials, to share one.
  final GraphicsShapes shapes;
}

/// What a [RenderProvider] hands the renderer for one entity: meshes and
/// batches placed in the entity's own space — the renderer moves them with
/// the entity.
final class RenderProviderOutput {
  final List<(GpuPrimitive, GpuMaterial, Matrix4, bool)> _meshes = [];
  final List<(GpuPrimitive, GpuMaterial, List<Matrix4>, double, bool)> _batches = [];

  /// Draws [primitive] in [material] at [local] (entity from mesh; the
  /// entity's origin when null).
  void addMesh(
    GpuPrimitive primitive,
    GpuMaterial material, {
    Matrix4? local,
    bool castShadows = true,
  }) => _meshes.add((primitive, material, local ?? Matrix4.identity(), castShadows));

  /// Draws [primitive] in [material] once at each of [locals] (entity from
  /// copy), in one call: grass, posts, tiles. Not drawn beyond
  /// [maxDistance] metres from the camera.
  void addBatch(
    GpuPrimitive primitive,
    GpuMaterial material,
    List<Matrix4> locals, {
    double maxDistance = double.infinity,
    bool castShadows = true,
  }) => _batches.add((primitive, material, locals, maxDistance, castShadows));

  /// The meshes added: primitive, material, placement, shadows.
  List<(GpuPrimitive, GpuMaterial, Matrix4, bool)> get meshes => _meshes;

  /// The batches added: primitive, material, placements, reach, shadows.
  List<(GpuPrimitive, GpuMaterial, List<Matrix4>, double, bool)> get batches => _batches;
}

/// Turns a component the renderer does not know — a terrain, a scatter of
/// grass, a swept road — into meshes and batches it draws.
///
/// Registered with [RenderProviders] (a kit's extension does it when it is
/// installed). The renderer builds an entity's output once and again only
/// when [revisionOf] changes or the component is replaced; between builds
/// it only follows the entity's transform. A provider never writes the
/// component's saved fields: its revision is runtime state.
abstract class RenderProvider<C extends Component> {
  /// For subclasses.
  const RenderProvider();

  /// The component type it draws.
  Type get componentType => C;

  /// What changes whenever [build] would build something else — a counter
  /// the component's editor bumps, a hash of what it draws from.
  Object? revisionOf(C component);

  /// Builds what [component], on [entity], draws into [out].
  void build(
    RenderProviderContext context,
    Entity entity,
    C component,
    RenderProviderOutput out,
  );

  /// Calls [revisionOf] with a component it is known to draw.
  Object? revisionOfAny(Component component) => revisionOf(component as C);

  /// Calls [build] with a component it is known to draw.
  void buildAny(
    RenderProviderContext context,
    Entity entity,
    Component component,
    RenderProviderOutput out,
  ) => build(context, entity, component as C, out);
}

/// The [RenderProvider]s of one engine: what its 3-D renderer draws beyond
/// models and shapes.
final class RenderProviders {
  /// None yet.
  RenderProviders();

  /// The providers of [context], made on first use.
  static RenderProviders of(EngineContext context) =>
      context.slot(RenderProviders, RenderProviders.new);

  final Map<Type, RenderProvider<Component>> _byType = {};
  int _version = 0;

  /// Bumped whenever one is registered or removed, so the renderer looks
  /// over the world again.
  int get version => _version;

  /// Every provider, in registration order.
  Iterable<RenderProvider<Component>> get all => _byType.values;

  /// Registers [provider], replacing one for the same component type.
  void register(RenderProvider<Component> provider) {
    _byType[provider.componentType] = provider;
    _version++;
  }

  /// Takes the provider for [type] away.
  void unregister(Type type) {
    if (_byType.remove(type) != null) _version++;
  }

  /// The provider for [type], if any.
  RenderProvider<Component>? forType(Type type) => _byType[type];
}

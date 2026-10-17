import '../ecs/ecs.dart';
import 'graphics_components.dart';
import 'shapes/primitive_3d.dart';

/// Where an entity's material file goes: its shape's [Primitive3D.material],
/// or — for a model — the file drawn for every one of its materials
/// (`*` in [ModelComponent.materials]). What painting a material on, and
/// picking one up, work through.
abstract final class MaterialSlots {
  /// What holds [entity]'s material file — its shape, else its model —
  /// or null when it draws nothing a material file can go on.
  static Component? holderOf(Entity entity) =>
      entity.getComponent<Primitive3D>() ?? entity.getComponent<ModelComponent>();

  /// The material file [entity] is drawn with; empty for its own look.
  static String materialOf(Entity entity) {
    final shape = entity.getComponent<Primitive3D>();
    if (shape != null) return shape.material;
    return entity.getComponent<ModelComponent>()?.materials['*'] ?? '';
  }

  /// Draws [entity] with the material file at [path] (empty for its own
  /// look again). False when it has nothing to draw it on.
  static bool assign(Entity entity, String path) {
    final shape = entity.getComponent<Primitive3D>();
    if (shape != null) {
      shape.material = path;
      return true;
    }
    final model = entity.getComponent<ModelComponent>();
    if (model == null) return false;
    model.materials = path.isEmpty ? {} : {'*': path};
    return true;
  }
}

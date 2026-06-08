import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(home: MyGame()));
}

class MyGame extends StatefulWidget {
  const MyGame({super.key});

  @override
  State<MyGame> createState() => _MyGameState();
}

class _MyGameState extends State<MyGame> {
  late final Engine _engine;
  late final World _world;
  final GlobalKey _gameWidgetKey = GlobalKey();

  Size _readViewportSize() {
    final renderObject = _gameWidgetKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      return renderObject.size;
    }
    return MediaQuery.sizeOf(context);
  }

  @override
  void initState() {
    super.initState();
    _engine = Engine();
    _init();
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _engine.initialize();
    _world = _engine.world;

    // Add core ECS systems
    _world.addSystem(RenderSystem());

    final size = _readViewportSize();
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Circle: radial gradient + warm tint.
    _world.createEntityWithComponents([
      TransformComponent(
        position: Vector3.fromXY(centerX - 180, centerY - 120),
      ),
      CircleComponent(
        radius: 48,
        fillStyle: const ShapePaintStyle(
          color: Color(0xFFFFB36B),
          gradient: ShapeGradient.radial(
            colors: [Color(0xFFFFFFFF), Color(0xFF4E2B1A)],
            radius: 0.9,
          ),
        ),
        strokeStyle: const ShapePaintStyle(
          color: Color(0xFFFFE2BE),
          gradient: ShapeGradient.sweep(
            colors: [Color(0xFFFFF0D9), Color(0xFFFFA45C), Color(0xFFFFF0D9)],
          ),
        ),
        strokeWidth: 4,
      ),
    ], name: 'shape_circle');

    // Rectangle: linear gradient + cool tint.
    _world.createEntityWithComponents([
      TransformComponent(position: Vector3.fromXY(centerX + 40, centerY - 120)),
      RectangleComponent(
        width: 180,
        height: 96,
        cornerRadius: 20,
        fillStyle: const ShapePaintStyle(
          color: Color(0xFF8FD6FF),
          gradient: ShapeGradient.linear(
            colors: [Color(0xFF0A1A2A), Color(0xFF1A4C70), Color(0xFF2E8DBB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        strokeStyle: const ShapePaintStyle(color: Color(0xFFDAF4FF)),
        strokeWidth: 3,
      ),
    ], name: 'shape_rectangle');

    // Polygon: sweep gradient + magenta tint.
    _world.createEntityWithComponents([
      TransformComponent(position: Vector3.fromXY(centerX - 210, centerY + 90)),
      PolygonComponent(
        vertices: const [
          Offset(0, -70),
          Offset(58, -18),
          Offset(36, 60),
          Offset(-36, 60),
          Offset(-58, -18),
        ],
        fillStyle: const ShapePaintStyle(
          color: Color(0xFFFF6AD5),
          gradient: ShapeGradient.sweep(
            colors: [Color(0xFF25002A), Color(0xFF6D1A84), Color(0xFF25002A)],
          ),
        ),
        strokeStyle: const ShapePaintStyle(color: Color(0xFFFFD1F5)),
        strokeWidth: 4,
      ),
    ], name: 'shape_polygon');

    // Line: linear gradient + cyan tint.
    _world.createEntityWithComponents([
      TransformComponent(position: Vector3.fromXY(centerX - 10, centerY + 96)),
      LineComponent(
        start: const Offset(-110, 0),
        end: const Offset(110, 0),
        roundCaps: true,
        strokeWidth: 14,
        strokeStyle: const ShapePaintStyle(
          color: Color(0xFF95FFF9),
          gradient: ShapeGradient.linear(
            colors: [Color(0xFF00353F), Color(0xFF00A0B3), Color(0xFF00353F)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
      ),
    ], name: 'shape_line');

    // Capsule: radial fill + sweep stroke.
    _world.createEntityWithComponents([
      TransformComponent(position: Vector3.fromXY(centerX + 220, centerY + 86)),
      CapsuleComponent(
        width: 150,
        height: 70,
        fillStyle: const ShapePaintStyle(
          color: Color(0xFFFFE28A),
          gradient: ShapeGradient.radial(
            colors: [Color(0xFF4A3200), Color(0xFFB67E00)],
            center: Alignment(-0.25, -0.15),
            radius: 1.0,
          ),
        ),
        strokeStyle: const ShapePaintStyle(
          color: Color(0xFFFFF2C6),
          gradient: ShapeGradient.sweep(
            colors: [Color(0xFFFFD46A), Color(0xFFFFFAE0), Color(0xFFFFD46A)],
          ),
        ),
        strokeWidth: 4,
      ),
    ], name: 'shape_capsule');

    _engine.start();
  }

  Widget _shapeLabel({
    required double left,
    required double top,
    required String text,
  }) {
    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xAA000000),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    return Scaffold(
      body: Stack(
        children: [
          GameWidget(key: _gameWidgetKey, engine: _engine),
          _shapeLabel(left: centerX - 220, top: centerY - 195, text: 'Circle'),
          _shapeLabel(
            left: centerX + 10,
            top: centerY - 195,
            text: 'Rectangle',
          ),
          _shapeLabel(left: centerX - 250, top: centerY + 12, text: 'Polygon'),
          _shapeLabel(left: centerX - 36, top: centerY + 132, text: 'Line'),
          _shapeLabel(left: centerX + 184, top: centerY + 10, text: 'Capsule'),
        ],
      ),
    );
  }
}

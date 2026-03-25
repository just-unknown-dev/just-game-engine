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

    // Create a player entity with ECS components
    _world.createEntityWithComponents([
      TransformComponent(
        position: Offset(
          _readViewportSize().width / 2,
          _readViewportSize().height / 2,
        ),
      ),
      VelocityComponent(velocity: const Offset(100, 0)),
      RenderableComponent(
        renderable: CircleRenderable(radius: 30, fillColor: Colors.blue),
      ),
    ], name: 'Player');

    _engine.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GameWidget(key: _gameWidgetKey, engine: _engine),
    );
  }
}

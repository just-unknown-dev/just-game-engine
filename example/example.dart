import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final engine = Engine();
  await engine.initialize();

  // Add a simple renderable
  engine.rendering.addRenderable(
    CircleRenderable(radius: 50, fillColor: Colors.blue, position: Offset.zero),
  );

  engine.start();

  runApp(
    MaterialApp(
      home: Scaffold(body: GameWidget(engine: engine)),
    ),
  );
}

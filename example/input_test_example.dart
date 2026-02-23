/// Input Test Example
///
/// This example demonstrates all input features including keyboard, mouse, and touch.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'dart:math' as math;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final engine = Engine();
  await engine.initialize();

  // Setup input test scene
  setupInputTest(engine);

  engine.start();
  runApp(InputTestApp(engine: engine));
}

void setupInputTest(Engine engine) {
  // Create player controlled by input
  final player = CircleRenderable(
    radius: 30,
    fillColor: Colors.blue,
    position: Offset.zero,
  );
  engine.rendering.addRenderable(player);

  // Create mouse cursor indicator
  final mouseCursor = CircleRenderable(
    radius: 10,
    fillColor: Colors.red.withValues(alpha: 0.5),
    position: Offset.zero,
  );
  engine.rendering.addRenderable(mouseCursor);

  // Create trail particles for mouse movement
  final List<CircleRenderable> trail = [];

  // Create keyboard indicator circles
  final Map<String, CircleRenderable> keyIndicators = {};
  final keyPositions = {
    'W': const Offset(0, -150),
    'A': const Offset(-50, -100),
    'S': const Offset(0, -100),
    'D': const Offset(50, -100),
    'Space': const Offset(0, -50),
  };

  for (final entry in keyPositions.entries) {
    final indicator = CircleRenderable(
      radius: 20,
      fillColor: Colors.grey.withValues(alpha: 0.3),
      strokeColor: Colors.white,
      strokeWidth: 2,
      position: entry.value,
    );
    keyIndicators[entry.key] = indicator;
    engine.rendering.addRenderable(indicator);
  }

  // Create click effect pool
  final List<CircleRenderable> clickEffects = [];

  // Store input info for display
  String inputInfo = '';
  int touchCount = 0;
  String lastKeyPressed = '';
  Offset mousePos = Offset.zero;
  int clickCount = 0;

  // Create custom renderable for drawing input info
  final infoRenderable = CustomRenderable(
    onRender: (canvas, size) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: inputInfo,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      // Draw in bottom-left corner
      canvas.save();
      canvas.translate(
        -size.width / 2 + 20,
        size.height / 2 - textPainter.height - 20,
      );
      textPainter.paint(canvas, Offset.zero);
      canvas.restore();
    },
  );
  engine.rendering.addRenderable(infoRenderable);

  // Player movement speed
  const double moveSpeed = 300.0;

  // Update loop
  engine.rendering.addRenderable(
    CustomRenderable(
      onRender: (canvas, size) {
        final input = engine.input;
        final deltaTime = engine.time.deltaTime;

        // === KEYBOARD INPUT ===
        // Move player with WASD or Arrow keys
        Offset movement = Offset.zero;

        if (input.keyboard.isKeyDown(LogicalKeyboardKey.keyW) ||
            input.keyboard.isKeyDown(LogicalKeyboardKey.arrowUp)) {
          movement += const Offset(0, -1);
          keyIndicators['W']!.fillColor = Colors.green.withValues(alpha: 0.7);
        } else {
          keyIndicators['W']!.fillColor = Colors.grey.withValues(alpha: 0.3);
        }

        if (input.keyboard.isKeyDown(LogicalKeyboardKey.keyS) ||
            input.keyboard.isKeyDown(LogicalKeyboardKey.arrowDown)) {
          movement += const Offset(0, 1);
          keyIndicators['S']!.fillColor = Colors.green.withValues(alpha: 0.7);
        } else {
          keyIndicators['S']!.fillColor = Colors.grey.withValues(alpha: 0.3);
        }

        if (input.keyboard.isKeyDown(LogicalKeyboardKey.keyA) ||
            input.keyboard.isKeyDown(LogicalKeyboardKey.arrowLeft)) {
          movement += const Offset(-1, 0);
          keyIndicators['A']!.fillColor = Colors.green.withValues(alpha: 0.7);
        } else {
          keyIndicators['A']!.fillColor = Colors.grey.withValues(alpha: 0.3);
        }

        if (input.keyboard.isKeyDown(LogicalKeyboardKey.keyD) ||
            input.keyboard.isKeyDown(LogicalKeyboardKey.arrowRight)) {
          movement += const Offset(1, 0);
          keyIndicators['D']!.fillColor = Colors.green.withValues(alpha: 0.7);
        } else {
          keyIndicators['D']!.fillColor = Colors.grey.withValues(alpha: 0.3);
        }

        // Normalize diagonal movement
        if (movement.distance > 0) {
          movement = Offset(
            movement.dx / movement.distance,
            movement.dy / movement.distance,
          );
        }

        // Apply movement
        player.position += movement * moveSpeed * deltaTime;

        // Space key for boost/color change
        if (input.keyboard.isKeyDown(LogicalKeyboardKey.space)) {
          player.fillColor = Colors.yellow;
          player.radius = 40;
          keyIndicators['Space']!.fillColor = Colors.yellow.withValues(
            alpha: 0.7,
          );
        } else {
          player.fillColor = Colors.blue;
          player.radius = 30;
          keyIndicators['Space']!.fillColor = Colors.grey.withValues(
            alpha: 0.3,
          );
        }

        // Track last key pressed
        if (input.keyboard.anyKeyPressed) {
          for (final key in input.keyboard.keysDown) {
            lastKeyPressed = key.keyLabel;
            break;
          }
        }

        // Reset camera with R
        if (input.keyboard.isKeyPressed(LogicalKeyboardKey.keyR)) {
          engine.rendering.camera.reset();
        }

        // === MOUSE INPUT ===
        mousePos = input.mouse.position;

        // Convert screen position to world position
        final worldPos = engine.rendering.camera.screenToWorld(mousePos);
        mouseCursor.position = worldPos;

        // Left click to create effects
        if (input.mouse.isButtonPressed(MouseButton.left)) {
          clickCount++;

          // Create expanding circle effect
          final effect = CircleRenderable(
            radius: 10,
            fillColor: Colors.transparent,
            strokeColor: Colors.orange,
            strokeWidth: 3,
            position: worldPos,
          );
          clickEffects.add(effect);
          engine.rendering.addRenderable(effect);

          // Animate effect
          final startTime = DateTime.now();
          void animateEffect() {
            final elapsed =
                DateTime.now().difference(startTime).inMilliseconds / 1000.0;
            if (elapsed < 0.5) {
              effect.radius = 10 + elapsed * 60;
              effect.strokeWidth = 3 - elapsed * 4;
              effect.strokeColor = Colors.orange.withValues(
                alpha: 1 - elapsed * 2,
              );
            } else {
              engine.rendering.removeRenderable(effect);
              clickEffects.remove(effect);
            }
          }

          // Use engine update to animate
          engine.rendering.addRenderable(
            CustomRenderable(
              onRender: (c, s) {
                if (clickEffects.contains(effect)) {
                  animateEffect();
                }
              },
            ),
          );
        }

        // Right click to spawn circle at mouse
        if (input.mouse.isButtonPressed(MouseButton.right)) {
          final newCircle = CircleRenderable(
            radius: 15 + math.Random().nextDouble() * 20,
            fillColor: HSLColor.fromAHSL(
              1.0,
              math.Random().nextDouble() * 360,
              0.7,
              0.6,
            ).toColor(),
            position: worldPos,
          );
          engine.rendering.addRenderable(newCircle);
        }

        // Mouse wheel to zoom
        if (input.mouse.scrollDelta.dy != 0) {
          final zoomFactor = 1.0 - input.mouse.scrollDelta.dy * 0.001;
          engine.rendering.camera.zoomBy(zoomFactor);
        }

        // Middle mouse to pan camera
        if (input.mouse.isMiddleButtonDown) {
          engine.rendering.camera.moveBy(-input.mouse.delta);
        }

        // === TOUCH INPUT ===
        touchCount = input.touch.touchCount;

        // Draw touch points
        for (final touch in input.touch.touches) {
          final touchWorld = engine.rendering.camera.screenToWorld(
            touch.position,
          );

          final touchIndicator = CircleRenderable(
            radius: 20 + touch.size * 10,
            fillColor: Colors.purple.withValues(alpha: 0.3),
            strokeColor: Colors.purple,
            strokeWidth: 2,
            position: touchWorld,
          );

          canvas.save();
          canvas.translate(touchWorld.dx, touchWorld.dy);

          // Draw touch indicator
          final paint = Paint()
            ..color = touchIndicator.fillColor
            ..style = PaintingStyle.fill;
          canvas.drawCircle(Offset.zero, touchIndicator.radius, paint);

          final stroke = Paint()
            ..color = touchIndicator.strokeColor!
            ..style = PaintingStyle.stroke
            ..strokeWidth = touchIndicator.strokeWidth;
          canvas.drawCircle(Offset.zero, touchIndicator.radius, stroke);

          canvas.restore();
        }

        // Mouse trail effect
        if (input.mouse.delta.distance > 1) {
          final trailParticle = CircleRenderable(
            radius: 5,
            fillColor: Colors.cyan.withValues(alpha: 0.5),
            position: worldPos,
          );
          trail.add(trailParticle);
          engine.rendering.addRenderable(trailParticle);

          if (trail.length > 20) {
            final old = trail.removeAt(0);
            engine.rendering.removeRenderable(old);
          }
        }

        // Fade trail
        for (int i = 0; i < trail.length; i++) {
          final particle = trail[i];
          final alpha = (i / trail.length) * 0.5;
          particle.fillColor = Colors.cyan.withValues(alpha: alpha);
          particle.radius = 5 * (i / trail.length);
        }

        // === UPDATE INFO DISPLAY ===
        inputInfo =
            '''
=== INPUT TEST ===
Keyboard:
  WASD/Arrows: Move player
  Space: Boost (hold)
  R: Reset camera
  Axis: (${input.keyboard.horizontal.toStringAsFixed(2)}, ${input.keyboard.vertical.toStringAsFixed(2)})
  Last Key: $lastKeyPressed

Mouse:
  Position: (${mousePos.dx.toInt()}, ${mousePos.dy.toInt()})
  World: (${worldPos.dx.toInt()}, ${worldPos.dy.toInt()})
  Delta: (${input.mouse.delta.dx.toStringAsFixed(1)}, ${input.mouse.delta.dy.toStringAsFixed(1)})
  Left Click: Spawn effect
  Right Click: Spawn circle
  Middle/Drag: Pan camera  
  Scroll: Zoom
  Clicks: $clickCount

Touch:
  Active Touches: $touchCount
  
Camera:
  Position: (${engine.rendering.camera.position.dx.toInt()}, ${engine.rendering.camera.position.dy.toInt()})
  Zoom: ${engine.rendering.camera.zoom.toStringAsFixed(2)}
''';
      },
    ),
  );

  debugPrint('Input test scene setup complete!');
  debugPrint('Controls:');
  debugPrint('  - WASD/Arrows to move player');
  debugPrint('  - Space to boost');
  debugPrint('  - Left click to spawn effects');
  debugPrint('  - Right click to spawn circles');
  debugPrint('  - Middle mouse or drag to pan');
  debugPrint('  - Scroll to zoom');
  debugPrint('  - R to reset camera');
}

class InputTestApp extends StatelessWidget {
  final Engine engine;

  const InputTestApp({super.key, required this.engine});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Input Test Demo',
      theme: ThemeData.dark(),
      home: InputTestScreen(engine: engine),
    );
  }
}

class InputTestScreen extends StatefulWidget {
  final Engine engine;

  const InputTestScreen({super.key, required this.engine});

  @override
  State<InputTestScreen> createState() => _InputTestScreenState();
}

class _InputTestScreenState extends State<InputTestScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      body: Stack(
        children: [
          // Game widget with input
          GameWidget(engine: widget.engine, showFPS: true, showDebug: true),

          // Instructions overlay
          Positioned(
            top: 20,
            left: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.5)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ðŸŽ® INPUT TEST DEMO',
                    style: TextStyle(
                      color: Colors.blue,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'âŒ¨ï¸  WASD/Arrows - Move blue player',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Text(
                    'âŒ¨ï¸  Space - Boost (hold)',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Text(
                    'âŒ¨ï¸  R - Reset camera',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'ðŸ–±ï¸  Left Click - Spawn effect',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Text(
                    'ðŸ–±ï¸  Right Click - Spawn circle',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Text(
                    'ðŸ–±ï¸  Middle Mouse - Pan camera',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Text(
                    'ðŸ–±ï¸  Scroll - Zoom',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'ðŸ‘† Touch - Multi-touch support',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    widget.engine.dispose();
    super.dispose();
  }
}

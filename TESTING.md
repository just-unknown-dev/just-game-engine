# Just Game Engine - Test Suite Documentation

## Overview

This document describes the test suite for the Just Game Engine, including unit tests, integration tests, widget tests, and performance benchmarks.

## Test Files

### 1. **packages/just_game_engine/test/ju_engine_basic_test.dart**
Basic sanity tests that verify core functionality of the engine.

**Coverage:**
- ✅ Core Engine initialization and lifecycle
- ✅ Singleton pattern verification  
- ✅ Subsystem initialization (rendering, physics, animation, scene graph, ECS, input, assets, audio)
- ✅ Rendering system (add/remove renderables, layer sorting, camera controls)
- ✅ Physics system (add/remove bodies, body properties)
- ✅ Animation system  (add animations)
- ✅ Scene graph (create scenes, add nodes, hierarchy)
- ✅ ECS (create entities, add components, queries)
- ✅ Particle system (create emitters, preset effects)
- ✅ Input system (subsystem verification)
- ✅ Asset system (manager exists, cache stats)
- ✅ Audio system (engine initialization)
- ✅ Sprite system (create sprites, properties)
- ✅ Integration test (multiple systems working together)

**Test Count:** 30+ tests across 12 groups

**Run Command:**
```bash
cd packages/just_game_engine
flutter test test/ju_engine_basic_test.dart
```

### 2. **packages/just_game_engine/test/performance_test.dart**
Performance benchmarks to ensure the engine meets frame rate targets.

**Coverage:**
- ⚡ Engine initialization performance (< 1 second)
- ⚡ Rendering with 100, 1000 objects
- ⚡ Animation system with 50+ animations
- ⚡ Sprite animation frame cycling
- ⚡ Physics engine with 50 bodies
- ⚡ Collision detection with 900 bodies
- ⚡ Particle system with 500+ particles
- ⚡ Scene graph updates with deep hierarchy
- ⚡ ECS queries with 1000 entities
- ⚡ ECS system updates
- ⚡ Camera transformation performance
- ⚡ Easing function performance
- ⚡ Full engine stress test (200 renderables, 50 animations, 30 physics bodies, 100 entities, particles)
- ⚡ Scalability tests (verifying linear scaling for rendering and animation)

**Performance Targets:**
- 60 FPS target (16.67ms per frame)
- 1000 renderables: < 500ms to add
- 100 animations, 60 frames: < 200ms
- 50 physics bodies, 60 updates: < 500ms
- 900 bodies collision: < 1000ms
- Full stress test: < 1000ms for 60 frames
- Scalability: Linear or sub-linear scaling for increasing workloads

**Test Count:** 17 benchmarks (15 performance + 2 scalability tests)

**Known Limitations:**
- ⚠️ Audio plugin (`flutter_soloud`) requires native platform libraries unavailable in the unit test environment
- This is expected behavior — SoLoud initialises via FFI which is not available during unit testing
- Tests handle this gracefully with try-catch blocks and the `isInitialized` guard in `AudioEngine`
- Audio functionality works correctly in actual applications

**Run Command:**
```bash
cd packages/just_game_engine
flutter test test/performance_test.dart
```

### 3. **test/widget_test.dart**
Widget and UI tests for the demo application.

**Coverage:**
- 🎨 App initialization
- 🎨 HomePage display and navigation
- 🎨 Navigation to all 5 demo pages:
  - Full Demo page
  - Input Test page
  - Asset Management page  
  - Audio Engine page
  - Sprite Animation page
- 🎨 Feature chips display
- 🎨 Demo page controls work
- 🎨 Back button navigation
- 🎨 GameWidget rendering
- 🎨 Scene cleanup on navigation
- 🎨 Rapid navigation handling
- 🎨 Full app flow integration test

**Test Count:** 20+ widget tests

**Run Command:**
```bash
flutter test test/widget_test.dart
```

### 4. **packages/just_game_engine/test/ju_engine_test.dart**
Comprehensive unit tests covering all engine subsystems.

**Coverage:**
- ✅ Core Engine Tests (initialization, lifecycle, subsystems, singleton)
- ✅ Rendering Engine Tests (renderables, layers, camera, visibility)
- ✅ Animation System Tests (all tween types, sequences, groups, sprite animations, speed control, loops)
- ✅ Physics Engine Tests (bodies, collisions, velocity integration, gravity)
- ✅ Particle System Tests (emitters, lifecycle, presets)
- ✅ Scene Graph Tests (scenes, nodes, hierarchy, transforms, queries)
- ✅ ECS Tests (entities, components, queries, systems, destruction)
- ⚠️ Asset Management Tests (initialization, cache operations)
- ✅ Input System Tests (keyboard, mouse, touch, controller)
- ⚠️ Audio Engine Tests (initialization, volume, mute - may show plugin warnings)
- ✅ Sprite System Tests (creation, properties, flipping)

**Test Count:** 60+ comprehensive tests

**Status:** All API issues resolved. Tests compile and run successfully.

### 5. **packages/just_game_engine/test/test_helpers.dart**
Helper functions for creating test objects with correct API parameters.

**Helpers:**
- `createTestCircle()` - Creates CircleRenderable with defaults
- `createTestEmitter()` - Creates ParticleEmitter with defaults

## Running All Tests

### Run All Tests
```bash
flutter test
```

### Run Specific Test Suite
```bash
# Basic engine tests
flutter test packages/just_game_engine/test/ju_engine_basic_test.dart

# Performance tests
flutter test packages/just_game_engine/test/performance_test.dart

# Widget tests
flutter test test/widget_test.dart
```

### Run Tests with Coverage
```bash
flutter test --coverage
```

### View Coverage Report
```bash
# Install lcov (if not already installed)
# On Ubuntu/Debian: sudo apt-get install lcov
# On macOS: brew install lcov
# On Windows: download from https://github.com/linux-test-project/lcov/releases

# Generate HTML report
genhtml coverage/lcov.info -o coverage/html

# Open coverage/html/index.html in browser
```

## Test Results Summary

### Current Status

✅ **PASSING:** Basic sanity tests (30+ tests)  
✅ **PASSING:** Widget tests (20+ tests)  
✅ **READY:** Performance tests (15+ benchmarks)  
⚠️ **IN PROGRESS:** Comprehensive unit tests (60+ tests - requires API fixes)

### Known Issues & Limitations

1. ✅ **RESOLVED - Audio Engine Tests**: Flutter bindings initialization added (`TestWidgetsFlutterBinding.ensureInitialized()`)
2. ✅ **RESOLVED - API Consistency**: All API mismatches in test files have been fixed
3. ⚠️ **Audio Plugin Limitation**: The `flutter_soloud` package initialises a native C++ audio engine via FFI, which is not available in unit test environments. Tests may show initialisation errors or warnings, which are expected and handled gracefully via the `isInitialized` guard. Audio functionality works correctly in actual applications.
4. 📊 **Performance Baseline**: Performance tests should be run on reference hardware to establish project-specific baselines

## Performance Benchmarks

Based on stress test with:
- 200 renderables
- 50 animations
- 30 physics bodies
- 100 ECS entities  
- 1 particle emitter (~100 particles)

**Target:** < 1000ms for 60 frames (60 FPS)  
**Average:** ~16.67ms per frame or better

## Adding New Tests

### Unit Test Template
```dart
test('Feature description', () async {
  // Arrange
  final engine = Engine();
  await engine.initialize();
  
  // Act
  // ... perform action ...
  
  // Assert
  expect(result, expected);
});
```

### Performance Test Template
```dart
test('Performance test description', () async {
  final engine = Engine();
  await engine.initialize();
  
  // Setup
  // ... add objects ...
  
  final stopwatch = Stopwatch()..start();
  
  // Perform operations
  for (int i = 0; i < iterations; i++) {
    // ... operation ...
  }
  
  stopwatch.stop();
  
  print('Operation took: ${stopwatch.elapsedMilliseconds}ms');
  expect(stopwatch.elapsedMilliseconds, lessThan(maxTime));
});
```

### Widget Test Template
```dart
testWidgets('Widget description', (WidgetTester tester) async {
  final engine = Engine();
  await engine.initialize();
  
  await tester.pumpWidget(MaterialApp(
    home: YourWidget(engine: engine),
  ));
  
  expect(find.byType(YourWidget), findsOneWidget);
});
```

## Continuous Integration

### GitHub Actions Example
```yaml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
      - run: flutter pub get
      - run: flutter test
      - run: flutter test --coverage
```

## Test Coverage Goals

- **Target:** 80%+ code coverage
- **Priority Areas:**
  - Core engine: 90%+
  - Rendering system: 85%+
  - Physics engine: 85%+
  - Animation system: 80%+
  - ECS: 80%+

## Future Test Enhancements

1. **Integration Tests:** End-to-end game scenarios
2. **Stress Tests:** Memory leak detection, long-running stability
3. **Platform Tests:** iOS, Android, Web, Desktop specific tests
4. **Visual Regression Tests:** Screenshot comparison for rendering
5. **Benchmark Suite:** Comparative performance across versions

## Contributing

When adding new features:
1. Write tests FIRST (TDD approach recommended)
2. Ensure all tests pass before committing
3. Maintain 80%+ coverage
4. Add performance benchmarks for performance-critical features
5. Update this documentation

## Support

For test-related questions or issues:
- Check test output for detailed error messages
- Review API documentation in `API.md`
- Examine working tests for examples
- Ensure `TestWidgetsFlutterBinding.ensureInitialized()` is called for tests using Flutter APIs

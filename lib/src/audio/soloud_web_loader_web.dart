import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Injects the flutter_soloud WASM scripts into the DOM and waits for them
/// to finish loading. Safe to call multiple times — subsequent calls are no-ops.
Future<void> loadSoLoudWeb() async {
  final doc = web.document;

  // Already injected?
  if (doc.querySelector('script[data-soloud]') != null) return;

  const scripts = [
    'assets/packages/flutter_soloud/web/libflutter_soloud_plugin.js',
    'assets/packages/flutter_soloud/web/init_module.dart.js',
  ];

  for (final src in scripts) {
    final script = (doc.createElement('script') as web.HTMLScriptElement)
      ..src = src
      ..dataset['soloud'] = 'true';

    final completer = Completer<void>();
    script.onload = ((web.Event _) => completer.complete()).toJS;
    script.onerror = ((web.Event _) => completer.completeError(
      'Failed to load $src',
    )).toJS;

    doc.head!.appendChild(script);
    await completer.future;
  }
}

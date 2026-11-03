// Writes the docs site's files for AI tools from doc/guides/:
//
//     dart run tool/llms_txt.dart [--out build/llms] [--site https://engine.justunknown.com]
//
// - llms.txt: the guides, listed by section with their summaries
//   (https://llmstxt.org), each linking to its Markdown page;
// - llms-full.txt: every guide in one file, in the site's order;
// - docs/<slug>.md: each guide as Markdown, next to the site's /docs/<slug>.
//
// The docs site is a Flutter app, so a plain fetch of a page gets only its
// loading shell. Copy these files into the site's `web/` folder: a host
// serves a file that exists before rewriting the rest to the app.

import 'dart:io';

void main(List<String> args) {
  final out = Directory(_option(args, '--out') ?? 'build/llms');
  final site = (_option(args, '--site') ?? 'https://engine.justunknown.com')
      .replaceAll(RegExp(r'/+$'), '');
  final guides = Directory('doc/guides');
  if (!guides.existsSync()) {
    stderr.writeln('Run this in the just_game_engine package: no doc/guides.');
    exitCode = 2;
    return;
  }
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final version = _field(pubspec, 'version') ?? '';
  final description = _field(pubspec, 'description') ?? '';
  final sections = readGuideIndex(
    File('${guides.path}/README.md').readAsStringSync(),
  );

  final index = StringBuffer()
    ..writeln('# Just Game Engine')
    ..writeln()
    ..writeln('> $description')
    ..writeln()
    ..writeln(
      'These guides are for just_game_engine $version (pub.dev). A game '
      'depends on `just_game_engine`; its level editor is '
      '`just_game_engine_editor` (a dev dependency, never shipped), and the '
      '`just` CLI (`just_core_cli` with `just_game_engine_cli`) creates, '
      'runs, checks and upgrades games. In a game, `just game mcp` serves '
      'these guides and the API of the exact versions the game resolved to '
      'an AI assistant over MCP.',
    );
  final full = StringBuffer()
    ..writeln('# Just Game Engine $version: the guides')
    ..writeln()
    ..writeln('> $description');
  final pages = Directory('${out.path}/docs')..createSync(recursive: true);
  var count = 0;
  for (final section in sections) {
    index
      ..writeln()
      ..writeln('## ${section.name}')
      ..writeln();
    for (final g in section.guides) {
      final text = File('${guides.path}/${g.slug}.md').readAsStringSync();
      File('${pages.path}/${g.slug}.md').writeAsStringSync(text);
      index.writeln('- [${g.title}]($site/docs/${g.slug}.md): ${g.summary}');
      full
        ..writeln()
        ..writeln('---')
        ..writeln()
        ..writeln('<!-- $site/docs/${g.slug} -->')
        ..writeln()
        ..write(text.endsWith('\n') ? text : '$text\n');
      count++;
    }
  }
  index
    ..writeln()
    ..writeln('## Optional')
    ..writeln()
    ..writeln(
      '- [API reference](https://pub.dev/documentation/just_game_engine/'
      'latest/): every public class and member, from the doc comments',
    )
    ..writeln(
      '- [Examples](https://examples.engine.justunknown.com/): the engine '
      'feature by feature, running',
    );
  File('${out.path}/llms.txt').writeAsStringSync(index.toString());
  File('${out.path}/llms-full.txt').writeAsStringSync(full.toString());
  stdout.writeln(
    'Wrote llms.txt, llms-full.txt and $count guides to ${out.path}/.',
  );
}

/// A section of doc/guides/README.md and its guides, in order.
class GuideSection {
  GuideSection(this.name);

  final String name;
  final List<GuideEntry> guides = [];
}

/// One `- [Title](slug.md): summary` line of doc/guides/README.md.
class GuideEntry {
  GuideEntry(this.slug, this.title, this.summary);

  final String slug;
  final String title;
  final String summary;
}

/// The sections of [readme] (`## Section`) and the guides listed under each.
List<GuideSection> readGuideIndex(String readme) {
  final sections = <GuideSection>[];
  final entry = RegExp(r'^- \[(.+?)\]\(([\w-]+)\.md\):\s*(.*)$');
  for (final line in readme.split('\n').map((l) => l.trimRight())) {
    if (line.startsWith('## ')) {
      sections.add(GuideSection(line.substring(3).trim()));
    } else if (entry.firstMatch(line) case final m? when sections.isNotEmpty) {
      sections.last.guides.add(GuideEntry(m[2]!, m[1]!, m[3]!));
    }
  }
  return sections;
}

String? _option(List<String> args, String name) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

/// A top-level `key: value` of a pubspec, unquoted.
String? _field(String yaml, String key) {
  final m = RegExp('^$key:\\s*(.+)\$', multiLine: true).firstMatch(yaml);
  final v = m?.group(1)?.trim();
  if (v == null) return null;
  return v.length > 1 && (v.startsWith('"') || v.startsWith("'"))
      ? v.substring(1, v.length - 1)
      : v;
}

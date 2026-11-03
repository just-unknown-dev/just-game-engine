// The guides in doc/guides/: listed once each in its README, in the order
// and with the titles and summaries the pages themselves give — what
// `just game mcp` and tool/llms_txt.dart read — and every library a guide
// imports from this package is one it has.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/llms_txt.dart' as llms;

void main() {
  final dir = Directory('doc/guides');
  final sections = llms.readGuideIndex(
    File('${dir.path}/README.md').readAsStringSync(),
  );
  final listed = [
    for (final s in sections)
      for (final g in s.guides) (section: s.name, guide: g),
  ];

  test('every guide is listed once, and every listed guide exists', () {
    final files = {
      for (final f in dir.listSync().whereType<File>())
        if (f.path.endsWith('.md') && !f.path.endsWith('README.md'))
          f.uri.pathSegments.last.replaceAll('.md', ''),
    };
    final slugs = [for (final e in listed) e.guide.slug];
    expect(slugs.toSet().length, slugs.length, reason: 'listed twice');
    expect(slugs.toSet(), files);
  });

  test("each page's title, section and summary match the README", () {
    for (final (:section, :guide) in listed) {
      final lines = File(
        '${dir.path}/${guide.slug}.md',
      ).readAsLinesSync();
      expect(lines.first, '# ${guide.title}', reason: guide.slug);
      expect(
        lines[2],
        '_${section}_ · ${guide.summary}',
        reason: guide.slug,
      );
    }
  });

  test("the package's libraries the guides import exist", () {
    final import = RegExp(r'package:just_game_engine/([\w/]+\.dart)');
    for (final (section: _, :guide) in listed) {
      final text = File('${dir.path}/${guide.slug}.md').readAsStringSync();
      for (final m in import.allMatches(text)) {
        expect(
          File('lib/${m[1]}').existsSync(),
          isTrue,
          reason: '${guide.slug} imports ${m[0]}',
        );
      }
    }
  });
}

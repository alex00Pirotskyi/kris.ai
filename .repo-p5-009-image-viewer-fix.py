from pathlib import Path

FIXTURES = Path('lib/product/p5_information_architecture/p5_fixtures.dart')
VIEWERS = Path('lib/product/p5_information_architecture/p5_verification_workspaces.dart')
TEST = Path('test/product/p5_information_architecture/p5_evidence_viewers_test.dart')

PNG_BASE64 = (
    'iVBORw0KGgoAAAANSUhEUgAAAEAAAAAkCAIAAAC2bqvFAAABJ0lEQVR4nO2ZwQ2DMAxF'
    'SdUxeusCZYBK7AHjwR5IDMBKPSBFVhIc+0dgqPJPIGLrv8QGAu71/jR31sPaQKkqgLWe'
    '9GSYVisfKo1964//awU2Ub6rKa6R26+AJcA2nYWNZwZA3Zcw2ADEjodpxTAMABijAMPZAI'
    'HFsW+Dm56WAQcAyjd2Hxz4YfK0IADQgnvuk6fytAhAsgVVGZLPSqyc1AB7Sfl1p5f4J7'
    '22nHQAWAuWrw+TQQEgb0FJFK9gapgoKYCqBf1gzH0wno8SAUh8ZGsXe8nNRuUB5D7ilpD'
    '7gJUBAGYxHnPoBoMDgGuA1u7R2yMOQHgfYGJP2NxlSug0H7DyTXxl901yU081LzOWt/t2W'
    'KBWdVNvLUe/TtcvcwZy9f+AsSqAtX4jOZqZSB0k/gAAAABJRU5ErkJggg=='
)


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    return text.replace(old, new, 1)


fixtures = FIXTURES.read_text(encoding='utf-8')
fixtures = replace_once(
    fixtures,
    "import 'p5_models.dart';\n",
    "import 'dart:convert';\n\nimport 'p5_models.dart';\n",
    'fixtures dart:convert import',
)
fixtures = replace_once(
    fixtures,
    "      P5EvidenceKind.image =>\n        'dimensions=640x360\\nalt=Deterministic saved-run image preview\\nsource=fixture://evidence/$runId/preview.png',",
    f"      P5EvidenceKind.image => '{PNG_BASE64}',",
    'image fixture payload',
)
fixtures = replace_once(
    fixtures,
    '      byteLength: content.length,',
    "      byteLength: kind == P5EvidenceKind.image\n          ? base64Decode(content).length\n          : utf8.encode(content).length,",
    'fixture byte length',
)
FIXTURES.write_text(fixtures, encoding='utf-8', newline='\n')

viewers = VIEWERS.read_text(encoding='utf-8')
old_image_viewer = """      case P5EvidenceKind.image:
        return Container(
          key: const Key('evidence-image-preview'),
          height: 180,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.image_outlined, size: 64),
              const SizedBox(height: 8),
              const Text('640 × 360 deterministic image preview'),
              Text(fixture.content.split('\\n').last),
            ],
          ),
        );
"""
new_image_viewer = """      case P5EvidenceKind.image:
        try {
          final imageBytes = base64Decode(fixture.content);
          return Container(
            key: const Key('evidence-image-preview'),
            height: 180,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Semantics(
                  image: true,
                  label: 'Deterministic saved-run image preview',
                  child: Image.memory(
                    imageBytes,
                    key: const Key('p5-evidence-image-bytes'),
                    width: 160,
                    height: 90,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.none,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) => const Text(
                      'Saved image bytes could not be decoded.',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('64 × 36 deterministic PNG fixture preview'),
              ],
            ),
          );
        } on FormatException {
          return const _BoundaryNotice(
            message:
                'Saved image evidence is malformed and cannot be previewed.',
          );
        }
"""
viewers = replace_once(
    viewers,
    old_image_viewer,
    new_image_viewer,
    'image viewer implementation',
)
VIEWERS.write_text(viewers, encoding='utf-8', newline='\n')

test = TEST.read_text(encoding='utf-8')
test = replace_once(
    test,
    "import 'package:flutter/material.dart';\n",
    "import 'dart:convert';\n\nimport 'package:flutter/material.dart';\n",
    'test dart:convert import',
)
test = replace_once(
    test,
    """      expect(evidence.every((item) => item.runId == run.id), isTrue);
      expect(evidence.every((item) => item.byteLength > 0), isTrue);
""",
    """      expect(evidence.every((item) => item.runId == run.id), isTrue);
      expect(evidence.every((item) => item.byteLength > 0), isTrue);
      final image = evidence.singleWhere(
        (item) => item.kind == P5EvidenceKind.image,
      );
      final imageBytes = base64Decode(image.content);
      expect(image.mediaType, 'image/png');
      expect(image.byteLength, imageBytes.length);
      expect(
        imageBytes.take(8),
        orderedEquals(<int>[137, 80, 78, 71, 13, 10, 26, 10]),
      );
""",
    'fixture PNG contract',
)
test = replace_once(
    test,
    """      final viewer = find.byKey(Key('evidence-viewer-${kind.name}'));
      expect(viewer, findsOneWidget);
      expect(controller.state.selectedEvidenceId, contains(kind.name));
""",
    """      final viewer = find.byKey(Key('evidence-viewer-${kind.name}'));
      expect(viewer, findsOneWidget);
      expect(controller.state.selectedEvidenceId, contains(kind.name));
      if (kind == P5EvidenceKind.image) {
        final image = find.descendant(
          of: viewer,
          matching: find.byKey(const Key('p5-evidence-image-bytes')),
        );
        expect(image, findsOneWidget);
        final widget = tester.widget<Image>(image);
        expect(widget.image, isA<MemoryImage>());
        final provider = widget.image as MemoryImage;
        expect(
          provider.bytes.take(8),
          orderedEquals(<int>[137, 80, 78, 71, 13, 10, 26, 10]),
        );
      }
""",
    'widget PNG contract',
)
TEST.write_text(test, encoding='utf-8', newline='\n')

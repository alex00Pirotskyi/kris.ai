from pathlib import Path

path = Path('test/product/p5_information_architecture/p5_evidence_viewers_test.dart')
text = path.read_text(encoding='utf-8')
old = "      expect(evidence.map((item) => item.kind).toSet(), P5EvidenceKind.values.toSet());\n"
new = "      final kinds = evidence.map((item) => item.kind).toSet();\n      expect(kinds, hasLength(P5EvidenceKind.values.length));\n      expect(kinds, containsAll(P5EvidenceKind.values));\n"
count = text.count(old)
if count != 1:
    raise SystemExit(f'expected one evidence-kind assertion anchor, found {count}')
path.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')

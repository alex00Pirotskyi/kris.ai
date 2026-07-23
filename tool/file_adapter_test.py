#!/usr/bin/env python3
"""Executable v1.8 file-adapter gates."""
from __future__ import annotations

import argparse
import dataclasses
import json
import os
from pathlib import Path
import tempfile
import time
import zipfile

import file_adapters as fa


@dataclasses.dataclass
class Result:
    name: str
    passed: bool
    detail: str
    durationMs: int



def duration_ms(started: float) -> int:
    if "SOURCE_DATE_EPOCH" in os.environ:
        return 0
    return int((time.monotonic() - started) * 1000)

def case(name, action, results):
    started = time.monotonic()
    try:
        detail = action()
        results.append(Result(name, True, detail, duration_ms(started)))
    except Exception as exc:  # noqa: BLE001
        results.append(Result(name, False, f"{type(exc).__name__}: {exc}", duration_ms(started)))


def require(condition, detail):
    if not condition:
        raise AssertionError(detail)
    return detail


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--json-output', type=Path)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    results: list[Result] = []

    with tempfile.TemporaryDirectory(prefix='kristin-v180-adapters-') as tmp:
        root = Path(tmp)
        (root / 'sample.txt').write_text('hello world\n', encoding='utf-8')
        (root / 'sample.json').write_text('{"ok": true}\n', encoding='utf-8')
        (root / 'sample.xml').write_text('<root><value>ok</value></root>\n', encoding='utf-8')
        (root / 'sample.csv').write_text('a,b\n1,2\n', encoding='utf-8')
        (root / 'sample.rtf').write_text('{\\rtf1\\ansi hello}', encoding='utf-8')
        (root / 'sample.eml').write_text('From: a@example.com\nSubject: Hi\nDate: Tue, 22 Jul 2026 10:00:00 +0000\n\nBody\n', encoding='utf-8')
        (root / 'sample.pdf').write_bytes(b'%PDF-1.4\n1 0 obj\n<<>>\nendobj\ntrailer\n<<>>\n%%EOF\n')
        with zipfile.ZipFile(root / 'sample.zip', 'w') as archive:
            archive.writestr('folder/data.txt', 'ok')
        with zipfile.ZipFile(root / 'sample.docx', 'w') as archive:
            archive.writestr('[Content_Types].xml', '<Types/>')
            archive.writestr('word/document.xml', '<w:document/>')
        with zipfile.ZipFile(root / 'sample.epub', 'w') as archive:
            archive.writestr('mimetype', 'application/epub+zip')
            archive.writestr('META-INF/container.xml', '<container/>')
        with zipfile.ZipFile(root / 'sample.odt', 'w') as archive:
            archive.writestr('mimetype', 'application/vnd.oasis.opendocument.text')
            archive.writestr('content.xml', '<office:document/>')
        (root / 'sample.png').write_bytes(bytes.fromhex('89504e470d0a1a0a0000000d4948445200000001000000010802000000907753de0000000c49444154789c6360000000020001e221bc330000000049454e44ae426082'))

        case('Registry document is schema-shaped', _registry_case, results)
        case('Text adapter detects and validates UTF-8 text', lambda: _validate_case(root / 'sample.txt', 'text'), results)
        case('JSON adapter reopens structured data', lambda: _validate_case(root / 'sample.json', 'json'), results)
        case('XML adapter reopens XML', lambda: _validate_case(root / 'sample.xml', 'xml'), results)
        case('CSV adapter reopens CSV', lambda: _validate_case(root / 'sample.csv', 'csv'), results)
        case('PNG image adapter detects dimensions', lambda: _png_case(root / 'sample.png'), results)
        case('ZIP adapter reopens safe archive', lambda: _validate_case(root / 'sample.zip', 'zip'), results)
        case('PDF adapter validates signature and EOF', lambda: _validate_case(root / 'sample.pdf', 'pdf'), results)
        case('OOXML adapter validates DOCX package', lambda: _validate_case(root / 'sample.docx', 'ooxml'), results)
        case('OpenDocument adapter validates ODT package', lambda: _validate_case(root / 'sample.odt', 'opendocument'), results)
        case('RTF adapter validates header', lambda: _validate_case(root / 'sample.rtf', 'rtf'), results)
        case('EPUB adapter validates mimetype', lambda: _validate_case(root / 'sample.epub', 'epub'), results)
        case('Email adapter parses RFC822 headers', lambda: _validate_case(root / 'sample.eml', 'email'), results)
        case('Unknown binary falls back to plugin tier', lambda: _unknown_case(root), results)

    payload = {
        'version': fa.VERSION,
        'passed': all(item.passed for item in results),
        'passedCount': sum(item.passed for item in results),
        'caseCount': len(results),
        'results': [dataclasses.asdict(item) for item in results],
    }
    if args.json_output:
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding='utf-8')
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if payload['passed'] else 1


def _registry_case() -> str:
    doc = fa.registry_document()
    return require(doc['schemaVersion'] == '1.0.0' and len(doc['adapters']) >= 10, 'registry exposes native and sandboxed-core adapters')


def _validate_case(path: Path, expected_adapter: str) -> str:
    info = fa.inspect(path)
    ok, detail = fa.validate(path)
    return require(info['adapterId'] == expected_adapter and ok, detail)


def _png_case(path: Path) -> str:
    info = fa.inspect(path)
    ok, detail = fa.validate(path)
    return require(info.get('width') == 1 and info.get('height') == 1 and ok, detail)


def _unknown_case(root: Path) -> str:
    path = root / 'sample.bin'
    path.write_bytes(bytes([0, 1, 2]))
    info = fa.inspect(path)
    return require(info['tier'] == 'plugin', 'unknown extension falls back to plugin tier')


if __name__ == '__main__':
    raise SystemExit(main())

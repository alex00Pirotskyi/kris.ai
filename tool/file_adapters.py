#!/usr/bin/env python3
"""Deterministic core file-adapter registry for Kristin v1.8."""
from __future__ import annotations

from dataclasses import dataclass
import email
import hashlib
import json
from pathlib import Path
import struct
import zipfile
import xml.etree.ElementTree as ET

VERSION = "1.9.0+190"
PNG_SIGNATURE = bytes.fromhex('89504e470d0a1a0a')
JPEG_SIGNATURE = bytes.fromhex('ffd8ff')
GIF_SIGNATURES = (b'GIF87a', b'GIF89a')
WEBP_SIGNATURE = b'RIFF'


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


@dataclass(frozen=True)
class FileAdapter:
    id: str
    tier: str
    extensions: tuple[str, ...]
    media_types: tuple[str, ...]
    capabilities: tuple[str, ...]
    sandbox_required: bool = False


BUILTINS: tuple[FileAdapter, ...] = (
    FileAdapter('text', 'native', ('txt', 'md', 'log'), ('text/plain', 'text/markdown'), ('detect', 'inspect', 'extract', 'preview', 'validate')),
    FileAdapter('json', 'native', ('json',), ('application/json',), ('detect', 'inspect', 'extract', 'preview', 'validate')),
    FileAdapter('yaml', 'native', ('yaml', 'yml'), ('application/yaml', 'text/yaml'), ('detect', 'inspect', 'extract', 'preview', 'validate')),
    FileAdapter('xml', 'native', ('xml',), ('application/xml', 'text/xml'), ('detect', 'inspect', 'extract', 'preview', 'validate')),
    FileAdapter('csv', 'native', ('csv',), ('text/csv',), ('detect', 'inspect', 'extract', 'preview', 'validate')),
    FileAdapter('image', 'native', ('png', 'jpg', 'jpeg', 'gif', 'webp'), ('image/png', 'image/jpeg', 'image/gif', 'image/webp'), ('detect', 'inspect', 'preview', 'validate')),
    FileAdapter('zip', 'native', ('zip',), ('application/zip',), ('detect', 'inspect', 'preview', 'validate')),
    FileAdapter('pdf', 'sandboxed_core', ('pdf',), ('application/pdf',), ('detect', 'inspect', 'preview', 'validate'), sandbox_required=True),
    FileAdapter('ooxml', 'sandboxed_core', ('docx', 'xlsx', 'pptx'), ('application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'application/vnd.openxmlformats-officedocument.presentationml.presentation'), ('detect', 'inspect', 'preview', 'validate'), sandbox_required=True),
    FileAdapter('opendocument', 'sandboxed_core', ('odt',), ('application/vnd.oasis.opendocument.text',), ('detect', 'inspect', 'preview', 'validate'), sandbox_required=True),
    FileAdapter('rtf', 'sandboxed_core', ('rtf',), ('application/rtf', 'text/rtf'), ('detect', 'inspect', 'extract', 'preview', 'validate'), sandbox_required=True),
    FileAdapter('epub', 'sandboxed_core', ('epub',), ('application/epub+zip',), ('detect', 'inspect', 'preview', 'validate'), sandbox_required=True),
    FileAdapter('email', 'sandboxed_core', ('eml',), ('message/rfc822',), ('detect', 'inspect', 'extract', 'preview', 'validate'), sandbox_required=True),
)


def registry_document() -> dict[str, object]:
    return {
        'schemaVersion': '1.0.0',
        'adapters': [
            {
                'id': adapter.id,
                'tier': adapter.tier,
                'sandboxRequired': adapter.sandbox_required,
                'extensions': list(adapter.extensions),
                'mediaTypes': list(adapter.media_types),
                'capabilities': list(adapter.capabilities),
            }
            for adapter in BUILTINS
        ],
    }


def detect(path: Path) -> FileAdapter:
    ext = path.suffix.lower().lstrip('.')
    for adapter in BUILTINS:
        if ext in adapter.extensions:
            return adapter
    return FileAdapter('binary', 'plugin', (ext,), (), ('detect', 'inspect'), sandbox_required=True)


def _png_dimensions(data: bytes) -> tuple[int, int] | None:
    if data.startswith(PNG_SIGNATURE) and len(data) >= 24:
        return struct.unpack('>II', data[16:24])
    return None


def inspect(path: Path) -> dict[str, object]:
    adapter = detect(path)
    data = path.read_bytes()
    info: dict[str, object] = {
        'path': str(path),
        'adapterId': adapter.id,
        'tier': adapter.tier,
        'sandboxRequired': adapter.sandbox_required,
        'sizeBytes': len(data),
        'sha256': sha256_hex(data),
        'extension': path.suffix.lower(),
    }
    if adapter.id == 'image':
        dims = _png_dimensions(data)
        if dims:
            info['width'], info['height'] = dims
    if adapter.id in {'zip', 'ooxml', 'opendocument', 'epub'}:
        with zipfile.ZipFile(path, 'r') as archive:
            info['memberCount'] = len(archive.namelist())
            info['members'] = archive.namelist()[:20]
    if adapter.id == 'email':
        message = email.message_from_bytes(data)
        info['subject'] = message.get('Subject', '')
    return info


def validate(path: Path) -> tuple[bool, str]:
    adapter = detect(path)
    data = path.read_bytes()
    try:
        if adapter.id == 'text':
            data.decode('utf-8')
            return True, 'UTF-8 text reopened successfully'
        if adapter.id == 'json':
            json.loads(data.decode('utf-8'))
            return True, 'JSON parsed successfully'
        if adapter.id == 'yaml':
            text = data.decode('utf-8')
            if not text.strip():
                raise ValueError('empty yaml')
            return True, 'YAML text is non-empty and UTF-8 decodable'
        if adapter.id == 'xml':
            ET.fromstring(data.decode('utf-8'))
            return True, 'XML parsed successfully'
        if adapter.id == 'csv':
            text = data.decode('utf-8')
            if ',' not in text and '\n' not in text:
                raise ValueError('not csv-like')
            return True, 'CSV reopened as UTF-8 text'
        if adapter.id == 'image':
            if data.startswith(PNG_SIGNATURE) or data.startswith(JPEG_SIGNATURE) or data[:6] in GIF_SIGNATURES or data.startswith(WEBP_SIGNATURE):
                return True, 'image signature recognized'
            raise ValueError('unknown image signature')
        if adapter.id == 'zip':
            with zipfile.ZipFile(path, 'r') as archive:
                if archive.testzip() is not None:
                    raise ValueError('zip corruption detected')
            return True, 'ZIP reopened successfully'
        if adapter.id == 'pdf':
            if not data.startswith(b'%PDF-'):
                raise ValueError('missing PDF header')
            if b'%%EOF' not in data[-2048:]:
                raise ValueError('missing PDF EOF marker')
            return True, 'PDF header and EOF marker detected'
        if adapter.id == 'ooxml':
            with zipfile.ZipFile(path, 'r') as archive:
                names = set(archive.namelist())
                if '[Content_Types].xml' not in names:
                    raise ValueError('OOXML content types missing')
                suffix = path.suffix.lower()
                if suffix == '.docx' and not any(name.startswith('word/') for name in names):
                    raise ValueError('DOCX word tree missing')
                if suffix == '.xlsx' and not any(name.startswith('xl/') for name in names):
                    raise ValueError('XLSX xl tree missing')
                if suffix == '.pptx' and not any(name.startswith('ppt/') for name in names):
                    raise ValueError('PPTX ppt tree missing')
            return True, 'OOXML package reopened successfully'
        if adapter.id == 'opendocument':
            with zipfile.ZipFile(path, 'r') as archive:
                mimetype = archive.read('mimetype').decode('utf-8')
                if not mimetype.startswith('application/vnd.oasis.opendocument'):
                    raise ValueError('OpenDocument mimetype missing')
            return True, 'OpenDocument package reopened successfully'
        if adapter.id == 'rtf':
            if not data.lstrip().startswith(b'{\\rtf'):
                raise ValueError('RTF header missing')
            return True, 'RTF header recognized'
        if adapter.id == 'epub':
            with zipfile.ZipFile(path, 'r') as archive:
                mimetype = archive.read('mimetype').decode('utf-8')
                if mimetype != 'application/epub+zip':
                    raise ValueError('EPUB mimetype mismatch')
            return True, 'EPUB package reopened successfully'
        if adapter.id == 'email':
            message = email.message_from_bytes(data)
            if not (message.get('From') or message.get('Subject') or message.get('Date')):
                raise ValueError('email headers missing')
            return True, 'RFC822 message parsed successfully'
    except Exception as exc:  # noqa: BLE001
        return False, f'{type(exc).__name__}: {exc}'
    return False, 'unsupported adapter'

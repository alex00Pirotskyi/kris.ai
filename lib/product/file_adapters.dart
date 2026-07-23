import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'crypto_utils.dart';

enum FileAdapterTier { native, sandboxedCore, plugin }

enum FileAdapterCapability {
  detect,
  inspect,
  extract,
  preview,
  create,
  transform,
  validate,
}

class FileAdapterDescriptor {
  const FileAdapterDescriptor({
    required this.id,
    required this.tier,
    required this.extensions,
    required this.mediaTypes,
    required this.capabilities,
    this.sandboxRequired = false,
  });

  final String id;
  final FileAdapterTier tier;
  final Set<String> extensions;
  final Set<String> mediaTypes;
  final Set<FileAdapterCapability> capabilities;
  final bool sandboxRequired;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'tier': tier.name,
        'sandboxRequired': sandboxRequired,
        'extensions': extensions.toList()..sort(),
        'mediaTypes': mediaTypes.toList()..sort(),
        'capabilities': capabilities.map((item) => item.name).toList()..sort(),
      };
}

class FileInspectionResult {
  const FileInspectionResult({
    required this.adapter,
    required this.path,
    required this.sizeBytes,
    required this.sha256,
    required this.metadata,
  });

  final FileAdapterDescriptor adapter;
  final String path;
  final int sizeBytes;
  final String sha256;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'adapter': adapter.toJson(),
        'path': path,
        'sizeBytes': sizeBytes,
        'sha256': sha256,
        'metadata': metadata,
      };
}

class FileAdapterRegistry {
  const FileAdapterRegistry();

  List<FileAdapterDescriptor> get all => const <FileAdapterDescriptor>[
        FileAdapterDescriptor(
          id: 'text',
          tier: FileAdapterTier.native,
          extensions: <String>{'txt', 'md', 'log'},
          mediaTypes: <String>{'text/plain', 'text/markdown'},
          capabilities: <FileAdapterCapability>{
            FileAdapterCapability.detect,
            FileAdapterCapability.inspect,
            FileAdapterCapability.extract,
            FileAdapterCapability.preview,
            FileAdapterCapability.validate,
          },
        ),
        FileAdapterDescriptor(
          id: 'json',
          tier: FileAdapterTier.native,
          extensions: <String>{'json'},
          mediaTypes: <String>{'application/json'},
          capabilities: <FileAdapterCapability>{
            FileAdapterCapability.detect,
            FileAdapterCapability.inspect,
            FileAdapterCapability.extract,
            FileAdapterCapability.preview,
            FileAdapterCapability.validate,
          },
        ),
        FileAdapterDescriptor(
          id: 'yaml',
          tier: FileAdapterTier.native,
          extensions: <String>{'yaml', 'yml'},
          mediaTypes: <String>{'application/yaml', 'text/yaml'},
          capabilities: <FileAdapterCapability>{
            FileAdapterCapability.detect,
            FileAdapterCapability.inspect,
            FileAdapterCapability.extract,
            FileAdapterCapability.preview,
            FileAdapterCapability.validate,
          },
        ),
        FileAdapterDescriptor(
          id: 'xml',
          tier: FileAdapterTier.native,
          extensions: <String>{'xml'},
          mediaTypes: <String>{'application/xml', 'text/xml'},
          capabilities: <FileAdapterCapability>{
            FileAdapterCapability.detect,
            FileAdapterCapability.inspect,
            FileAdapterCapability.extract,
            FileAdapterCapability.preview,
            FileAdapterCapability.validate,
          },
        ),
        FileAdapterDescriptor(
          id: 'csv',
          tier: FileAdapterTier.native,
          extensions: <String>{'csv'},
          mediaTypes: <String>{'text/csv'},
          capabilities: <FileAdapterCapability>{
            FileAdapterCapability.detect,
            FileAdapterCapability.inspect,
            FileAdapterCapability.extract,
            FileAdapterCapability.preview,
            FileAdapterCapability.validate,
          },
        ),
        FileAdapterDescriptor(
          id: 'image',
          tier: FileAdapterTier.native,
          extensions: <String>{'png', 'jpg', 'jpeg', 'gif', 'webp'},
          mediaTypes: <String>{'image/png', 'image/jpeg', 'image/gif', 'image/webp'},
          capabilities: <FileAdapterCapability>{
            FileAdapterCapability.detect,
            FileAdapterCapability.inspect,
            FileAdapterCapability.preview,
            FileAdapterCapability.validate,
          },
        ),
        FileAdapterDescriptor(
          id: 'zip',
          tier: FileAdapterTier.native,
          extensions: <String>{'zip'},
          mediaTypes: <String>{'application/zip'},
          capabilities: <FileAdapterCapability>{
            FileAdapterCapability.detect,
            FileAdapterCapability.inspect,
            FileAdapterCapability.preview,
            FileAdapterCapability.validate,
          },
        ),
        FileAdapterDescriptor(
          id: 'pdf',
          tier: FileAdapterTier.sandboxedCore,
          extensions: <String>{'pdf'},
          mediaTypes: <String>{'application/pdf'},
          capabilities: <FileAdapterCapability>{
            FileAdapterCapability.detect,
            FileAdapterCapability.inspect,
            FileAdapterCapability.preview,
            FileAdapterCapability.validate,
          },
          sandboxRequired: true,
        ),
        FileAdapterDescriptor(
          id: 'ooxml',
          tier: FileAdapterTier.sandboxedCore,
          extensions: <String>{'docx', 'xlsx', 'pptx'},
          mediaTypes: <String>{
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            'application/vnd.openxmlformats-officedocument.presentationml.presentation',
          },
          capabilities: <FileAdapterCapability>{
            FileAdapterCapability.detect,
            FileAdapterCapability.inspect,
            FileAdapterCapability.preview,
            FileAdapterCapability.validate,
          },
          sandboxRequired: true,
        ),
        FileAdapterDescriptor(
          id: 'opendocument',
          tier: FileAdapterTier.sandboxedCore,
          extensions: <String>{'odt'},
          mediaTypes: <String>{'application/vnd.oasis.opendocument.text'},
          capabilities: <FileAdapterCapability>{
            FileAdapterCapability.detect,
            FileAdapterCapability.inspect,
            FileAdapterCapability.preview,
            FileAdapterCapability.validate,
          },
          sandboxRequired: true,
        ),
        FileAdapterDescriptor(
          id: 'rtf',
          tier: FileAdapterTier.sandboxedCore,
          extensions: <String>{'rtf'},
          mediaTypes: <String>{'application/rtf', 'text/rtf'},
          capabilities: <FileAdapterCapability>{
            FileAdapterCapability.detect,
            FileAdapterCapability.inspect,
            FileAdapterCapability.extract,
            FileAdapterCapability.preview,
            FileAdapterCapability.validate,
          },
          sandboxRequired: true,
        ),
        FileAdapterDescriptor(
          id: 'epub',
          tier: FileAdapterTier.sandboxedCore,
          extensions: <String>{'epub'},
          mediaTypes: <String>{'application/epub+zip'},
          capabilities: <FileAdapterCapability>{
            FileAdapterCapability.detect,
            FileAdapterCapability.inspect,
            FileAdapterCapability.preview,
            FileAdapterCapability.validate,
          },
          sandboxRequired: true,
        ),
        FileAdapterDescriptor(
          id: 'email',
          tier: FileAdapterTier.sandboxedCore,
          extensions: <String>{'eml'},
          mediaTypes: <String>{'message/rfc822'},
          capabilities: <FileAdapterCapability>{
            FileAdapterCapability.detect,
            FileAdapterCapability.inspect,
            FileAdapterCapability.extract,
            FileAdapterCapability.preview,
            FileAdapterCapability.validate,
          },
          sandboxRequired: true,
        ),
      ];

  FileAdapterDescriptor detect(File file) {
    final extension = file.path.contains('.')
        ? file.path.split('.').last.toLowerCase()
        : '';
    for (final adapter in all) {
      if (adapter.extensions.contains(extension)) {
        return adapter;
      }
    }
    return const FileAdapterDescriptor(
      id: 'binary',
      tier: FileAdapterTier.plugin,
      extensions: <String>{},
      mediaTypes: <String>{'application/octet-stream'},
      capabilities: <FileAdapterCapability>{
        FileAdapterCapability.detect,
        FileAdapterCapability.inspect,
      },
      sandboxRequired: true,
    );
  }

  Future<FileInspectionResult> inspect(File file) async {
    final bytes = await file.readAsBytes();
    final adapter = detect(file);
    final metadata = <String, dynamic>{
      'extension': file.path.contains('.')
          ? file.path.split('.').last.toLowerCase()
          : '',
    };
    if (adapter.id == 'image' &&
        bytes.length >= 24 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      final view = ByteData.sublistView(Uint8List.fromList(bytes), 16, 24);
      metadata['width'] = view.getUint32(0, Endian.big);
      metadata['height'] = view.getUint32(4, Endian.big);
    }
    if (adapter.id == 'email') {
      final text = utf8.decode(bytes, allowMalformed: true);
      final subject = RegExp(r'^subject:\s*(.+)$', caseSensitive: false, multiLine: true)
              .firstMatch(text)
              ?.group(1) ??
          '';
      metadata['subject'] = subject.trim();
    }
    return FileInspectionResult(
      adapter: adapter,
      path: file.path,
      sizeBytes: bytes.length,
      sha256: Sha256.hex(bytes),
      metadata: metadata,
    );
  }

  Future<Map<String, dynamic>> validate(File file) async {
    final bytes = await file.readAsBytes();
    final adapter = detect(file);
    try {
      switch (adapter.id) {
        case 'text':
          utf8.decode(bytes);
          break;
        case 'json':
          jsonDecode(utf8.decode(bytes));
          break;
        case 'yaml':
          final text = utf8.decode(bytes);
          if (text.trim().isEmpty) {
            throw StateError('YAML is empty.');
          }
          break;
        case 'xml':
          final text = utf8.decode(bytes);
          if (!text.trimLeft().startsWith('<')) {
            throw StateError('XML does not start with an element.');
          }
          break;
        case 'csv':
          final text = utf8.decode(bytes);
          if (!text.contains(',') && !text.contains('\n')) {
            throw StateError('CSV is not delimited text.');
          }
          break;
        case 'image':
          final isPng = bytes.length >= 4 &&
              bytes[0] == 0x89 &&
              bytes[1] == 0x50 &&
              bytes[2] == 0x4E &&
              bytes[3] == 0x47;
          final isJpeg =
              bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
          final signature = utf8.decode(bytes.take(6).toList(), allowMalformed: true);
          if (!(isPng || isJpeg || signature.startsWith('GIF8') || signature.startsWith('RIFF'))) {
            throw StateError('Image signature is not recognized.');
          }
          break;
        case 'zip':
        case 'ooxml':
        case 'opendocument':
        case 'epub':
          final header = bytes.length >= 4
              ? bytes.take(4).toList()
              : const <int>[];
          final isZip = header.length == 4 &&
              header[0] == 0x50 &&
              header[1] == 0x4B &&
              header[2] == 0x03 &&
              header[3] == 0x04;
          if (!isZip) {
            throw StateError('ZIP container header is missing.');
          }
          break;
        case 'pdf':
          final text = utf8.decode(bytes, allowMalformed: true);
          if (!text.startsWith('%PDF-') || !text.contains('%%EOF')) {
            throw StateError('PDF markers are missing.');
          }
          break;
        case 'rtf':
          final text = utf8.decode(bytes, allowMalformed: true);
          if (!text.trimLeft().startsWith(r'{\rtf')) {
            throw StateError('RTF header is missing.');
          }
          break;
        case 'email':
          final text = utf8.decode(bytes, allowMalformed: true).toLowerCase();
          if (!(text.contains('\nsubject:') ||
              text.contains('\nfrom:') ||
              text.contains('\ndate:') ||
              text.startsWith('from:'))) {
            throw StateError('Email headers are missing.');
          }
          break;
      }
      return <String, dynamic>{'passed': true, 'adapterId': adapter.id};
    } catch (error) {
      return <String, dynamic>{
        'passed': false,
        'adapterId': adapter.id,
        'error': '$error',
      };
    }
  }
}

import 'dart:convert';
import 'dart:io';

import '../crypto_utils.dart';
import '../storage_security.dart';

abstract interface class P3BrowserProfileCipher {
  Future<List<int>> seal(
    List<int> plaintext, {
    required List<int> associatedData,
  });

  Future<List<int>> open(
    List<int> ciphertext, {
    required List<int> associatedData,
  });
}

final class P3BrowserProfileStore {
  P3BrowserProfileStore({
    required Directory root,
    required this.cipher,
    this.maxStateBytes = 2 * 1024 * 1024,
    DateTime Function()? clock,
  }) : root = root.absolute,
       _clock = clock ?? DateTime.now {
    if (maxStateBytes < 1024 || maxStateBytes > 16 * 1024 * 1024) {
      throw StateError('browser_profile_state_budget_invalid');
    }
  }

  static final RegExp _profileId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$');

  final Directory root;
  final P3BrowserProfileCipher cipher;
  final int maxStateBytes;
  final DateTime Function() _clock;

  String _requireProfileId(String value) {
    final id = value.trim();
    if (!_profileId.hasMatch(id)) {
      throw ProductException(
        'browser_profile_id_invalid',
        'Browser profile identifiers must use a bounded safe identifier.',
      );
    }
    return id;
  }

  File _file(String profileId) => File(
    '${root.path}${Platform.pathSeparator}$profileId'
    '${Platform.pathSeparator}state.v1.json',
  );

  List<int> _associatedData(String profileId) => utf8.encode(
    canonicalJson(<String, Object?>{
      'schemaVersion': '1.0.0',
      'recordType': 'kristin-p3-browser-auth-profile-v1',
      'profileId': profileId,
    }),
  );

  Future<void> put(String profileId, Map<String, Object?> state) async {
    final id = _requireProfileId(profileId);
    final plaintext = utf8.encode(canonicalJson(state));
    if (plaintext.isEmpty || plaintext.length > maxStateBytes) {
      throw ProductException(
        'browser_profile_state_budget_exceeded',
        'Browser profile state exceeds its configured storage budget.',
      );
    }
    final aad = _associatedData(id);
    final ciphertext = await cipher.seal(
      List<int>.unmodifiable(plaintext),
      associatedData: List<int>.unmodifiable(aad),
    );
    if (ciphertext.isEmpty || ciphertext.length > maxStateBytes + 64 * 1024) {
      throw ProductException(
        'browser_profile_ciphertext_invalid',
        'Authenticated browser profile encryption returned invalid output.',
      );
    }
    final record = <String, Object?>{
      'schemaVersion': '1.0.0',
      'recordType': 'kristin-p3-browser-auth-profile-v1',
      'profileId': id,
      'ciphertextBase64': base64Encode(ciphertext),
      'ciphertextBytes': ciphertext.length,
      'ciphertextSha256': Sha256.hex(ciphertext),
      'updatedAt': _clock().toUtc().toIso8601String(),
    };
    await AtomicJsonFile(_file(id)).write(record);
  }

  Future<Map<String, Object?>?> get(String profileId) async {
    final id = _requireProfileId(profileId);
    final file = _file(id);
    if (!await file.exists()) return null;
    final raw = await AtomicJsonFile(file).read();
    if (raw is! Map) {
      throw ProductException(
        'browser_profile_record_invalid',
        'Browser profile storage record has an invalid shape.',
      );
    }
    final record = raw.map((key, value) => MapEntry(key.toString(), value));
    if (record['schemaVersion'] != '1.0.0' ||
        record['recordType'] != 'kristin-p3-browser-auth-profile-v1' ||
        record['profileId'] != id ||
        record['ciphertextBase64'] is! String ||
        record['ciphertextBytes'] is! int ||
        record['ciphertextSha256'] is! String ||
        record['updatedAt'] is! String) {
      throw ProductException(
        'browser_profile_record_invalid',
        'Browser profile storage record failed schema validation.',
      );
    }
    late final List<int> ciphertext;
    try {
      ciphertext = base64Decode(record['ciphertextBase64']! as String);
    } on FormatException {
      throw ProductException(
        'browser_profile_record_invalid',
        'Browser profile ciphertext encoding is invalid.',
      );
    }
    if (ciphertext.length != record['ciphertextBytes'] ||
        ciphertext.isEmpty ||
        ciphertext.length > maxStateBytes + 64 * 1024 ||
        Sha256.hex(ciphertext) != record['ciphertextSha256']) {
      throw ProductException(
        'browser_profile_record_integrity_failed',
        'Browser profile ciphertext failed integrity validation.',
      );
    }
    final plaintext = await cipher.open(
      List<int>.unmodifiable(ciphertext),
      associatedData: List<int>.unmodifiable(_associatedData(id)),
    );
    if (plaintext.isEmpty || plaintext.length > maxStateBytes) {
      throw ProductException(
        'browser_profile_plaintext_invalid',
        'Decrypted browser profile state is outside the allowed budget.',
      );
    }
    late final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(plaintext));
    } on FormatException {
      throw ProductException(
        'browser_profile_plaintext_invalid',
        'Decrypted browser profile state is not valid JSON.',
      );
    }
    if (decoded is! Map) {
      throw ProductException(
        'browser_profile_plaintext_invalid',
        'Decrypted browser profile state must be a JSON object.',
      );
    }
    return Map<String, Object?>.unmodifiable(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  Future<void> remove(String profileId) async {
    final id = _requireProfileId(profileId);
    final directory = _file(id).parent;
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<List<String>> listProfileIds() async {
    if (!await root.exists()) return const <String>[];
    final ids = <String>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = entity.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .lastOrNull;
      if (name != null &&
          _profileId.hasMatch(name) &&
          await _file(name).exists()) {
        ids.add(name);
      }
    }
    ids.sort();
    return List<String>.unmodifiable(ids);
  }
}

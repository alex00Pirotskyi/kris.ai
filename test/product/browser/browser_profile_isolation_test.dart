import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/browser/browser_profile_store.dart';
import 'package:kristin_local_agent/product/crypto_utils.dart';

void main() {
  test('P3-008 cross-profile ciphertext transplant fails closed', () async {
    final root = await Directory.systemTemp.createTemp('p3-profile-isolation-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final store = P3BrowserProfileStore(
      root: root,
      cipher: _ProfileCipher(),
      clock: () => DateTime.utc(2026, 8, 23),
    );
    await store.put('personal', const <String, Object?>{
      'token': 'personal-secret',
      'cookies': <Object?>[],
    });
    await store.put('work', const <String, Object?>{
      'token': 'work-secret',
      'cookies': <Object?>[],
    });

    expect((await store.get('personal'))?['token'], 'personal-secret');
    expect((await store.get('work'))?['token'], 'work-secret');

    final personalFile = File(
      '${root.path}${Platform.pathSeparator}personal'
      '${Platform.pathSeparator}state.v1.json',
    );
    final workFile = File(
      '${root.path}${Platform.pathSeparator}work'
      '${Platform.pathSeparator}state.v1.json',
    );
    final personalRecord = _record(personalFile);
    final workRecord = _record(workFile);
    final personalCiphertext = _cipherFields(personalRecord);
    final workCiphertext = _cipherFields(workRecord);

    _replaceCipherFields(personalRecord, workCiphertext);
    _replaceCipherFields(workRecord, personalCiphertext);
    await personalFile.writeAsString(jsonEncode(personalRecord), flush: true);
    await workFile.writeAsString(jsonEncode(workRecord), flush: true);

    await expectLater(store.get('personal'), throwsA(isA<StateError>()));
    await expectLater(store.get('work'), throwsA(isA<StateError>()));
  });
}

Map<String, Object?> _record(File file) {
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map) throw StateError('profile_record_not_object');
  return decoded.map((key, value) => MapEntry(key.toString(), value));
}

Map<String, Object?> _cipherFields(Map<String, Object?> record) =>
    <String, Object?>{
      'ciphertextBase64': record['ciphertextBase64'],
      'ciphertextBytes': record['ciphertextBytes'],
      'ciphertextSha256': record['ciphertextSha256'],
    };

void _replaceCipherFields(
  Map<String, Object?> record,
  Map<String, Object?> replacement,
) {
  for (final key in replacement.keys) {
    record[key] = replacement[key];
  }
}

final class _ProfileCipher implements P3BrowserProfileCipher {
  static const int _mask = 0x5a;

  @override
  Future<List<int>> seal(
    List<int> plaintext, {
    required List<int> associatedData,
  }) async {
    final encrypted = plaintext.map((value) => value ^ _mask).toList();
    final tag = utf8.encode(Sha256.hex(<int>[...associatedData, ...encrypted]));
    return <int>[...tag, ...encrypted];
  }

  @override
  Future<List<int>> open(
    List<int> ciphertext, {
    required List<int> associatedData,
  }) async {
    if (ciphertext.length <= 64) throw StateError('ciphertext_invalid');
    final tag = utf8.decode(ciphertext.take(64).toList());
    final encrypted = ciphertext.skip(64).toList();
    final expected = Sha256.hex(<int>[...associatedData, ...encrypted]);
    if (!constantTimeEquals(tag, expected)) {
      throw StateError('ciphertext_authentication_failed');
    }
    return encrypted.map((value) => value ^ _mask).toList();
  }
}

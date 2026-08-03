import 'dart:convert';
import 'dart:typed_data';

Object? _canonicalValue(Object? value) {
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  if (value is double) {
    throw const FormatException(
      'RFC 8785 subset forbids floating-point values',
    );
  }
  if (value is List) {
    return value.map<Object?>(_canonicalValue).toList(growable: false);
  }
  if (value is Map) {
    final keys = value.keys.map((Object? key) {
      if (key is! String) {
        throw const FormatException('manifest object keys must be strings');
      }
      return key;
    }).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalValue(value[key]),
    };
  }
  throw FormatException(
    'unsupported canonical JSON type: ${value.runtimeType}',
  );
}

String canonicalJsonV2(Object? value) => jsonEncode(_canonicalValue(value));

Uint8List hexToBytesV2(String hex) {
  if (hex.length.isOdd) {
    throw const FormatException('hex length must be even');
  }
  return Uint8List.fromList(<int>[
    for (var index = 0; index < hex.length; index += 2)
      int.parse(hex.substring(index, index + 2), radix: 16),
  ]);
}

String bytesToHexV2(List<int> bytes) =>
    bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();

final class _Sha512 {
  static final List<BigInt> _k = <BigInt>[
    BigInt.parse('428a2f98d728ae22', radix: 16),
    BigInt.parse('7137449123ef65cd', radix: 16),
    BigInt.parse('b5c0fbcfec4d3b2f', radix: 16),
    BigInt.parse('e9b5dba58189dbbc', radix: 16),
    BigInt.parse('3956c25bf348b538', radix: 16),
    BigInt.parse('59f111f1b605d019', radix: 16),
    BigInt.parse('923f82a4af194f9b', radix: 16),
    BigInt.parse('ab1c5ed5da6d8118', radix: 16),
    BigInt.parse('d807aa98a3030242', radix: 16),
    BigInt.parse('12835b0145706fbe', radix: 16),
    BigInt.parse('243185be4ee4b28c', radix: 16),
    BigInt.parse('550c7dc3d5ffb4e2', radix: 16),
    BigInt.parse('72be5d74f27b896f', radix: 16),
    BigInt.parse('80deb1fe3b1696b1', radix: 16),
    BigInt.parse('9bdc06a725c71235', radix: 16),
    BigInt.parse('c19bf174cf692694', radix: 16),
    BigInt.parse('e49b69c19ef14ad2', radix: 16),
    BigInt.parse('efbe4786384f25e3', radix: 16),
    BigInt.parse('0fc19dc68b8cd5b5', radix: 16),
    BigInt.parse('240ca1cc77ac9c65', radix: 16),
    BigInt.parse('2de92c6f592b0275', radix: 16),
    BigInt.parse('4a7484aa6ea6e483', radix: 16),
    BigInt.parse('5cb0a9dcbd41fbd4', radix: 16),
    BigInt.parse('76f988da831153b5', radix: 16),
    BigInt.parse('983e5152ee66dfab', radix: 16),
    BigInt.parse('a831c66d2db43210', radix: 16),
    BigInt.parse('b00327c898fb213f', radix: 16),
    BigInt.parse('bf597fc7beef0ee4', radix: 16),
    BigInt.parse('c6e00bf33da88fc2', radix: 16),
    BigInt.parse('d5a79147930aa725', radix: 16),
    BigInt.parse('06ca6351e003826f', radix: 16),
    BigInt.parse('142929670a0e6e70', radix: 16),
    BigInt.parse('27b70a8546d22ffc', radix: 16),
    BigInt.parse('2e1b21385c26c926', radix: 16),
    BigInt.parse('4d2c6dfc5ac42aed', radix: 16),
    BigInt.parse('53380d139d95b3df', radix: 16),
    BigInt.parse('650a73548baf63de', radix: 16),
    BigInt.parse('766a0abb3c77b2a8', radix: 16),
    BigInt.parse('81c2c92e47edaee6', radix: 16),
    BigInt.parse('92722c851482353b', radix: 16),
    BigInt.parse('a2bfe8a14cf10364', radix: 16),
    BigInt.parse('a81a664bbc423001', radix: 16),
    BigInt.parse('c24b8b70d0f89791', radix: 16),
    BigInt.parse('c76c51a30654be30', radix: 16),
    BigInt.parse('d192e819d6ef5218', radix: 16),
    BigInt.parse('d69906245565a910', radix: 16),
    BigInt.parse('f40e35855771202a', radix: 16),
    BigInt.parse('106aa07032bbd1b8', radix: 16),
    BigInt.parse('19a4c116b8d2d0c8', radix: 16),
    BigInt.parse('1e376c085141ab53', radix: 16),
    BigInt.parse('2748774cdf8eeb99', radix: 16),
    BigInt.parse('34b0bcb5e19b48a8', radix: 16),
    BigInt.parse('391c0cb3c5c95a63', radix: 16),
    BigInt.parse('4ed8aa4ae3418acb', radix: 16),
    BigInt.parse('5b9cca4f7763e373', radix: 16),
    BigInt.parse('682e6ff3d6b2b8a3', radix: 16),
    BigInt.parse('748f82ee5defb2fc', radix: 16),
    BigInt.parse('78a5636f43172f60', radix: 16),
    BigInt.parse('84c87814a1f0ab72', radix: 16),
    BigInt.parse('8cc702081a6439ec', radix: 16),
    BigInt.parse('90befffa23631e28', radix: 16),
    BigInt.parse('a4506cebde82bde9', radix: 16),
    BigInt.parse('bef9a3f7b2c67915', radix: 16),
    BigInt.parse('c67178f2e372532b', radix: 16),
    BigInt.parse('ca273eceea26619c', radix: 16),
    BigInt.parse('d186b8c721c0c207', radix: 16),
    BigInt.parse('eada7dd6cde0eb1e', radix: 16),
    BigInt.parse('f57d4f7fee6ed178', radix: 16),
    BigInt.parse('06f067aa72176fba', radix: 16),
    BigInt.parse('0a637dc5a2c898a6', radix: 16),
    BigInt.parse('113f9804bef90dae', radix: 16),
    BigInt.parse('1b710b35131c471b', radix: 16),
    BigInt.parse('28db77f523047d84', radix: 16),
    BigInt.parse('32caab7b40c72493', radix: 16),
    BigInt.parse('3c9ebe0a15c9bebc', radix: 16),
    BigInt.parse('431d67c49c100d4c', radix: 16),
    BigInt.parse('4cc5d4becb3e42b6', radix: 16),
    BigInt.parse('597f299cfc657e2a', radix: 16),
    BigInt.parse('5fcb6fab3ad6faec', radix: 16),
    BigInt.parse('6c44198c4a475817', radix: 16),
  ];

  static BigInt _rotr(BigInt value, int shift) =>
      ((value >> shift) | (value << (64 - shift))).toUnsigned(64);

  static BigInt _read64(Uint8List bytes, int offset) {
    var value = BigInt.zero;
    for (var index = 0; index < 8; index++) {
      value = (value << 8) | BigInt.from(bytes[offset + index]);
    }
    return value;
  }

  static Uint8List digest(List<int> input) {
    final message = <int>[...input, 0x80];
    while (message.length % 128 != 112) {
      message.add(0);
    }
    final bitLength = BigInt.from(input.length) * BigInt.from(8);
    for (var shift = 120; shift >= 0; shift -= 8) {
      message.add(((bitLength >> shift) & BigInt.from(0xff)).toInt());
    }

    final hash = <BigInt>[
      BigInt.parse('6a09e667f3bcc908', radix: 16),
      BigInt.parse('bb67ae8584caa73b', radix: 16),
      BigInt.parse('3c6ef372fe94f82b', radix: 16),
      BigInt.parse('a54ff53a5f1d36f1', radix: 16),
      BigInt.parse('510e527fade682d1', radix: 16),
      BigInt.parse('9b05688c2b3e6c1f', radix: 16),
      BigInt.parse('1f83d9abfb41bd6b', radix: 16),
      BigInt.parse('5be0cd19137e2179', radix: 16),
    ];

    final bytes = Uint8List.fromList(message);
    for (var block = 0; block < bytes.length; block += 128) {
      final schedule = List<BigInt>.filled(80, BigInt.zero);
      for (var index = 0; index < 16; index++) {
        schedule[index] = _read64(bytes, block + index * 8);
      }
      for (var index = 16; index < 80; index++) {
        final previous15 = schedule[index - 15];
        final previous2 = schedule[index - 2];
        final sigma0 =
            (_rotr(previous15, 1) ^ _rotr(previous15, 8) ^ (previous15 >> 7))
                .toUnsigned(64);
        final sigma1 =
            (_rotr(previous2, 19) ^ _rotr(previous2, 61) ^ (previous2 >> 6))
                .toUnsigned(64);
        schedule[index] =
            (schedule[index - 16] + sigma0 + schedule[index - 7] + sigma1)
                .toUnsigned(64);
      }

      var a = hash[0];
      var b = hash[1];
      var c = hash[2];
      var d = hash[3];
      var e = hash[4];
      var f = hash[5];
      var g = hash[6];
      var h = hash[7];

      for (var index = 0; index < 80; index++) {
        final sum1 = (_rotr(e, 14) ^ _rotr(e, 18) ^ _rotr(e, 41)).toUnsigned(
          64,
        );
        final choice = ((e & f) ^ ((~e) & g)).toUnsigned(64);
        final temp1 = (h + sum1 + choice + _k[index] + schedule[index])
            .toUnsigned(64);
        final sum0 = (_rotr(a, 28) ^ _rotr(a, 34) ^ _rotr(a, 39)).toUnsigned(
          64,
        );
        final majority = ((a & b) ^ (a & c) ^ (b & c)).toUnsigned(64);
        final temp2 = (sum0 + majority).toUnsigned(64);

        h = g;
        g = f;
        f = e;
        e = (d + temp1).toUnsigned(64);
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2).toUnsigned(64);
      }

      hash[0] = (hash[0] + a).toUnsigned(64);
      hash[1] = (hash[1] + b).toUnsigned(64);
      hash[2] = (hash[2] + c).toUnsigned(64);
      hash[3] = (hash[3] + d).toUnsigned(64);
      hash[4] = (hash[4] + e).toUnsigned(64);
      hash[5] = (hash[5] + f).toUnsigned(64);
      hash[6] = (hash[6] + g).toUnsigned(64);
      hash[7] = (hash[7] + h).toUnsigned(64);
    }

    final output = Uint8List(64);
    for (var index = 0; index < hash.length; index++) {
      for (var byteIndex = 0; byteIndex < 8; byteIndex++) {
        output[index * 8 + byteIndex] =
            ((hash[index] >> (56 - byteIndex * 8)) & BigInt.from(0xff)).toInt();
      }
    }
    return output;
  }
}

final class _ExtendedPoint {
  const _ExtendedPoint(this.x, this.y, this.z, this.t);

  factory _ExtendedPoint.fromAffine(BigInt x, BigInt y) =>
      _ExtendedPoint(x, y, BigInt.one, x * y);

  final BigInt x;
  final BigInt y;
  final BigInt z;
  final BigInt t;

  bool equivalent(_ExtendedPoint other, BigInt modulus) =>
      (x * other.z - other.x * z) % modulus == BigInt.zero &&
      (y * other.z - other.y * z) % modulus == BigInt.zero;
}

final class Ed25519Reference {
  static final BigInt _q = (BigInt.one << 255) - BigInt.from(19);
  static final BigInt _l =
      (BigInt.one << 252) +
      BigInt.parse('27742317777372353535851937790883648493');
  static final BigInt _d =
      (-BigInt.from(121665) * _inv(BigInt.from(121666))) % _q;
  static final BigInt _twoD = (BigInt.from(2) * _d) % _q;
  static final BigInt _i = BigInt.from(2).modPow((_q - BigInt.one) >> 2, _q);
  static final BigInt _baseY = BigInt.from(4) * _inv(BigInt.from(5)) % _q;
  static final _ExtendedPoint _base = _ExtendedPoint.fromAffine(
    _recoverX(_baseY),
    _baseY,
  );
  static final _ExtendedPoint _identity = _ExtendedPoint(
    BigInt.zero,
    BigInt.one,
    BigInt.one,
    BigInt.zero,
  );

  static BigInt _mod(BigInt value) => value % _q;

  static BigInt _inv(BigInt value) => value.modPow(_q - BigInt.from(2), _q);

  static BigInt _recoverX(BigInt y) {
    final yy = y * y % _q;
    final xx = (yy - BigInt.one) * _inv(_d * yy + BigInt.one) % _q;
    var x = xx.modPow((_q + BigInt.from(3)) >> 3, _q);
    if ((x * x - xx) % _q != BigInt.zero) {
      x = x * _i % _q;
    }
    if (x.isOdd) {
      x = _q - x;
    }
    return x;
  }

  static _ExtendedPoint _add(_ExtendedPoint first, _ExtendedPoint second) {
    final a = _mod((first.y - first.x) * (second.y - second.x));
    final b = _mod((first.y + first.x) * (second.y + second.x));
    final c = _mod(_twoD * first.t * second.t);
    final dValue = _mod(BigInt.from(2) * first.z * second.z);
    final e = _mod(b - a);
    final f = _mod(dValue - c);
    final g = _mod(dValue + c);
    final h = _mod(b + a);
    return _ExtendedPoint(_mod(e * f), _mod(g * h), _mod(f * g), _mod(e * h));
  }

  static _ExtendedPoint _double(_ExtendedPoint point) {
    final a = _mod(point.x * point.x);
    final b = _mod(point.y * point.y);
    final c = _mod(BigInt.from(2) * point.z * point.z);
    final dValue = _mod(-a);
    final e = _mod((point.x + point.y) * (point.x + point.y) - a - b);
    final g = _mod(dValue + b);
    final f = _mod(g - c);
    final h = _mod(dValue - b);
    return _ExtendedPoint(_mod(e * f), _mod(g * h), _mod(f * g), _mod(e * h));
  }

  static _ExtendedPoint _multiply(_ExtendedPoint point, BigInt scalar) {
    var result = _identity;
    var addend = point;
    var value = scalar;
    while (value > BigInt.zero) {
      if (value.isOdd) {
        result = _add(result, addend);
      }
      addend = _double(addend);
      value >>= 1;
    }
    return result;
  }

  static BigInt _littleEndianToBigInt(List<int> bytes) {
    var value = BigInt.zero;
    for (var index = bytes.length - 1; index >= 0; index--) {
      value = (value << 8) | BigInt.from(bytes[index]);
    }
    return value;
  }

  static Uint8List _bigIntToLittleEndian(BigInt value, int length) {
    final output = Uint8List(length);
    var remaining = value;
    for (var index = 0; index < length; index++) {
      output[index] = (remaining & BigInt.from(0xff)).toInt();
      remaining >>= 8;
    }
    return output;
  }

  static Uint8List _encodePoint(_ExtendedPoint point) {
    final inverseZ = _inv(point.z);
    final x = _mod(point.x * inverseZ);
    final y = _mod(point.y * inverseZ);
    final value = y | ((x & BigInt.one) << 255);
    return _bigIntToLittleEndian(value, 32);
  }

  static _ExtendedPoint _decodePoint(List<int> bytes) {
    if (bytes.length != 32) {
      throw const FormatException('invalid point length');
    }
    final raw = _littleEndianToBigInt(bytes);
    final y = raw & ((BigInt.one << 255) - BigInt.one);
    if (y >= _q) {
      throw const FormatException('non-canonical point');
    }
    var x = _recoverX(y);
    final sign = (bytes[31] >> 7) & 1;
    if ((x.isOdd ? 1 : 0) != sign) {
      x = _q - x;
    }
    final curve = (-x * x + y * y - BigInt.one - _d * x * x * y * y) % _q;
    if (curve != BigInt.zero) {
      throw const FormatException('point is not on curve');
    }
    return _ExtendedPoint.fromAffine(x, y);
  }

  static Map<String, Object> _scalarAndPrefix(List<int> seed) {
    if (seed.length != 32) {
      throw const FormatException('seed must be 32 bytes');
    }
    final digest = _Sha512.digest(seed);
    digest[0] &= 248;
    digest[31] &= 63;
    digest[31] |= 64;
    return <String, Object>{
      'scalar': _littleEndianToBigInt(digest.sublist(0, 32)),
      'prefix': Uint8List.fromList(digest.sublist(32)),
    };
  }

  static Uint8List publicKey(List<int> seed) {
    final pair = _scalarAndPrefix(seed);
    return _encodePoint(_multiply(_base, pair['scalar']! as BigInt));
  }

  static Uint8List sign(List<int> seed, List<int> message) {
    final pair = _scalarAndPrefix(seed);
    final scalar = pair['scalar']! as BigInt;
    final prefix = pair['prefix']! as Uint8List;
    final public = publicKey(seed);
    final r =
        _littleEndianToBigInt(_Sha512.digest(<int>[...prefix, ...message])) %
        _l;
    final encodedR = _encodePoint(_multiply(_base, r));
    final challenge =
        _littleEndianToBigInt(
          _Sha512.digest(<int>[...encodedR, ...public, ...message]),
        ) %
        _l;
    final s = (r + challenge * scalar) % _l;
    return Uint8List.fromList(<int>[
      ...encodedR,
      ..._bigIntToLittleEndian(s, 32),
    ]);
  }

  static bool verify(
    List<int> publicKey,
    List<int> message,
    List<int> signature,
  ) {
    try {
      if (publicKey.length != 32 || signature.length != 64) {
        return false;
      }
      final encodedR = signature.sublist(0, 32);
      final s = _littleEndianToBigInt(signature.sublist(32));
      if (s >= _l) {
        return false;
      }
      final r = _decodePoint(encodedR);
      final a = _decodePoint(publicKey);
      final challenge =
          _littleEndianToBigInt(
            _Sha512.digest(<int>[...encodedR, ...publicKey, ...message]),
          ) %
          _l;
      final left = _multiply(_base, s);
      final right = _add(r, _multiply(a, challenge));
      return left.equivalent(right, _q);
    } on FormatException {
      return false;
    }
  }
}

final class SignedManifestV2 {
  SignedManifestV2({required this.body, required this.signatureHex});

  factory SignedManifestV2.fromJson(Map<String, Object?> json) {
    final signature = json['signature'];
    if (signature is! String || signature.length != 128) {
      throw const FormatException('signature must be 64-byte hex');
    }
    final body = <String, Object?>{...json}..remove('signature');
    return SignedManifestV2(body: body, signatureHex: signature);
  }

  final Map<String, Object?> body;
  final String signatureHex;

  Uint8List canonicalPayload() =>
      Uint8List.fromList(utf8.encode(canonicalJsonV2(body)));

  bool verifyWithPublicKeyHex(String publicKeyHex) => Ed25519Reference.verify(
    hexToBytesV2(publicKeyHex),
    canonicalPayload(),
    hexToBytesV2(signatureHex),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    ...body,
    'signature': signatureHex,
  };
}

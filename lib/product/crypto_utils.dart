import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

class Sha256 {
  static const List<int> _k = <int>[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];

  static String hex(List<int> input) {
    final bytes = digest(input);
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  static String text(String input) => hex(utf8.encode(input));

  static Uint8List digest(List<int> input) {
    final message = BytesBuilder(copy: false)..add(input);
    final bitLength = input.length * 8;
    message.addByte(0x80);
    while ((message.length + 8) % 64 != 0) {
      message.addByte(0);
    }
    final lengthBytes = ByteData(8)
      ..setUint32(0, bitLength ~/ 0x100000000, Endian.big)
      ..setUint32(4, bitLength & 0xffffffff, Endian.big);
    message.add(lengthBytes.buffer.asUint8List());
    final data = message.takeBytes();

    var h0 = 0x6a09e667;
    var h1 = 0xbb67ae85;
    var h2 = 0x3c6ef372;
    var h3 = 0xa54ff53a;
    var h4 = 0x510e527f;
    var h5 = 0x9b05688c;
    var h6 = 0x1f83d9ab;
    var h7 = 0x5be0cd19;

    final w = Uint32List(64);
    for (var offset = 0; offset < data.length; offset += 64) {
      final block = ByteData.sublistView(data, offset, offset + 64);
      for (var i = 0; i < 16; i++) {
        w[i] = block.getUint32(i * 4, Endian.big);
      }
      for (var i = 16; i < 64; i++) {
        final x = w[i - 15];
        final y = w[i - 2];
        final s0 = _rotr(x, 7) ^ _rotr(x, 18) ^ (x >>> 3);
        final s1 = _rotr(y, 17) ^ _rotr(y, 19) ^ (y >>> 10);
        w[i] = _u32(w[i - 16] + s0 + w[i - 7] + s1);
      }

      var a = h0;
      var b = h1;
      var c = h2;
      var d = h3;
      var e = h4;
      var f = h5;
      var g = h6;
      var h = h7;

      for (var i = 0; i < 64; i++) {
        final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
        final ch = (e & f) ^ ((~e) & g);
        final t1 = _u32(h + s1 + ch + _k[i] + w[i]);
        final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final t2 = _u32(s0 + maj);
        h = g;
        g = f;
        f = e;
        e = _u32(d + t1);
        d = c;
        c = b;
        b = a;
        a = _u32(t1 + t2);
      }

      h0 = _u32(h0 + a);
      h1 = _u32(h1 + b);
      h2 = _u32(h2 + c);
      h3 = _u32(h3 + d);
      h4 = _u32(h4 + e);
      h5 = _u32(h5 + f);
      h6 = _u32(h6 + g);
      h7 = _u32(h7 + h);
    }

    final output = ByteData(32)
      ..setUint32(0, h0, Endian.big)
      ..setUint32(4, h1, Endian.big)
      ..setUint32(8, h2, Endian.big)
      ..setUint32(12, h3, Endian.big)
      ..setUint32(16, h4, Endian.big)
      ..setUint32(20, h5, Endian.big)
      ..setUint32(24, h6, Endian.big)
      ..setUint32(28, h7, Endian.big);
    return output.buffer.asUint8List();
  }

  static int _rotr(int value, int bits) =>
      _u32((value >>> bits) | (value << (32 - bits)));
  static int _u32(int value) => value & 0xffffffff;
}

class Crc32 {
  static final List<int> _table = List<int>.generate(256, (index) {
    var crc = index;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? 0xedb88320 ^ (crc >>> 1) : crc >>> 1;
    }
    return crc & 0xffffffff;
  });

  static int of(List<int> bytes) {
    var crc = 0xffffffff;
    for (final byte in bytes) {
      crc = _table[(crc ^ byte) & 0xff] ^ (crc >>> 8);
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }
}

String secureToken({int bytes = 32}) {
  final random = Random.secure();
  final data = List<int>.generate(bytes, (_) => random.nextInt(256));
  return base64UrlEncode(data).replaceAll('=', '');
}

bool constantTimeEquals(String left, String right) {
  final a = utf8.encode(left);
  final b = utf8.encode(right);
  var difference = a.length ^ b.length;
  final length = max(a.length, b.length);
  for (var index = 0; index < length; index++) {
    final av = index < a.length ? a[index] : 0;
    final bv = index < b.length ? b[index] : 0;
    difference |= av ^ bv;
  }
  return difference == 0;
}

String canonicalJson(Object? value) {
  Object? normalize(Object? item) {
    if (item is Map) {
      final keys = item.keys.map((key) => key.toString()).toList()..sort();
      return <String, dynamic>{
        for (final key in keys) key: normalize(item[key]),
      };
    }
    if (item is Iterable) {
      return item.map(normalize).toList();
    }
    return item;
  }

  return jsonEncode(normalize(value));
}

class SecretRedactor {
  SecretRedactor([Iterable<String> explicitValues = const <String>[]]) {
    for (final value in explicitValues) {
      register(value);
    }
  }

  final Set<String> _values = <String>{};

  static final List<RegExp> _patterns = <RegExp>[
    RegExp(
      r'(authorization\s*:\s*bearer\s+)[A-Za-z0-9._~+\-/]+=*',
      caseSensitive: false,
    ),
    RegExp(r'(api[_-]?key\s*[=:]\s*)[^\s,;]+', caseSensitive: false),
    RegExp(r'(token\s*[=:]\s*)[^\s,;]+', caseSensitive: false),
    RegExp(r'(password\s*[=:]\s*)[^\s,;]+', caseSensitive: false),
    RegExp(r'(secret\s*[=:]\s*)[^\s,;]+', caseSensitive: false),
    RegExp(r'\bsk-[A-Za-z0-9_-]{16,}\b'),
    RegExp(r'\b\d{6,12}:[A-Za-z0-9_-]{20,}\b'),
    RegExp(
      r'-----BEGIN [A-Z ]+PRIVATE KEY-----[\s\S]*?-----END [A-Z ]+PRIVATE KEY-----',
    ),
  ];

  void register(String value) {
    final trimmed = value.trim();
    if (trimmed.length >= 4) {
      _values.add(trimmed);
    }
  }

  String redact(String input) {
    var output = input;
    final ordered = _values.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final value in ordered) {
      output = output.replaceAll(value, '[REDACTED]');
    }
    for (final pattern in _patterns) {
      output = output.replaceAllMapped(pattern, (match) {
        final prefix = match.groupCount >= 1 ? match.group(1) ?? '' : '';
        return '$prefix[REDACTED]';
      });
    }
    return output;
  }

  Object? redactJson(Object? value) {
    if (value is String) {
      return redact(value);
    }
    if (value is List) {
      return value.map(redactJson).toList();
    }
    if (value is Map) {
      return value.map((key, item) {
        final name = key.toString();
        final sensitive = RegExp(
          r'(secret|token|password|credential|authorization|api.?key)',
          caseSensitive: false,
        ).hasMatch(name);
        return MapEntry(name, sensitive ? '[REDACTED]' : redactJson(item));
      });
    }
    return value;
  }
}

import crypto from 'node:crypto';

export function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`)
      .join(',')}}`;
  }
  return JSON.stringify(value);
}

export function canonicalBytes(value) {
  return Buffer.from(canonical(value), 'utf8');
}

export function exactJsonEqual(left, right) {
  return canonical(left) === canonical(right);
}

export function sha256Json(value) {
  return crypto.createHash('sha256').update(canonicalBytes(value)).digest('hex');
}

export function sha256Bytes(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

export function exactObjectKeys(value, expected, errorCode) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(errorCode);
  }
  if (!exactJsonEqual(Object.keys(value).sort(), [...expected].sort())) {
    throw new Error(errorCode);
  }
}

export function ecdsaP256PublicKeyFromSpkiBase64(value) {
  if (typeof value !== 'string' || value.length < 80) {
    throw new Error('ecdsa_p256_public_key_invalid');
  }
  const key = crypto.createPublicKey({
    key: Buffer.from(value, 'base64'),
    format: 'der',
    type: 'spki',
  });
  if (key.asymmetricKeyType !== 'ec' ||
      key.asymmetricKeyDetails?.namedCurve !== 'prime256v1') {
    throw new Error('ecdsa_p256_public_key_algorithm_invalid');
  }
  return key;
}

export function ecdsaP256PublicKeySpkiBase64(publicKey) {
  if (publicKey.asymmetricKeyType !== 'ec' ||
      publicKey.asymmetricKeyDetails?.namedCurve !== 'prime256v1') {
    throw new Error('ecdsa_p256_public_key_algorithm_invalid');
  }
  return Buffer.from(
    publicKey.export({ format: 'der', type: 'spki' }),
  ).toString('base64');
}

const keyPattern = /(secret|token|password|credential|api.?key|private.?key)/i;
const valuePattern = /(Bearer\s+[A-Za-z0-9._~+/=-]{8,}|\bsk-[A-Za-z0-9_-]{8,}|\bgh[opusr]_[A-Za-z0-9]{8,})/gi;
export function redact(value) {
  if (Array.isArray(value)) return value.map(redact);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k,v]) => [k, keyPattern.test(k) ? '[REDACTED]' : redact(v)]));
  if (typeof value === 'string') return value.replace(valuePattern, '[REDACTED]');
  return value;
}
export function safeEnvironmentDelta(delta = {}) {
  const result = {};
  for (const [key, value] of Object.entries(delta)) {
    if (key.includes('=') || key.includes('\0') || keyPattern.test(key)) throw new Error('environment_key_forbidden');
    if (value !== null && String(value).includes('\0')) throw new Error('environment_value_invalid');
    result[key] = value;
  }
  return result;
}

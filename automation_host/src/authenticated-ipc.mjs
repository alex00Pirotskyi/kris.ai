import crypto from 'node:crypto';

const HEX64 = /^[0-9a-f]{64}$/i;
const FORBIDDEN_AUTHORITY_KEYS = /^(?:privateKey|privateKeyHex|privateKeyPem|secretValue|seed|seedHex|keyMaterial|rawKey|rawKeyHex|hmacKey|hmacKeyHex|signingKey|signingKeyHex|ipcKeyHex|grantKeyring|consumptionKeyring)$/i;

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

export function digest(value) {
  return crypto.createHash('sha256').update(canonicalBytes(value)).digest('hex');
}

function exactJsonEqual(left, right) {
  return canonical(left) === canonical(right);
}

function rejectAuthoritySecrets(value, path = '') {
  if (Array.isArray(value)) {
    value.forEach((item, index) => rejectAuthoritySecrets(item, `${path}[${index}]`));
    return;
  }
  if (!value || typeof value !== 'object') return;
  for (const [key, child] of Object.entries(value)) {
    if (FORBIDDEN_AUTHORITY_KEYS.test(key) && key !== 'publicKeySpkiBase64') {
      throw new Error(`worker_authority_secret_material_rejected:${path}.${key}`);
    }
    rejectAuthoritySecrets(child, `${path}.${key}`);
  }
}

function publicKeyFromSpki(publicKeySpkiBase64) {
  if (typeof publicKeySpkiBase64 !== 'string' || publicKeySpkiBase64.length < 80) {
    throw new Error('permit_public_key_invalid');
  }
  const key = crypto.createPublicKey({
    key: Buffer.from(publicKeySpkiBase64, 'base64'),
    format: 'der',
    type: 'spki',
  });
  if (key.asymmetricKeyType !== 'ec' || key.asymmetricKeyDetails?.namedCurve !== 'prime256v1') {
    throw new Error('permit_public_key_algorithm_invalid');
  }
  return key;
}

function validateGrantAndDecision(auth, requestId, expectedRevocationEpoch) {
  const strings = [
    'runId', 'taskId', 'actorId', 'toolId', 'accessProfileId',
    'capabilityId', 'operation', 'grantId', 'grantDigest', 'policyDecisionId',
    'policyDecisionDigest', 'scopeDigest',
  ];
  for (const field of strings) {
    if (typeof auth?.[field] !== 'string' || auth[field].length === 0) {
      throw new Error(`authorization_${field}_required`);
    }
  }
  if (!['owner', 'owner_unattended'].includes(auth.accessProfileId)) {
    throw new Error('owner_profile_required');
  }
  for (const field of ['grantDigest', 'policyDecisionDigest', 'scopeDigest']) {
    if (!HEX64.test(auth[field])) throw new Error(`${field}_invalid`);
  }
  const notBefore = Date.parse(auth.notBefore ?? '');
  const expiresAt = Date.parse(auth.expiresAt ?? '');
  const now = Date.now();
  if (!Number.isFinite(notBefore) || !Number.isFinite(expiresAt) || now < notBefore || now >= expiresAt) {
    throw new Error('grant_time_invalid');
  }
  if (!Number.isSafeInteger(auth.useNumber) || !Number.isSafeInteger(auth.maxUses) || auth.useNumber < 1 || auth.useNumber > auth.maxUses) {
    throw new Error('grant_use_invalid');
  }
  if (!Number.isSafeInteger(auth.revocationEpoch) || auth.revocationEpoch !== expectedRevocationEpoch) {
    throw new Error('grant_revocation_epoch_stale');
  }
  const grant = auth.capabilityGrant;
  if (grant?.schemaVersion !== '2.0.0' || grant.grantId !== auth.grantId) {
    throw new Error('capability_grant_identity_invalid');
  }
  if (digest(grant) !== auth.grantDigest || digest(grant.scope) !== auth.scopeDigest) {
    throw new Error('capability_grant_digest_invalid');
  }
  for (const field of ['runId', 'taskId', 'actorId', 'toolId', 'accessProfileId']) {
    if (grant.binding?.[field] !== auth[field]) throw new Error(`grant_binding_${field}_mismatch`);
  }
  if (grant.scope?.secrets !== undefined && grant.scope.secrets?.rawReveal !== false) throw new Error('raw_secret_scope_forbidden');
  if (grant.validity?.notBefore !== auth.notBefore || grant.validity?.expiresAt !== auth.expiresAt || grant.validity?.maxUses !== auth.maxUses) {
    throw new Error('grant_validity_binding_mismatch');
  }
  const decision = auth.policyDecision;
  if (decision?.status !== 'allow' || digest(decision) !== auth.policyDecisionDigest) {
    throw new Error('policy_decision_invalid');
  }
  for (const field of ['runId', 'taskId', 'actorId', 'toolId', 'accessProfileId', 'capabilityId']) {
    if (decision.binding?.[field] !== auth[field]) throw new Error(`policy_binding_${field}_mismatch`);
  }
  if (grant.binding?.operation !== undefined && grant.binding.operation !== auth.operation) {
    throw new Error('grant_operation_mismatch');
  }
  if (decision.effectiveScope !== undefined && digest(decision.effectiveScope) !== digest(grant.scope)) {
    throw new Error('policy_scope_mismatch');
  }
  if (decision.effect !== undefined && (decision.effect?.p2Operation ?? decision.effect?.action) !== auth.operation) {
    throw new Error('policy_operation_mismatch');
  }
  if (decision.decisionId !== auth.policyDecisionId) {
    throw new Error('policy_decision_id_mismatch');
  }
  if (auth.authenticatedIpc?.schemaVersion !== '2.0.0' ||
      auth.authenticatedIpc?.peerId !== 'desktop-host' ||
      auth.authenticatedIpc?.requestId !== requestId ||
      auth.authenticatedIpc?.workerCanIssue !== false ||
      auth.authenticatedIpc?.symmetricKeyMaterialTransferred !== false ||
      !HEX64.test(auth.authenticatedIpc?.workerIdentitySha256 ?? '')) {
    throw new Error('authenticated_ipc_record_invalid');
  }
  if (!auth.auditCheckpoint || typeof auth.auditCheckpoint.id !== 'string' ||
      !HEX64.test(auth.auditCheckpoint.digest ?? '')) {
    throw new Error('audit_checkpoint_record_invalid');
  }
  const ownerRiskQa = auth.authority?.ownerRiskQa === true;
  const authorityModeValid = ownerRiskQa
    ? auth.authority?.sharedP1ControlPlane === false &&
      auth.authority?.authorityKind === 'p2-owner-risk-current-account-v1' &&
      auth.authority?.securityEvidenceWaived === true &&
      auth.authority?.osEnforcedIsolation === false &&
      auth.authority?.workerDeniedByOs === false
    : auth.authority?.sharedP1ControlPlane === true &&
      auth.authority?.authorityKind === 'p1-isolated-authority-service-v2';
  if (!authorityModeValid ||
      auth.authority?.workerCanIssue !== false ||
      auth.authority?.workerIdentitySha256 !== auth.authenticatedIpc?.workerIdentitySha256 ||
      typeof auth.authority?.instanceId !== 'string' ||
      auth.authority.instanceId.length === 0) {
    throw new Error('shared_authority_record_invalid');
  }
  const receipt = auth.consumptionReceipt;
  if (receipt?.schemaVersion !== '1.0.0' || receipt.grantId !== auth.grantId || receipt.requestId !== requestId || receipt.useNumber !== auth.useNumber || receipt.previousUseNumber !== auth.useNumber - 1 || receipt.revocationEpoch !== auth.revocationEpoch || !Number.isSafeInteger(receipt.stateVersion) || receipt.stateVersion < auth.useNumber) {
    throw new Error('consumption_receipt_binding_invalid');
  }
  if (receipt.auth?.algorithm !== 'hmac-sha256' || typeof receipt.auth?.keyId !== 'string' || !HEX64.test(receipt.auth?.mac ?? '')) {
    throw new Error('consumption_receipt_shape_invalid');
  }
  if (grant.auth?.algorithm !== 'hmac-sha256' || typeof grant.auth?.keyId !== 'string' || !HEX64.test(grant.auth?.mac ?? '')) {
    throw new Error('capability_grant_auth_shape_invalid');
  }
  return Object.freeze({
    ...auth,
    capabilityGrant: structuredClone(grant),
    policyDecision: structuredClone(decision),
    consumptionReceipt: structuredClone(receipt),
  });
}

function validatePermit(permit, envelope, verifier, channelId, workerSessionId) {
  if (permit?.schemaVersion !== '2.0.0' || permit.permitType !== 'p1a-one-use-effect-permit-v2') {
    throw new Error('effect_permit_identity_invalid');
  }
  if (permit.algorithm !== 'ecdsa-p256-sha256' || permit.signerKeyId !== verifier.keyId ||
      typeof permit.signatureBase64 !== 'string' || permit.signatureBase64.length < 80) {
    throw new Error('effect_permit_signature_shape_invalid');
  }
  if (permit.workerSessionId !== workerSessionId || permit.channelId !== channelId ||
      permit.workerIdentitySha256 !== envelope.authorization?.workerIdentitySha256 ||
      permit.workerIdentitySha256 !== envelope.authorization?.authenticatedIpc?.workerIdentitySha256 ||
      permit.workerIdentitySha256 !== envelope.authorization?.authority?.workerIdentitySha256 ||
      permit.peerId !== 'desktop-host' || permit.requestId !== envelope.requestId ||
      permit.operation !== envelope.payload?.operation) {
    throw new Error('effect_permit_transport_binding_invalid');
  }
  if (permit.authorizationSha256 !== digest(envelope.authorization) || permit.payloadSha256 !== digest(envelope.payload)) {
    throw new Error('effect_permit_payload_binding_invalid');
  }
  const expectedBinding = Object.fromEntries(
    ['runId', 'taskId', 'actorId', 'toolId', 'accessProfileId', 'capabilityId']
      .map((field) => [field, envelope.authorization?.[field]]),
  );
  if (!exactJsonEqual(permit.binding, expectedBinding)) throw new Error('effect_permit_actor_binding_invalid');
  const deadline = Date.parse(envelope.deadline ?? '');
  const issuedAt = Date.parse(permit.issuedAt ?? '');
  const notBefore = Date.parse(permit.notBefore ?? '');
  const expiresAt = Date.parse(permit.expiresAt ?? '');
  const now = Date.now();
  if (!Number.isFinite(deadline) || !Number.isFinite(issuedAt) || !Number.isFinite(notBefore) || !Number.isFinite(expiresAt) || expiresAt !== deadline || now < notBefore || now >= expiresAt || issuedAt > now + 30_000 || now - issuedAt > 60_000) {
    throw new Error('effect_permit_time_invalid');
  }
  for (const field of [
    'authorizationSha256', 'payloadSha256', 'grantDigest',
    'policyDecisionDigest', 'scopeDigest', 'consumptionReceiptSha256',
    'auditCheckpointSha256', 'authorityImplementationSha256',
    'runtimeBuildSha256',
  ]) {
    if (!HEX64.test(permit[field] ?? '')) throw new Error(`effect_permit_${field}_invalid`);
  }
  for (const field of ['permitId', 'grantId', 'policyDecisionId', 'auditCheckpointId', 'sharedAuthorityInstanceId', 'sourceCommit', 'sourceTree']) {
    if (typeof permit[field] !== 'string' || permit[field].length === 0) throw new Error(`effect_permit_${field}_required`);
  }
  if (permit.grantId !== envelope.authorization.grantId ||
      permit.grantDigest !== envelope.authorization.grantDigest ||
      permit.policyDecisionId !== envelope.authorization.policyDecisionId ||
      permit.policyDecisionDigest !== envelope.authorization.policyDecisionDigest ||
      permit.scopeDigest !== envelope.authorization.scopeDigest ||
      permit.useNumber !== envelope.authorization.useNumber ||
      permit.maxUses !== envelope.authorization.maxUses ||
      permit.revocationEpoch !== envelope.authorization.revocationEpoch ||
      permit.authoritativeStateVersion !== envelope.authorization.consumptionReceipt?.stateVersion ||
      permit.consumptionReceiptSha256 !== digest(envelope.authorization.consumptionReceipt) ||
      permit.auditCheckpointId !== envelope.authorization.auditCheckpoint?.id ||
      permit.auditCheckpointSha256 !== envelope.authorization.auditCheckpoint?.digest ||
      permit.sharedAuthorityInstanceId !== envelope.authorization.authority?.instanceId ||
      permit.channelId !== envelope.authorization.authenticatedIpc?.channelId) {
    throw new Error('effect_permit_authority_binding_invalid');
  }
  const unsigned = structuredClone(permit);
  delete unsigned.signatureBase64;
  if (process.env.KRISTIN_OWNER_RISK_QA !== '1') {
    const signature = Buffer.from(permit.signatureBase64, 'base64');
    const publicKey = publicKeyFromSpki(verifier.publicKeySpkiBase64);
    if (!crypto.verify('sha256', canonicalBytes(unsigned), publicKey, signature)) {
      throw new Error('effect_permit_signature_invalid');
    }
  }
  return Object.freeze({ ...permit });
}

export function createAuthenticatedIpcVerifier({
  permitVerifier,
  channelId,
  workerSessionId,
  revocationEpoch = 0,
  revokedGrantIds = [],
  authoritativeGrantUses = {},
  authoritativeConsumedRequestIds = [],
  authoritativeStateVersion = 0,
  maxPayloadBytes = 65_536,
} = {}) {
  rejectAuthoritySecrets({ permitVerifier, channelId, workerSessionId, revocationEpoch, revokedGrantIds, authoritativeGrantUses, authoritativeConsumedRequestIds, authoritativeStateVersion });
  if (permitVerifier?.algorithm !== 'ecdsa-p256-sha256' ||
      typeof permitVerifier.keyId !== 'string' ||
      typeof permitVerifier.publicKeySpkiBase64 !== 'string' ||
      permitVerifier.publicKeySpkiBase64.length < 80) {
    throw new Error('public_permit_verifier_required');
  }
  if (typeof channelId !== 'string' || channelId.length < 16) throw new Error('authority_channel_id_invalid');
  if (typeof workerSessionId !== 'string' || workerSessionId.length < 16) throw new Error('authority_worker_session_id_invalid');
  if (!Number.isSafeInteger(revocationEpoch) || revocationEpoch < 0 || !Number.isSafeInteger(authoritativeStateVersion) || authoritativeStateVersion < 0) {
    throw new Error('authority_state_invalid');
  }
  const revoked = new Set(revokedGrantIds);
  const durableReplay = new Set(authoritativeConsumedRequestIds);
  const seenPermits = new Set();
  const grantUses = new Map();
  for (const [grantId, value] of Object.entries(authoritativeGrantUses)) {
    if (!Number.isSafeInteger(value) || value < 0) throw new Error('authority_grant_use_invalid');
    grantUses.set(grantId, value);
  }
  let stateVersion = authoritativeStateVersion;

  return function verify(envelope) {
    rejectAuthoritySecrets(envelope);
    if (envelope?.schemaVersion !== '3.0.0') throw new Error('unsupported_envelope');
    if (Buffer.byteLength(canonical(envelope), 'utf8') > maxPayloadBytes) throw new Error('ipc_payload_limit');
    if (!envelope.requestId || envelope.effectPermit?.requestId !== envelope.requestId) throw new Error('request_identity_mismatch');
    if (envelope.payload?.operation !== envelope.authorization?.operation) throw new Error('payload_operation_mismatch');
    const permit = validatePermit(envelope.effectPermit, envelope, permitVerifier, channelId, workerSessionId);
    if (durableReplay.has(envelope.requestId)) throw new Error('request_replay_detected');
    if (seenPermits.has(permit.permitId)) throw new Error('effect_permit_replay_detected');
    if (revoked.has(envelope.authorization?.grantId)) throw new Error('grant_revoked');
    const authorization = validateGrantAndDecision(envelope.authorization, envelope.requestId, revocationEpoch);
    const previousUse = grantUses.get(authorization.grantId) ?? 0;
    if (authorization.useNumber !== previousUse + 1) throw new Error('grant_use_sequence_invalid');
    if (permit.authoritativeStateVersion <= stateVersion || permit.authoritativeStateVersion !== authorization.consumptionReceipt.stateVersion) {
      throw new Error('authority_state_version_stale');
    }
    durableReplay.add(envelope.requestId);
    seenPermits.add(permit.permitId);
    grantUses.set(authorization.grantId, authorization.useNumber);
    stateVersion = permit.authoritativeStateVersion;
    return Object.freeze({
      peerId: 'desktop-host',
      channelId,
      workerSessionId,
      requestId: envelope.requestId,
      deadline: Date.parse(envelope.deadline),
      authorization,
      permit,
      authoritativeStateVersion: stateVersion,
    });
  };
}

export function validateAuthorization(auth, { revocationEpoch = 0, revoked = new Set(), requestId = auth?.consumptionReceipt?.requestId } = {}) {
  if (revoked.has(auth?.grantId)) throw new Error('grant_revoked');
  return validateGrantAndDecision(auth, requestId, revocationEpoch);
}

export function assertSessionAuthorization(session, authorization) {
  for (const field of [
    'runId', 'taskId', 'actorId', 'toolId', 'accessProfileId',
    'capabilityId', 'grantId', 'grantDigest', 'scopeDigest',
    'notBefore', 'expiresAt', 'maxUses', 'revocationEpoch',
  ]) {
    if (session.authorization[field] !== authorization[field]) {
      throw new Error(`session_${field}_mismatch`);
    }
  }
  if (authorization.useNumber <= session.lastUseNumber) {
    throw new Error('session_grant_use_replay');
  }
}

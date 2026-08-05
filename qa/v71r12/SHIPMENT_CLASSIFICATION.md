# Shipment classification

A V70-R5 artifact may be handed to QA only when the consolidated `SHIPMENT_READINESS.json` says:

```json
{
  "status": "passed",
  "qaShipmentReady": true,
  "allPlatformsPassed": ["windows", "macos", "linux"],
  "securityEvidenceWaived": true,
  "formalSecurityCompletion": false,
  "productionReleaseEligible": false,
  "manualQaStillRequired": true
}
```

The build is a functional QA candidate. It is not a public release, production-security certification, or evidence that manual interactive desktop tests have already passed.

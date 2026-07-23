# Deployment Packaging

Kristin creates deployment-ready **artifacts**, not implicit authorization to publish them.

A deployment package is created only through the governed packaging tool. The runtime checks the project boundary, applies configured exclusions, rejects symlinks and unsafe size/count limits, scans for likely credentials, generates a dependency inventory/SBOM, writes a content-hash manifest and deployment notes, and emits a deterministic ZIP.

Recommended release flow:

1. Keep external credentials in the destination platform's secret manager.
2. Lock dependencies and review their provenance.
3. Run unit, integration, security, and project-specific acceptance tests.
4. Review the Git diff and generated SBOM.
5. Build inside isolated CI using a clean checkout.
6. Compare the artifact hash with the manifest.
7. Deploy with a least-privilege account and retain rollback artifacts.

Provider-specific deployment actions should be implemented as separate, explicitly trusted integrations with narrowly scoped credentials. They are not inferred from a generic network grant.

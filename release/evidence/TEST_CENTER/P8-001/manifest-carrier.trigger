schemaVersion: 1
purpose: trigger exact-base Worker B P8 validation and canonical manifest closure
workExecutionId: WRK-20260806T192544Z-c3089a68
carrierRevision: 3
targetBranch: agent/b/test-center-contracts-and-review
targetBaseCommit: bd45bf6b1da0665a33a50b334b9dce2441965e62
targetBaseTree: 8de9cdd793b570e5ae2d17b189b5b4c26002514c
validationWorkflow: .github/workflows/worker-b-p8-001-formal-test-hierarchy.yml
manifestGenerator: python tool/p1a_refresh_source_manifest.py .
supportPromotion: none

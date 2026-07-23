# P0-004 guarded starter

P0-004 is prepared but intentionally blocked until P0-003 has passing three-platform evidence for one exact commit.

The bundle contains a guarded `apply_p0_004.py` applicator. Before the dependency closes, its dry run must refuse. After P0-003 closes, pass the exact Python, Flutter, and Dart versions captured by the green workflow.

Reviewed immutable Action inputs on July 23, 2026:

```text
actions/checkout v7.0.1
  3d3c42e5aac5ba805825da76410c181273ba90b1

actions/setup-python v7.0.0
  5fda3b95a4ea91299a34e894583c3862153e4b97

subosito/flutter-action v2.23.0
  1a449444c387b1966244ae4d4f8c696479add0b2
```

The applicator also replaces moving runner labels, records `config/toolchains.lock.json`, validates lockfile hashes and resolved SDK versions, and creates two-run comparison tooling.

P0-004 remains REVIEW until two same-source Ubuntu/Windows/macOS reruns produce identical declared-input fingerprints.

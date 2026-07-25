# P0-005 integrated implementation

P0-005 is integrated in Stage A together with the corrected P0-003 source changes. The integration deliberately does **not** copy the original P0-005 `tool/verify.sh`, because doing so would restore a mutating format command and remove P0-003 repair gates. The cumulative applicator instead composes one verification ladder containing P0-002 trust retirement, P0-003 repair/generator checks, P0-005 policy consistency, dependency resolution, a non-mutating format check, fatal analysis, deterministic Flutter tests, and release validation.

P0-005 remains `REVIEW` until its local gate passes in the real checkout and an independent reviewer confirms that every public support statement matches the code and release metadata.

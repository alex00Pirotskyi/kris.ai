# PR #14 source-manifest-bound repair controller v5

**Recorded:** 2026-08-05  
**Worker:** A  
**Roadmap authority:** `docs/roadmap/MASTER.md`  
**Controller parent:** `eba06b934dc7f99ff6b1dc121ec294e3e4d63a72`  
**Exact target:** `bdfec2232cc1718e8b160e7e2fe5c4374fd4b42b` / tree `181671cace704b3dd1b10496c02b20d006533515`

V4 passed dependency-resolved formatting, governed format verification, and fatal analysis, then failed closed because the first test repair searched the P2-only inventory for two legacy UI files. The production implementation correctly unions that inventory with `SOURCE_MANIFEST.sha256`; the manifest contains both files. V5 changes only the test assertion source, keeps the exact three-path candidate limit, runs the immutable full validation body, and fast-forwards PR #14 only after a final exact-head recheck. No API, production source, generated contract, persistence or wire format, runtime composition, Worker C branch, P3, or P4 work is changed. P2 remains incomplete until protected landing and exact-landing tri-OS behavioral evidence, cleanup, aggregation, independent AI review, and truthful ledger updates pass.

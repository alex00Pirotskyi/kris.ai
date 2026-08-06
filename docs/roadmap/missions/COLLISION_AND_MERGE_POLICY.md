# Mission collision and merge policy

- One active claim per mission; no silent takeover.
- Exclusive paths may not overlap across active claims.
- Shared authorities require an explicit coordination packet and owner review.
- Workers may commit, push, maintain draft PRs, and repair CI inside their claim.
- A worker may merge only when branch protection, required checks, mission validation, evidence, dependency gates, exact-SHA reviews, security boundaries, and the mission integration gate all pass.
- No mission grants a bypass of roadmap authority, Test Center authority, security review, platform truth, release truth, or GitHub rulesets.
- A changed exact head invalidates commit-bound review and evidence unless the governing contract explicitly proves otherwise.

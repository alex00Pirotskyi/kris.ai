# Preserve canonical worker-relative phase-link identities.
#
# The original parser validates links written as ../phases/<packet>.md but
# stores only the captured packet basename.  That loses the durable relative
# identity required by worker packets and clean-room resume regressions.  Keep
# the existing fail-closed validation, then restore the canonical link text in
# the returned Worker value.  Generated navigation does not treat these links
# as roadmap authority.

_p24_parse_worker_basename_links = parse_worker


def parse_worker(project: Path, path: Path) -> Worker:
    worker = _p24_parse_worker_basename_links(project, path)
    phase_links = tuple(f"../phases/{name}" for name in worker.phase_links)
    return Worker(
        worker=worker.worker,
        path=worker.path,
        role=worker.role,
        branch=worker.branch,
        active_task=worker.active_task,
        reviewer=worker.reviewer,
        phase_links=phase_links,
        sha256=worker.sha256,
    )

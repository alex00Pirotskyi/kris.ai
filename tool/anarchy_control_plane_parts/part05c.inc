# Canonical repository-relative identity for P24 runtime paths.
#
# Persisted control-plane paths remain POSIX repository-relative strings.
# Runtime filesystem paths may arrive through legitimate aliases (for example
# macOS /var -> /private/var or Windows 8.3/case aliases).  Every conversion
# from an absolute runtime path back to a repository identity must pass through
# this helper after fail-closed canonical containment validation.

REPOSITORY_RELATIVE_PATH_AUDIT = {
    "write_generated": "alias-sensitive project argument; canonical helper required",
    "iter_scope_files": "alias-sensitive sort identity; canonical helper required",
    "snapshot_scopes": "alias-sensitive snapshot identity; canonical helper required",
    "parse_phase": "safe: validate_project supplies a canonical project root",
    "parse_worker": "safe: validate_project supplies a canonical project root",
    "glob_files": "safe: validate_project supplies a canonical project root",
    "discover_phases": "safe: paths originate from canonical glob_files",
    "discover_workers": "safe: paths originate from canonical glob_files",
    "parse_claim": "safe: paths originate from canonical glob_files",
    "validate_authority": "safe: state.project is canonical",
}


def repository_relative(
    project: Path,
    candidate: Path,
    *,
    must_exist: bool | None = None,
) -> str:
    """Return a stable POSIX repository-relative identity, fail-closed.

    Both root and candidate are canonicalized before containment is checked.
    Existing symlink/junction targets are therefore compared by their resolved
    location, not by a lexical prefix.  A non-existing output is accepted only
    when ``must_exist`` is false (or omitted) and all existing parents resolve
    inside the canonical repository.  Root equality is represented by ``.``.
    """
    root = _canonical_path(Path(project), strict=True)
    raw_candidate = Path(candidate)
    if not raw_candidate.is_absolute():
        raise ControlPlaneError(
            f"repository-relative conversion requires an absolute candidate: {candidate!s}"
        )

    exists = raw_candidate.exists()
    require_existing = exists if must_exist is None else must_exist
    if require_existing and not exists:
        raise ControlPlaneError(f"required repository path is missing: {candidate!s}")

    resolved = _canonical_path(
        raw_candidate,
        strict=bool(require_existing or exists),
    )
    if not _same_or_descendant(root, resolved):
        raise ControlPlaneError(f"path escapes repository: {candidate!s}")

    root_key = os.path.normcase(os.path.normpath(str(root)))
    candidate_key = os.path.normcase(os.path.normpath(str(resolved)))
    if candidate_key == root_key:
        relative = "."
    else:
        # Path.relative_to is preferred once both operands are canonical.  The
        # guarded relpath fallback handles platforms whose Path implementation
        # retains a harmless case alias after canonicalization.  Containment
        # and cross-drive checks already succeeded above.
        try:
            relative = resolved.relative_to(root).as_posix()
        except ValueError:
            try:
                relative = os.path.relpath(str(resolved), str(root)).replace("\\", "/")
            except (OSError, ValueError) as error:
                raise ControlPlaneError(
                    f"cannot derive repository-relative path for {candidate!s}: {error}"
                ) from error

    normalized = PurePosixPath(relative).as_posix()
    if not safe_relative(normalized):
        raise ControlPlaneError(
            f"canonical repository-relative identity is unsafe: {normalized!r}"
        )
    return normalized

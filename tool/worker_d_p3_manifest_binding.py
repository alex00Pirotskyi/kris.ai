#!/usr/bin/env python3
"""Verify P3 evidence-manifest artifact bindings against repository bytes."""
from __future__ import annotations
import argparse,hashlib,json,re
from pathlib import Path,PurePosixPath
MANIFEST_PATH="release/evidence/P3-001/manifest.json"
SHA256_RE=re.compile(r"^[0-9a-f]{64}$")
EXPECTED_ARTIFACT_PATHS=frozenset({
".github/workflows/worker-d-p3-readiness.yml","config/test_center_registry.v1.json","docs/roadmap/progress/2026-08-05-p3-001-readiness.md","release/evidence/P3-001/READINESS.md","release/evidence/P3-001/claim-boundary.json","release/evidence/P3-001/dependency-status.json","release/evidence/P3-001/fixture-specification.json","release/evidence/P3-001/packaging-readiness-contract.json","release/evidence/P3-001/runtime-candidate-matrix.json","release/evidence/P3-001/test-center-registration.json","tool/worker_d_p3_readiness.py","tool/worker_d_p3_readiness_test.py"})
def _safe_relative_path(value:object)->str|None:
    if not isinstance(value,str) or not value or value!=value.strip(): return None
    path=PurePosixPath(value.replace("\\","/"))
    if path.is_absolute() or ".." in path.parts or "." in path.parts:return None
    return path.as_posix()
def validate(root:Path)->list[str]:
    errors=[]; manifest_path=root/MANIFEST_PATH
    if manifest_path.is_symlink() or not manifest_path.is_file():return [f"missing evidence manifest {MANIFEST_PATH}"]
    try:manifest=json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError,UnicodeError,json.JSONDecodeError) as error:return [f"evidence manifest is unreadable: {error}"]
    artifacts=manifest.get("artifacts")
    if not isinstance(artifacts,list):return ["manifest artifacts must be an array"]
    observed=set()
    for index,artifact in enumerate(artifacts):
        label=f"manifest artifacts[{index}]"
        if not isinstance(artifact,dict):errors.append(f"{label} must be an object");continue
        if set(artifact)!={"path","sha256"}:errors.append(f"{label} must contain exactly path and sha256");continue
        rel=_safe_relative_path(artifact.get("path"))
        if rel is None:errors.append(f"{label} has unsafe path");continue
        if rel in observed:errors.append(f"duplicate manifest artifact path {rel}");continue
        observed.add(rel); expected=artifact.get("sha256")
        if not isinstance(expected,str) or SHA256_RE.fullmatch(expected) is None:errors.append(f"manifest artifact digest invalid {rel}");continue
        target=root/rel
        try:target.resolve(strict=True).relative_to(root.resolve())
        except (FileNotFoundError,RuntimeError,ValueError):errors.append(f"manifest artifact missing or escapes repository {rel}");continue
        if target.is_symlink() or not target.is_file():errors.append(f"manifest artifact is not a regular source file {rel}");continue
        actual=hashlib.sha256(target.read_bytes()).hexdigest()
        if actual!=expected:errors.append(f"manifest artifact digest mismatch {rel}: expected {expected}, computed {actual}")
    missing=sorted(EXPECTED_ARTIFACT_PATHS-observed);extra=sorted(observed-EXPECTED_ARTIFACT_PATHS)
    if missing:errors.append(f"manifest artifact bindings missing: {', '.join(missing)}")
    if extra:errors.append(f"manifest artifact bindings unexpected: {', '.join(extra)}")
    return errors
def main()->None:
    parser=argparse.ArgumentParser();parser.add_argument("--check",action="store_true");parser.add_argument("--project",default=".");args=parser.parse_args()
    if not args.check:raise SystemExit("--check is required; validator is non-mutating")
    errors=validate(Path(args.project).resolve())
    if errors:print("\n".join(f"FAIL {error}" for error in errors));raise SystemExit(1)
    print("Worker D P3 evidence artifact bindings: PASS")
if __name__=="__main__":main()

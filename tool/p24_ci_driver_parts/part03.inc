def command_exact(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    paths = _paths(root, Path(args.temporary).resolve())
    diagnostic = _read_json(paths["diagnostic"])
    commands: list[list[str]] = [
        [sys.executable, "tool/anarchy_control_plane.py", "--report", str(paths["report"]), "--project", ".", "--repository-sha", args.candidate, "--repository-tree", args.tree],
        [sys.executable, "tool/anarchy_control_plane.py", "--check", "--project", "."],
    ]
    if (root / "tool/p0_010_generated_state_test.py").is_file():
        commands.append([sys.executable, "tool/p0_010_generated_state_test.py", "--project", "."])
    if (root / "tool/generated_state_guard.py").is_file():
        commands.append([sys.executable, "tool/generated_state_guard.py", "audit", "--project", ".", "--strict"])
    records: list[dict[str, Any]] = []
    failure: str | None = None
    try:
        with paths["exact_log"].open("w", encoding="utf-8", newline="\n") as log:
            for command in commands:
                completed = _run(command, cwd=root)
                output = completed.stdout or ""
                log.write(f"## {' '.join(command)} rc={completed.returncode}\n{output}\n")
                records.append({"command": command, "returnCode": completed.returncode})
                if completed.returncode:
                    raise RuntimeError(_interesting(output, f"command exited {completed.returncode}: {' '.join(command)}"))

        if not paths["expected_index"].is_file() or not paths["expected_manifest"].is_file():
            raise RuntimeError("isolated expected generated outputs are missing")
        current_index = root / INDEX_REL
        current_manifest = root / MANIFEST_REL
        if not current_index.is_file():
            raise RuntimeError("committed generated P24 index is missing")
        if current_index.read_bytes() != paths["expected_index"].read_bytes():
            raise RuntimeError("committed generated P24 index differs from exact generation")
        if current_manifest.read_bytes() != paths["expected_manifest"].read_bytes():
            raise RuntimeError("committed SOURCE_MANIFEST.sha256 differs from canonical generation")

        diff = _run(["git", "diff", "--exit-code"], cwd=root)
        if diff.returncode:
            raise RuntimeError(f"exact checkout has a tracked diff: {diff.stdout}")
        status = _run(["git", "status", "--porcelain=v1", "--untracked-files=all"], cwd=root)
        if status.returncode or (status.stdout or "").strip():
            raise RuntimeError(f"exact checkout is dirty: {(status.stdout or '').strip()}")

        diagnostic["phases"]["exactCheck"] = {"status": "PASS", "commands": records}
        diagnostic["generatedIndex"]["status"] = "CURRENT"
        diagnostic["sourceManifest"]["status"] = "CURRENT"
        diagnostic["nonMutation"] = {"status": "PASS"}
        diagnostic["exactCheckConclusion"] = "PASS"
        return_code = 0
    except Exception as error:  # diagnostic boundary
        failure = f"{type(error).__name__}: {error}"
        with paths["exact_log"].open("a", encoding="utf-8", newline="\n") as log:
            log.write(traceback.format_exc(limit=20))
        diagnostic["phases"]["exactCheck"] = {"status": "FAIL", "commands": records}
        diagnostic["exactCheckConclusion"] = "FAIL"
        _update_failure(diagnostic, "exactCheck", failure)
        return_code = 1
    _write_json(paths["diagnostic"], diagnostic)
    return return_code


def command_enforce(args: argparse.Namespace) -> int:
    paths = _paths(Path(args.root).resolve(), Path(args.temporary).resolve())
    diagnostic = _read_json(paths["diagnostic"])
    print(_canonical_json(diagnostic), end="")
    outcomes = {
        "tests": args.tests_outcome,
        "generation": args.generation_outcome,
        "exactCheck": args.exact_outcome,
    }
    failed = [name for name, outcome in outcomes.items() if outcome != "success"]
    if failed or diagnostic.get("exactCheckConclusion") != "PASS":
        first = diagnostic.get("firstFailure") or {"detail": "exact-head validation failed without a recorded phase"}
        print(
            "P24 exact-head validation failed; phases=" + ",".join(failed) +
            "; firstFailure=" + str(first.get("detail")),
            file=sys.stderr,
        )
        return 1
    return 0


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("init", "tests", "generate", "exact", "enforce"))
    parser.add_argument("--root", default=".")
    parser.add_argument("--temporary", required=True)
    parser.add_argument("--candidate", default=os.environ.get("CANDIDATE_SHA", "UNRESOLVED"))
    parser.add_argument("--tree", default="UNRESOLVED")
    parser.add_argument("--tests-outcome", default="skipped")
    parser.add_argument("--generation-outcome", default="skipped")
    parser.add_argument("--exact-outcome", default="skipped")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    handlers = {
        "init": command_init,
        "tests": command_tests,
        "generate": command_generate,
        "exact": command_exact,
        "enforce": command_enforce,
    }
    return handlers[args.command](args)


if __name__ == "__main__":
    raise SystemExit(main())

def command_generate(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    temporary = Path(args.temporary).resolve()
    paths = _paths(root, temporary)
    diagnostic = _read_json(paths["diagnostic"])
    isolated = temporary / "p24-isolated-candidate"
    proof: dict[str, Any] = {
        "schemaVersion": "1.0.0",
        "candidateCommit": args.candidate,
        "candidateTree": args.tree,
        "lane": os.environ.get("RUNNER_OS", "unknown"),
        "sourceManifestOwner": "tool/p1a_refresh_source_manifest.py",
        "status": "FAIL",
    }
    try:
        if isolated.exists():
            shutil.rmtree(isolated)
        clone = _run(["git", "clone", "--no-checkout", str(root), str(isolated)], cwd=root)
        if clone.returncode:
            raise RuntimeError(_interesting(clone.stdout or "", "local exact-head clone failed"))
        checkout = _run(["git", "-C", str(isolated), "checkout", "--detach", args.candidate], cwd=root)
        if checkout.returncode:
            raise RuntimeError(_interesting(checkout.stdout or "", "exact candidate checkout failed"))

        write_outputs: list[dict[str, Any]] = []
        generated_bytes: list[bytes] = []
        with paths["generation_log"].open("w", encoding="utf-8", newline="\n") as log:
            for attempt in (1, 2):
                completed = _run(
                    [sys.executable, "tool/anarchy_control_plane.py", "--write", "--project", "."],
                    cwd=isolated,
                )
                output = completed.stdout or ""
                parsed = _parse_write_result(output)
                log.write(f"## write attempt={attempt} rc={completed.returncode}\n{output}\n")
                record = {"attempt": attempt, "returnCode": completed.returncode, "result": parsed}
                write_outputs.append(record)
                if completed.returncode not in {0, 1}:
                    raise RuntimeError(f"write attempt {attempt} failed before validation; rc={completed.returncode}")
                if parsed is None:
                    raise RuntimeError(f"write attempt {attempt} did not emit a structured result")
                if parsed.get("path") != INDEX_REL.as_posix():
                    raise RuntimeError(f"write attempt {attempt} emitted a noncanonical path: {parsed.get('path')!r}")
                generated = isolated / INDEX_REL
                if not generated.is_file():
                    raise RuntimeError(f"write attempt {attempt} did not produce {INDEX_REL.as_posix()}")
                generated_bytes.append(generated.read_bytes())
        if generated_bytes[0] != generated_bytes[1]:
            raise RuntimeError("second P24 write was not byte-identical")
        if write_outputs[1]["result"].get("changed") is not False:
            raise RuntimeError("second P24 write was not idempotent (changed must be false)")
        paths["expected_index"].write_bytes(generated_bytes[1])
        generated_hash = hashlib.sha256(generated_bytes[1]).hexdigest()

        generator = isolated / "tool/p1a_refresh_source_manifest.py"
        first = _run([sys.executable, str(generator), str(isolated)], cwd=isolated)
        if first.returncode:
            raise RuntimeError(_interesting(first.stdout or "", "first manifest generation failed"))
        first_manifest = (isolated / MANIFEST_REL).read_bytes()
        second = _run([sys.executable, str(generator), str(isolated)], cwd=isolated)
        if second.returncode:
            raise RuntimeError(_interesting(second.stdout or "", "second manifest generation failed"))
        second_manifest = (isolated / MANIFEST_REL).read_bytes()
        if first_manifest != second_manifest:
            raise RuntimeError("canonical source-manifest generator is not byte-idempotent")
        paths["expected_manifest"].write_bytes(second_manifest)
        manifest_hash = hashlib.sha256(second_manifest).hexdigest()

        proof.update({
            "status": "PASS",
            "controlPlaneWrites": write_outputs,
            "generatedIndexSha256": generated_hash,
            "generatedIndexSecondWriteByteIdentical": True,
            "generatedIndexSecondWriteChanged": write_outputs[1]["result"]["changed"],
            "generatedIndexRepositoryRelativePath": write_outputs[1]["result"]["path"],
            "sourceManifestSha256": manifest_hash,
            "sourceManifestSecondWriteByteIdentical": True,
        })
        diagnostic["phases"]["generation"] = {"status": "PASS"}
        diagnostic["generatedIndex"] = {
            "status": "GENERATED", "sha256": generated_hash,
            "secondWriteByteIdentical": True,
            "secondWriteChanged": write_outputs[1]["result"]["changed"],
            "repositoryRelativePath": write_outputs[1]["result"]["path"],
        }
        diagnostic["sourceManifest"] = {
            "status": "GENERATED", "sha256": manifest_hash,
            "secondWriteByteIdentical": True,
        }
        diagnostic["idempotence"] = {"status": "PASS"}
        return_code = 0
    except Exception as error:  # diagnostic boundary
        detail = f"{type(error).__name__}: {error}"
        proof["exception"] = detail
        proof["traceback"] = traceback.format_exc(limit=20)
        _update_failure(diagnostic, "generation", detail)
        return_code = 1
    finally:
        _write_json(paths["proof"], proof)
        _write_json(paths["diagnostic"], diagnostic)
    return return_code



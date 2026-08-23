from pathlib import Path

path = Path('tool/p0_008_roadmap_test.py')
text = path.read_text(encoding='utf-8')
old = '''        owner_task = {
            1: "P1-001",
            2: "P1-001",  # authority boundary accepted; profile schema remains P1-002
            3: "P1-005",
            4: "P1-001",  # supervision boundary accepted; technology remains P2-004
            6: "P1-008",
        }
        accepted_count = 0
'''
new = '''        owner_task = {
            1: "P1-001",
            2: "P1-001",  # authority boundary accepted; profile schema remains P1-002
            3: "P1-005",
            4: "P1-001",  # supervision boundary accepted; technology remains P2-004
            6: "P1-008",
        }
        later_owner_evidence = {
            5: ("P3-008", "P4-011"),
        }

        def later_owner_tasks_complete(index: int) -> bool:
            task_ids = later_owner_evidence.get(index)
            if task_ids is None:
                return False
            for task_id in task_ids:
                manifest_path = root / "release" / "evidence" / task_id / "manifest.json"
                results_path = root / "release" / "evidence" / task_id / "test-results.json"
                if not manifest_path.is_file() or not results_path.is_file():
                    return False
                manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
                results = json.loads(results_path.read_text(encoding="utf-8"))
                require(manifest.get("taskId") == task_id, f"{task_id} evidence task identity mismatch")
                require(manifest.get("status") == "implemented", f"{task_id} evidence is not implemented")
                require(
                    manifest.get("testResults") == f"release/evidence/{task_id}/test-results.json",
                    f"{task_id} test-results authority mismatch",
                )
                acceptance = manifest.get("acceptance")
                require(isinstance(acceptance, dict), f"{task_id} acceptance evidence missing")
                proof = acceptance.get("proof")
                require(isinstance(proof, list) and proof, f"{task_id} acceptance proof missing")
                missing_proof = [
                    item for item in proof
                    if not isinstance(item, str) or not (root / item).is_file()
                ]
                require(not missing_proof, f"{task_id} acceptance proof missing files: {missing_proof}")
                require(results.get("taskId") == task_id, f"{task_id} test result identity mismatch")
                require(results.get("result") == "passed", f"{task_id} test results are not passing")
            return True

        accepted_count = 0
'''
if text.count(old) != 1:
    raise SystemExit('ADR owner-task anchor mismatch')
text = text.replace(old, new, 1)
old = '''            should_accept = index == 0 or (
                index in owner_task and tasks.get(owner_task[index], {}).get("status") == "DONE"
            )
'''
new = '''            should_accept = index == 0 or (
                index in owner_task and tasks.get(owner_task[index], {}).get("status") == "DONE"
            ) or later_owner_tasks_complete(index)
'''
if text.count(old) != 1:
    raise SystemExit('ADR acceptance expression anchor mismatch')
text = text.replace(old, new, 1)
old = '''        required.update(str(task["packet"]) for task in manifest["tasks"])
        missing = sorted(item for item in required if item not in entries)
'''
new = '''        required.update(str(task["packet"]) for task in manifest["tasks"])
        for task_id in ("P3-008", "P4-011"):
            manifest_path = f"release/evidence/{task_id}/manifest.json"
            results_path = f"release/evidence/{task_id}/test-results.json"
            if (root / manifest_path).is_file() or (root / results_path).is_file():
                required.update((manifest_path, results_path))
        missing = sorted(item for item in required if item not in entries)
'''
if text.count(old) != 1:
    raise SystemExit('source-manifest later-evidence anchor mismatch')
path.write_text(text, encoding='utf-8')

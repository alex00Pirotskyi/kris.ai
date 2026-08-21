#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
import pathlib
import re
import subprocess
import sys
import types
import unittest
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any
from unittest import mock

HERE = pathlib.Path(__file__).resolve().parent
BASE = HERE / "kris_qwen_worker.py"
ENTRY = HERE / "kris_qwen_worker_v531.py"
RECONCILE = HERE / "kris_qwen_v53_reconcile.py"


def load(path: pathlib.Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class DummyTransient(RuntimeError):
    def __init__(self, message: str, *, retry_seconds=None, signature=None):
        super().__init__(message)
        self.retry_seconds = retry_seconds
        self.signature = signature


@dataclass
class DummyReply:
    content: str
    duration_s: float
    prompt_tokens: int | None = None
    completion_tokens: int | None = None
    total_tokens: int | None = None


def reconcile_namespace() -> dict[str, Any]:
    module = load(RECONCILE, "kris_qwen_v531_reconcile_test_source")
    ns: dict[str, Any] = {
        "Any": Any,
        "Config": object,
        "ModelReply": DummyReply,
        "WorkerError": RuntimeError,
        "CASLost": RuntimeError,
        "TransientFleetState": DummyTransient,
        "pathlib": pathlib,
        "re": re,
        "hashlib": hashlib,
        "json": json,
        "time": __import__("time"),
        "urllib": __import__("urllib"),
        "preflight": lambda cfg: {},
    }
    source = "from __future__ import annotations\n" + module.RECONCILE_BLOCK
    exec(compile(source, str(RECONCILE), "exec"), ns, ns)
    return ns


class TransformContractTest(unittest.TestCase):
    def test_real_version_entry_executes_531(self) -> None:
        result = subprocess.run(
            [sys.executable, str(ENTRY), "version"],
            cwd=HERE.parent,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        value = json.loads(result.stdout)
        self.assertEqual(value.get("scriptVersion"), "5.3.1")

    def test_transform_orders_reconciliation_before_mutation_and_seeding(self) -> None:
        entry = load(ENTRY, "kris_qwen_v531_transform_test")
        text = entry.transform(BASE.read_text(encoding="utf-8"))
        compile(text, str(BASE), "exec")
        first_refresh = text.index("        refresh_snapshots(cfg)\n        # Reconcile safe generated Product descendants")
        first_reap = text.index("        reap_expired_runtime(cfg)\n", first_refresh)
        self.assertLess(first_refresh, first_reap)
        seed = text.index("        frontier_recovery = recover_continuous_frontier(cfg, worker_identity, log)\n")
        preceding = text.rfind("        resilient_preflight(cfg)\n", 0, seed)
        self.assertGreater(preceding, 0)
        self.assertLess(preceding, seed)
        self.assertIn("wait_for_product_divergence_change", text)
        self.assertIn("response_schema=REVIEW_ACTION_SCHEMA", text)
        self.assertIn("response_schema=REVIEW_FINAL_SCHEMA", text)


class DescendantPolicyTest(unittest.TestCase):
    def setUp(self) -> None:
        self.ns = reconcile_namespace()

    def test_divergence_parser_is_exact(self) -> None:
        parsed = self.ns["parse_product_divergence"](
            "MISSION_V15_LIVE_RUNTIME_AUDIT_ERROR: PRODUCT_RUNTIME_DIVERGENCE:"
            "PR71:" + "a" * 40 + "!=LIVE:" + "b" * 40
        )
        self.assertEqual(parsed, (71, "a" * 40, "b" * 40))
        self.assertIsNone(self.ns["parse_product_divergence"]("other error"))

    def test_only_task_evidence_and_root_source_manifest_are_automatic(self) -> None:
        allowed = self.ns["generated_descendant_path_allowed"]
        self.assertTrue(allowed("P11-001", "SOURCE_MANIFEST.sha256"))
        self.assertTrue(allowed("P11-001", "release/evidence/P11-001/manifest.json"))
        self.assertTrue(allowed("P11-001", "release/evidence/P11-001/generated/a.json"))
        self.assertFalse(allowed("P11-001", "release/evidence/P5-001/manifest.json"))
        self.assertFalse(allowed("P11-001", "tool/worker_e_dependency_binding.py"))
        self.assertFalse(allowed("P11-001", "lib/product/product_runtime.dart"))

    def test_cheap_watch_polls_refs_until_one_changes(self) -> None:
        ns = self.ns
        watch = ns["ProductDivergenceWatch"](
            "diverged",
            product_pr=71,
            product_branch="agent/e/native-parity-readiness",
            runtime_ref="a" * 40,
            product_ref="b" * 40,
            safety_reason="unexpected source path",
        )
        calls = {"runtime": 0, "product": 0}

        def remote(_cfg, branch):
            if branch == "agent/mission-runtime":
                calls["runtime"] += 1
                return "a" * 40 if calls["runtime"] == 1 else "c" * 40
            calls["product"] += 1
            return "b" * 40

        class FakeTime:
            value = 0.0

            @classmethod
            def monotonic(cls):
                cls.value += 1.0
                return cls.value

            @classmethod
            def sleep(cls, _seconds):
                return None

        cfg = types.SimpleNamespace(
            root=pathlib.Path("/tmp/qwen-test"),
            runtime_branch="agent/mission-runtime",
        )
        ns["_remote_head_only"] = remote
        ns["read_stop_request"] = lambda _root: None
        ns["write_worker_status"] = lambda *_args, **_kwargs: None
        ns["time"] = FakeTime
        result = ns["wait_for_product_divergence_change"](cfg, watch, jobs_completed=3)
        self.assertEqual(result, "CHANGED")
        self.assertEqual(calls["runtime"], 2)


class ReviewJsonSchemaTest(unittest.TestCase):
    def setUp(self) -> None:
        self.ns = reconcile_namespace()
        self.ns["compact_messages"] = lambda messages, max_chars: messages

    def _cfg(self):
        return types.SimpleNamespace(
            model_base="http://127.0.0.1:8080/v1",
            model="qwen",
            ctx_size=65536,
            temperature=0.15,
            max_tokens=2048,
            request_timeout=30,
            api_key="",
        )

    def test_review_request_prefers_strict_json_schema(self) -> None:
        payloads = []

        class Response:
            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return False

            def read(self):
                return json.dumps({
                    "choices": [{"message": {"content": '{"action":"review_diff","why":"bind"}'}}],
                    "usage": {"prompt_tokens": 1, "completion_tokens": 1},
                }).encode()

        def urlopen(request, timeout):
            payloads.append(json.loads(request.data.decode()))
            return Response()

        with mock.patch.object(urllib.request, "urlopen", side_effect=urlopen):
            reply = self.ns["chat_reply"](
                self._cfg(),
                [{"role": "user", "content": "review"}],
                response_schema=self.ns["REVIEW_ACTION_SCHEMA"],
            )
        self.assertIn("review_diff", reply.content)
        fmt = payloads[0]["response_format"]
        self.assertEqual(fmt["type"], "json_schema")
        self.assertTrue(fmt["json_schema"]["strict"])
        self.assertEqual(fmt["json_schema"]["schema"], self.ns["REVIEW_ACTION_SCHEMA"])

    def test_schema_rejection_falls_back_to_json_object(self) -> None:
        payloads = []

        class Response:
            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return False

            def read(self):
                return json.dumps({
                    "choices": [{"message": {"content": '{"action":"blocked","reason":"x","why":"y"}'}}]
                }).encode()

        def urlopen(request, timeout):
            payloads.append(json.loads(request.data.decode()))
            if len(payloads) == 1:
                raise urllib.error.HTTPError(request.full_url, 400, "bad schema", {}, None)
            return Response()

        with mock.patch.object(urllib.request, "urlopen", side_effect=urlopen):
            self.ns["chat_reply"](
                self._cfg(),
                [{"role": "user", "content": "review"}],
                response_schema=self.ns["REVIEW_ACTION_SCHEMA"],
            )
        self.assertEqual(payloads[0]["response_format"]["type"], "json_schema")
        self.assertEqual(payloads[1]["response_format"], {"type": "json_object"})


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path
import tempfile

import dependency_policy as policy


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="kristin-deps-") as raw:
        root = Path(raw)
        npm = root / "package-lock.json"
        npm.write_text(
            json.dumps(
                {
                    "lockfileVersion": 3,
                    "packages": {
                        "": {"dependencies": {"safe": "1.0.0"}},
                        "node_modules/safe": {
                            "version": "1.0.0",
                            "resolved": "https://registry.npmjs.org/safe/-/safe-1.0.0.tgz",
                            "integrity": "sha512-AAAA",
                            "license": "MIT",
                        },
                    },
                }
            ),
            encoding="utf-8",
        )
        pub = root / "pubspec.lock"
        pub.write_text(
            "packages:\n"
            "  safe_pub:\n"
            "    dependency: \"direct main\"\n"
            "    description:\n"
            "      name: safe_pub\n"
            f"      sha256: {'a' * 64}\n"
            "      url: \"https://pub.dev\"\n"
            "    source: hosted\n"
            "    version: \"2.0.0\"\n",
            encoding="utf-8",
        )
        pub_cache = root / "pub-cache"
        package = pub_cache / "hosted" / "pub.dev" / "safe_pub-2.0.0"
        package.mkdir(parents=True)
        package.joinpath("LICENSE").write_text(
            "Permission is hereby granted, free of charge, to any person obtaining a copy...",
            encoding="utf-8",
        )

        dependencies = policy.parse_npm_lock(npm)
        dependencies += policy.parse_pub_lock(pub, pub_cache=pub_cache)
        by_id = {item.identity: item for item in dependencies}
        assert by_id["npm:safe@1.0.0"].license == "MIT"
        assert by_id["Pub:safe_pub@2.0.0"].license == "MIT"
        advisories = {identity: [] for identity in by_id}
        report = policy.evaluate(dependencies, advisories)
        assert report["passed"] is True
        assert report["dependencyCount"] == 2
        assert len(str(report["dependencySetSha256"])) == 64

        vulnerable = dict(advisories)
        vulnerable["npm:safe@1.0.0"] = [{"id": "OSV-TEST-1"}]
        report = policy.evaluate(dependencies, vulnerable)
        assert report["passed"] is False
        assert any(row["code"] == "known_vulnerability" for row in report["failures"])

        denied = [
            policy.Dependency("npm", "copyleft", "1.0.0", "sha512-X", "GPL-3.0", True)
        ]
        report = policy.evaluate(denied, {denied[0].identity: []})
        assert report["passed"] is False
        assert report["failures"][0]["code"] == "license_denied"

        malformed = root / "bad-package-lock.json"
        malformed.write_text(
            json.dumps(
                {
                    "lockfileVersion": 3,
                    "packages": {
                        "": {},
                        "node_modules/bad": {
                            "version": "1.0.0",
                            "resolved": "http://example.invalid/bad.tgz",
                            "license": "MIT",
                        },
                    },
                }
            ),
            encoding="utf-8",
        )
        try:
            policy.parse_npm_lock(malformed)
        except ValueError as exc:
            assert "npm_lock_integrity_invalid" in str(exc)
        else:
            raise AssertionError("expected malformed npm lock to fail")

    print("PASS dependency policy: lock integrity, licenses and advisory fail-closed behavior")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

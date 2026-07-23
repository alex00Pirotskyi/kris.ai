#!/usr/bin/env python3
"""Generate the Dart migration registry from reviewed SQL source files."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = ROOT / "migrations" / "workflow"
OUTPUT = ROOT / "lib" / "product" / "generated" / "workflow_migrations.g.dart"
PATTERN = re.compile(r"^(?P<version>[0-9]{3})_(?P<name>[a-z0-9_]+)\.sql$")


@dataclass(frozen=True)
class Migration:
    version: int
    name: str
    sql: str
    sha256: str


def load() -> list[Migration]:
    migrations: list[Migration] = []
    for path in sorted(MIGRATIONS.glob("*.sql")):
        match = PATTERN.match(path.name)
        if not match:
            raise SystemExit(f"Unexpected migration name: {path.name}")
        sql = path.read_text(encoding="utf-8").replace("\r\n", "\n")
        if not sql.endswith("\n"):
            sql += "\n"
        migrations.append(
            Migration(
                version=int(match.group("version")),
                name=match.group("name"),
                sql=sql,
                sha256=hashlib.sha256(sql.encode("utf-8")).hexdigest(),
            )
        )
    expected = list(range(1, len(migrations) + 1))
    actual = [item.version for item in migrations]
    if actual != expected:
        raise SystemExit(f"Workflow migrations must be contiguous: {actual!r}")
    return migrations


def dart_string(value: str) -> str:
    # json.dumps produces a valid double-quoted Dart string for this ASCII SQL.
    return json.dumps(value, ensure_ascii=True)


def render(migrations: list[Migration]) -> str:
    digest_input = "\n".join(
        f"{item.version}:{item.name}:{item.sha256}" for item in migrations
    )
    digest = hashlib.sha256(digest_input.encode("utf-8")).hexdigest()
    lines = [
        "// GENERATED FILE. DO NOT EDIT.",
        "// Source: migrations/workflow/*.sql", 
        "",
        "class GeneratedWorkflowMigration {",
        "  const GeneratedWorkflowMigration({",
        "    required this.version,",
        "    required this.name,",
        "    required this.sql,",
        "    required this.sha256,",
        "  });",
        "",
        "  final int version;",
        "  final String name;",
        "  final String sql;",
        "  final String sha256;",
        "}",
        "",
        f"const int generatedWorkflowSchemaVersion = {len(migrations)};",
        f"const String generatedWorkflowMigrationDigest = '{digest}';",
        "",
        "const List<GeneratedWorkflowMigration> generatedWorkflowMigrations =",
        "    <GeneratedWorkflowMigration>[",
    ]
    for item in migrations:
        lines.extend(
            [
                "  GeneratedWorkflowMigration(",
                f"    version: {item.version},",
                f"    name: '{item.name}',",
                f"    sql: {dart_string(item.sql)},",
                f"    sha256: '{item.sha256}',",
                "  ),",
            ]
        )
    lines.extend(["];", ""])
    return "\n".join(lines).replace("];\n\n\n", "];\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    rendered = render(load())
    if args.check:
        if not OUTPUT.is_file() or OUTPUT.read_text(encoding="utf-8") != rendered:
            print(f"STALE {OUTPUT.relative_to(ROOT)}")
            return 1
        print(f"PASS {OUTPUT.relative_to(ROOT)}")
        return 0
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(rendered, encoding="utf-8", newline="\n")
    print(OUTPUT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

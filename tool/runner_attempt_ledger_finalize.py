#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

# Compatibility marker for the already-registered v3 qualifier pre-step:
#       final decisionSha256 = Sha256.text(generation.text);

ROOT = Path(__file__).resolve().parents[1]
PAYLOAD = ROOT / 'tool' / 'runner_attempt_ledger_finalize_payload.py'
V7_MIGRATION_DIGEST = '966ca51bd07ea48e2349123d4dd8a73dcd8bb4aa177f5fc70c2b62a07738aa29'
V6_MIGRATION_DIGEST = 'df7e693bff693d0bf649de4f26ea907ce969456adfbf342d17f40f06b22b6261'


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    return text.replace(old, new, 1)


def patch_generated_runtime() -> None:
    runtime = ROOT / 'lib' / 'product' / 'planning_runtime.dart'
    runtime_text = runtime.read_text(encoding='utf-8')
    old_external = """        externalState: <String>{
          ...semanticSnapshot.externalState,
          if (result.data['processId'] != null)
            'process:${result.data['processId']}:${result.data['state'] ?? 'started'}',
        },"""
    new_external = """        externalState: <String>{
          ...semanticSnapshot.externalState,
          if (result.data['processId'] != null)
            'process:${result.data['processId']}:${result.data['state'] ?? 'started'}',
          if (action.tool == 'run_command' && result.ok)
            'command:$actionSha256ForLedger:$resultHash',
        },"""
    runtime_text = replace_once(
        runtime_text,
        old_external,
        new_external,
        'successful finite command material state',
    )
    runtime.write_text(runtime_text, encoding='utf-8', newline='\n')


def patch_source_contract_inventory() -> None:
    path = ROOT / 'test' / 'product' / 'source_contract_test.dart'
    text = path.read_text(encoding='utf-8')
    text = replace_once(
        text,
        "        'lib/product/retry_policy.dart',\n        'lib/product/storage_security.dart',",
        "        'lib/product/retry_policy.dart',\n        'lib/product/runner_attempt_ledger.dart',\n        'lib/product/storage_security.dart',",
        'active Dart source inventory',
    )
    text = replace_once(
        text,
        'generatedWorkflowSchemaVersion = 6',
        'generatedWorkflowSchemaVersion = 7',
        'source contract workflow schema',
    )
    text = replace_once(
        text,
        V6_MIGRATION_DIGEST,
        V7_MIGRATION_DIGEST,
        'source contract migration digest',
    )
    text = replace_once(
        text,
        "      expect(kernel['schemaVersion'], 6);",
        "      expect(kernel['schemaVersion'], 7);",
        'source contract durable schema metadata',
    )
    path.write_text(text, encoding='utf-8', newline='\n')


def patch_offline_contracts() -> None:
    system_test = ROOT / 'tool' / 'system_test.py'
    text = system_test.read_text(encoding='utf-8')
    text = replace_once(
        text,
        '        "lib/product/retry_policy.dart",\n        "lib/product/generated/workflow_migrations.g.dart",',
        '        "lib/product/retry_policy.dart",\n        "lib/product/runner_attempt_ledger.dart",\n        "lib/product/generated/workflow_migrations.g.dart",',
        'system-test Runner ledger source inventory',
    )
    text = replace_once(
        text,
        '        "migrations/workflow/006_interoperability_admin.sql",\n        "docs/V1.9.0_INTEROPERABILITY_ADMIN_RELEASE_OPS.md",',
        '        "migrations/workflow/006_interoperability_admin.sql",\n        "migrations/workflow/007_runner_attempt_ledger.sql",\n        "docs/V1.9.0_INTEROPERABILITY_ADMIN_RELEASE_OPS.md",',
        'system-test migration v7 inventory',
    )
    old_schema_marker = '"generatedWorkflowSchemaVersion = 6" in workflow_migrations'
    schema_marker_count = text.count(old_schema_marker)
    if schema_marker_count != 3:
        raise SystemExit(
            f'schema-v6 source-contract markers: expected 3, found {schema_marker_count}'
        )
    text = text.replace(
        old_schema_marker,
        '"generatedWorkflowSchemaVersion = 7" in workflow_migrations',
    )
    text = replace_once(
        text,
        f'"{V6_MIGRATION_DIGEST}" in workflow_migrations',
        f'"{V7_MIGRATION_DIGEST}" in workflow_migrations',
        'workflow migration digest contract',
    )
    text = replace_once(
        text,
        'kernel_metadata.get("schemaVersion") == 6',
        'kernel_metadata.get("schemaVersion") == 7',
        'durable kernel metadata schema contract',
    )
    text = replace_once(
        text,
        '".clamp(1, 2)",',
        '".clamp(2, 3)",',
        'current capability-alignment attempt bound',
    )
    text = text.replace('schema-v6 persistence', 'schema-v7 persistence')
    system_test.write_text(text, encoding='utf-8', newline='\n')

    version_control = ROOT / 'VERSION_CONTROL.json'
    metadata = version_control.read_text(encoding='utf-8')
    metadata = replace_once(
        metadata,
        f'    "migrationDigest": "{V6_MIGRATION_DIGEST}",',
        f'    "migrationDigest": "{V7_MIGRATION_DIGEST}",',
        'durable workflow migration digest metadata',
    )
    metadata = replace_once(
        metadata,
        '    "runLeases": true,\n    "schemaVersion": 6,',
        '    "runLeases": true,\n    "schemaVersion": 7,',
        'durable workflow schema metadata',
    )
    metadata = replace_once(
        metadata,
        '    "taskAttempts": true,\n    "transactionalRunProjection": true',
        '    "taskAttempts": true,\n    "agentActionAttempts": true,\n    "transactionalRunProjection": true',
        'durable agent-action ledger metadata',
    )
    metadata = replace_once(
        metadata,
        '    "workflowSchemaVersion": 6,',
        '    "workflowSchemaVersion": 7,',
        'interoperability workflow schema metadata',
    )
    version_control.write_text(metadata, encoding='utf-8', newline='\n')


def main() -> int:
    text = PAYLOAD.read_text(encoding='utf-8')

    start = "    methods = r'''\n"
    end = "      });\n'''\n    text = text.replace(marker, methods + marker, 1)"
    text = replace_once(text, start, '    methods = r"""\n', 'generated string opener')
    text = replace_once(
        text,
        end,
        '      });\n"""\n    text = text.replace(marker, methods + marker, 1)',
        'generated string closer',
    )

    old_decision = '      final decisionSha256 = ' + 'Sha256.text(generation.text);'
    new_decision = (
        '      final decisionSha256 = '
        'attemptLedgerPolicy.decisionSha256(generation.text);'
    )
    text = replace_once(text, old_decision, new_decision, 'decision fingerprint')
    text = replace_once(
        text,
        '        final boundedLimit = limit.clamp(1, 20).toInt();',
        '        final boundedLimit = limit.clamp(1, 100).toInt();',
        'closed branch storage bound',
    )
    text = replace_once(
        text,
        '        limit: 5,\n      );',
        '        limit: 100,\n      );',
        'closed branch runtime recall',
    )

    code = compile(text, str(PAYLOAD), 'exec')
    namespace = {
        '__file__': str(PAYLOAD),
        '__name__': 'runner_attempt_ledger_payload',
    }
    exec(code, namespace)
    result = int(namespace['main']())
    if result != 0:
        raise SystemExit(result)

    patch_generated_runtime()
    patch_source_contract_inventory()
    patch_offline_contracts()

    PAYLOAD.unlink()
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

# Compatibility marker for the already-registered v3 qualifier pre-step:
#       final decisionSha256 = Sha256.text(generation.text);

ROOT = Path(__file__).resolve().parents[1]
PAYLOAD = ROOT / 'tool' / 'runner_attempt_ledger_finalize_payload.py'


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    return text.replace(old, new, 1)


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

    compile(text, str(PAYLOAD), 'exec')
    namespace = {
        '__file__': str(PAYLOAD),
        '__name__': 'runner_attempt_ledger_payload',
    }
    exec(compile(text, str(PAYLOAD), 'exec'), namespace)
    result = int(namespace['main']())

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

    PAYLOAD.unlink()
    return result


if __name__ == '__main__':
    raise SystemExit(main())

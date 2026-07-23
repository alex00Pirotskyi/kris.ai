#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys


def main() -> int:
    request = json.loads(os.environ['KRISTIN_A2A_REQUEST_JSON'])
    contract = request['contract']
    payload = request.get('payload') or {}
    used_capabilities = ['summarize']
    artifacts = [{'path': 'artifacts/summary.txt', 'logicalType': 'text'}]
    steps = 2
    if payload.get('forceUnauthorizedCapability'):
        used_capabilities.append('deploy')
    if payload.get('forceUnexpectedArtifact'):
        artifacts = [{'path': 'artifacts/private.txt', 'logicalType': 'text'}]
    if payload.get('forceTooManySteps'):
        steps = int(contract['maxSteps']) + 1
    result = {
        'taskId': contract['taskId'],
        'status': 'completed',
        'usedCapabilities': used_capabilities,
        'outputArtifacts': artifacts,
        'steps': steps,
        'summary': 'Delegated summary complete.',
    }
    sys.stdout.write(json.dumps(result, sort_keys=True))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

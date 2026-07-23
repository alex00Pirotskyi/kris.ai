#!/usr/bin/env python3
"""One-shot sandboxed MCP stdio bridge used by interoperability_v19 tests.

The target server uses newline-delimited JSON-RPC 2.0 over stdin/stdout.
The bridge performs initialize + one requested lifecycle step, then exits.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
from typing import Any


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False)


def send_line(process: subprocess.Popen[str], payload: dict[str, Any]) -> None:
    assert process.stdin is not None
    process.stdin.write(canonical_json(payload) + '\n')
    process.stdin.flush()


def recv_line(process: subprocess.Popen[str]) -> dict[str, Any]:
    assert process.stdout is not None
    line = process.stdout.readline()
    if not line:
        stderr = ''
        if process.stderr is not None:
            stderr = process.stderr.read()
        raise RuntimeError(f'MCP server closed stdout. stderr={stderr[-1200:]}')
    return json.loads(line)


def request(process: subprocess.Popen[str], ident: int, method: str, params: dict[str, Any]) -> dict[str, Any]:
    send_line(process, {'jsonrpc': '2.0', 'id': ident, 'method': method, 'params': params})
    response = recv_line(process)
    if response.get('id') != ident:
        raise RuntimeError(f'MCP response id mismatch for {method}: {response}')
    if 'error' in response:
        raise RuntimeError(f"MCP error for {method}: {response['error']}")
    return response.get('result') or {}


def notify(process: subprocess.Popen[str], method: str, params: dict[str, Any]) -> None:
    send_line(process, {'jsonrpc': '2.0', 'method': method, 'params': params})


def main() -> int:
    request_json = json.loads(os.environ['KRISTIN_MCP_REQUEST_JSON'])
    target = json.loads(os.environ['KRISTIN_MCP_TARGET_JSON'])
    executable = str(target['executable'])
    arguments = [str(item) for item in target.get('arguments') or []]
    process = subprocess.Popen(
        [executable, *arguments],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        errors='replace',
        cwd=str(Path('/workspace')),
    )
    try:
        init = request(
            process,
            1,
            'initialize',
            {
                'protocolVersion': request_json.get('protocolVersion', '2026-07-23'),
                'clientInfo': {'name': 'Kristin Local Agent', 'version': '1.9.0+190'},
                'roots': request_json.get('roots', []),
            },
        )
        notify(process, 'notifications/initialized', {})
        operation = request_json['operation']
        mapping = {
            'list_tools': ('tools/list', {}),
            'list_resources': ('resources/list', {}),
            'list_prompts': ('prompts/list', {}),
            'call_tool': ('tools/call', request_json.get('params') or {}),
            'read_resource': ('resources/read', request_json.get('params') or {}),
            'get_prompt': ('prompts/get', request_json.get('params') or {}),
        }
        result = None
        if operation != 'initialize':
            method, params = mapping[operation]
            result = request(process, 2, method, params)
        output = {'initialize': init, 'result': result}
        sys.stdout.write(json.dumps(output, sort_keys=True))
        return 0
    finally:
        try:
            process.terminate()
            process.communicate(timeout=2)
        except Exception:
            try:
                process.kill()
            except Exception:
                pass


if __name__ == '__main__':
    raise SystemExit(main())

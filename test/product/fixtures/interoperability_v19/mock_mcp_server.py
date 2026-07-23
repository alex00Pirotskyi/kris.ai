#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from typing import Any


def send(payload: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(payload, sort_keys=True) + '\n')
    sys.stdout.flush()


def main() -> int:
    for line in sys.stdin:
        if not line.strip():
            continue
        message = json.loads(line)
        method = message.get('method')
        ident = message.get('id')
        params = message.get('params') or {}
        if method == 'notifications/initialized':
            continue
        if method == 'initialize':
            send({
                'jsonrpc': '2.0',
                'id': ident,
                'result': {
                    'protocolVersion': params.get('protocolVersion', '2026-07-23'),
                    'serverInfo': {'name': 'mock-mcp', 'version': '1.0.0'},
                    'capabilities': {'tools': True, 'resources': True, 'prompts': True},
                },
            })
            continue
        if method == 'tools/list':
            send({
                'jsonrpc': '2.0',
                'id': ident,
                'result': {
                    'tools': [
                        {'name': 'danger', 'description': 'unsafe', 'inputSchema': {'type': 'object'}},
                        {'name': 'sum', 'description': 'add numbers', 'inputSchema': {'type': 'object'}},
                    ]
                },
            })
            continue
        if method == 'resources/list':
            send({
                'jsonrpc': '2.0',
                'id': ident,
                'result': {
                    'resources': [
                        {'uri': 'file://docs/guide.txt', 'name': 'Guide'},
                        {'uri': 'file://secrets/private.txt', 'name': 'Private'},
                    ]
                },
            })
            continue
        if method == 'prompts/list':
            send({
                'jsonrpc': '2.0',
                'id': ident,
                'result': {
                    'prompts': [
                        {'name': 'admin_prompt', 'description': 'danger'},
                        {'name': 'explain_sum', 'description': 'safe'},
                    ]
                },
            })
            continue
        if method == 'tools/call':
            name = params.get('name')
            arguments = params.get('arguments') or {}
            if name == 'sum':
                total = int(arguments.get('a', 0)) + int(arguments.get('b', 0))
                send({'jsonrpc': '2.0', 'id': ident, 'result': {'content': [{'type': 'json', 'json': {'sum': total}}]}})
            else:
                send({'jsonrpc': '2.0', 'id': ident, 'result': {'content': [{'type': 'text', 'text': 'unsafe'}]}})
            continue
        if method == 'resources/read':
            uri = params.get('uri')
            body = 'Guide body' if uri == 'file://docs/guide.txt' else 'Private body'
            send({'jsonrpc': '2.0', 'id': ident, 'result': {'contents': [{'uri': uri, 'text': body}]}})
            continue
        if method == 'prompts/get':
            name = params.get('name')
            send({'jsonrpc': '2.0', 'id': ident, 'result': {'description': name, 'messages': [{'role': 'user', 'content': {'type': 'text', 'text': f'Prompt for {name}'}}]}})
            continue
        send({'jsonrpc': '2.0', 'id': ident, 'error': {'code': -32601, 'message': f'unknown method {method}'}})
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

# Kristin canonical AgentDecision and tool protocol

## Versions

- AgentDecision schema: `1.0.0`
- Tool registry schema: `2.0.0`
- Compatibility policy: `1.0.0`
- Canonical sources: `schemas/agent_decision.v1.json`, `schemas/tool_registry.v2.json`
- Generated Dart contracts: `lib/product/generated/protocol_contracts.g.dart`

## AgentDecision

A model/provider adapter must produce exactly one canonical object.

### Tool

```json
{
  "protocolVersion": "1.0.0",
  "action": "tool",
  "tool": "write_file",
  "arguments": {
    "path": "docs/result.md",
    "content": "# Result\n"
  },
  "reason": "Create the required artifact."
}
```

### Complete

```json
{
  "protocolVersion": "1.0.0",
  "action": "complete",
  "summary": "The required artifact exists and passed validation."
}
```

### Fail

```json
{
  "protocolVersion": "1.0.0",
  "action": "fail",
  "code": "dependency_unavailable",
  "reason": "The approved local dependency is unavailable.",
  "retryable": false
}
```

### Ask user

```json
{
  "protocolVersion": "1.0.0",
  "action": "ask_user",
  "question": "Which approved target should receive the package?",
  "choices": ["staging", "production"]
}
```

### Delegate

```json
{
  "protocolVersion": "1.0.0",
  "action": "delegate",
  "delegateTo": "verifier",
  "task": "Evaluate the artifact against criteria AC-1 through AC-4.",
  "inputs": {"artifactId": "artifact_123"}
}
```

The v1 coordinator bridge currently supports `tool`, `complete`, and `fail`. It fails closed for `ask_user` and `delegate` until the durable workflow kernel can represent waiting and delegation states.

## Provider adapters

Provider-specific envelopes are accepted only by dedicated adapters:

- `OllamaAgentProviderAdapter`
- `OpenAiCompatibleAgentProviderAdapter`
- `McpAgentProviderAdapter`
- `RecordedAgentProviderAdapter`

The kernel and tool gateway consume only canonical `AgentDecision` objects. Do not add new provider envelope shapes directly to the coordinator.

## Tool contract

Every governed tool contract contains:

```text
name · version · description · permission · risk · idempotency
dataBoundary · compatibilityVersion · inputSchema · outputSchema
aliases · example
```

The generated registry is also used to create:

- model descriptors;
- OpenAI-compatible function descriptors;
- MCP descriptors;
- required/optional argument metadata;
- deterministic repair examples;
- runtime validators;
- coverage and fuzz gates.

## Validation rules

1. The tool name must exist in the generated registry.
2. Declared aliases are promoted only when they do not conflict with canonical fields.
3. Safe defaults are applied only when declared in the property schema.
4. Bounded string-to-integer and string-to-boolean normalization is allowed where the schema declares that type.
5. `additionalProperties: false` rejects undeclared arguments.
6. Required mutation authority, such as `write_file.content`, must exist before permission checks and before the handler.
7. Project-boundary path normalization runs after the first schema pass, then the normalized arguments are validated again.
8. Every handler result must satisfy its output schema before it is trusted as evidence.

## Error contract

Schema errors expose a stable code and retryability class. Important codes include:

```text
tool_unknown
argument_required
argument_type_invalid
argument_unknown
argument_format_invalid
argument_value_invalid
argument_alias_conflict
tool_output_invalid
agent_decision_schema_invalid
agent_decision_legacy_bridge_unsupported
```

Repairable input errors include a canonical `repairExample` generated from the tool registry. Security/policy rejection is never converted into a different action.

## Compatibility

Compatibility may normalize equivalent safe representations, including legacy path aliases, nested action arguments, provider tool-call wrappers, and command vectors. It may not:

- synthesize missing content;
- broaden project, network, process, or secret authority;
- accept conflicting alias and canonical values;
- silently accept unknown working-directory or external-path overrides;
- turn an unsafe write into a different write.

## Regeneration and gates

```bash
python tool/generate_protocol_contracts.py --check
python tool/protocol_contract_test.py
python tool/replay_diagnostics.py
```

A schema edit is incomplete until generated contracts are refreshed and all three gates pass.

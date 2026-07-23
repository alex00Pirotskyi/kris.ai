# Local Capability Manifests

A capability manifest adds detection, verification, and run behavior without
editing Kristin's planner, executor, UI, or generic tools.

Place JSON files in:

```text
~/.kristin_agent/capability_manifests/
```

Example:

```json
{
  "id": "rust.cargo",
  "display_name": "Rust Cargo project",
  "required_executables": ["cargo"],
  "detection": {
    "all_files": ["Cargo.toml"],
    "confidence": 0.96
  },
  "verification": [
    {
      "executable": "cargo",
      "arguments": ["check"],
      "label": "Cargo check",
      "timeout_seconds": 300,
      "required": true
    },
    {
      "executable": "cargo",
      "arguments": ["test"],
      "label": "Cargo tests",
      "timeout_seconds": 600,
      "required": false
    }
  ],
  "run": {
    "executable": "cargo",
    "arguments": ["run"],
    "label": "Cargo run"
  }
}
```

## Detection fields

- `all_files` — every relative path must exist.
- `any_files` — at least one relative path must exist.
- `content_contains` — map of relative file paths to required literal text.
- `confidence` — value from `0.1` to `1.0`.

At least one file/content detection rule is required. Absolute paths, parent
traversal, drive prefixes, and duplicate capability IDs are rejected. Invalid
manifests are isolated and reported by `./init`; they do not block startup.

Verification commands are finite and pass through the same command safety and
network policy as model-issued commands. Run commands are launched as managed
processes through `run_workspace`.

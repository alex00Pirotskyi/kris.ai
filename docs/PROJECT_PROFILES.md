# Project profiles

Project profiles make **Test**, **Build**, and **Run** explicit. The same profile is used by the desktop Doctor/Quick Test UI and by the `kristin` CLI.

## Automatic detection

Kristin currently detects:

| Marker | Profile | Test command |
|---|---|---|
| Flutter `pubspec.yaml` | Flutter | `flutter analyze`, `flutter test` |
| Dart `pubspec.yaml` | Dart | `dart analyze`, `dart test` |
| `package.json` | Node.js | `npm run lint`, `npm test` when declared |
| Python package markers | Python | `python -m pytest -q` |
| `go.mod` | Go | `go test ./...` |
| `Cargo.toml` | Rust | `cargo test` |
| `.sln` or `.csproj` | .NET | `dotnet test --nologo` |
| `pom.xml` | Maven | `mvn test` |
| Gradle wrapper/build file | Gradle | wrapper `test` task |
| `CMakeLists.txt` | CMake | configure and build |
| `index.html` | Static site | no automatic tests; local Python preview |

Detection is intentionally conservative. A detected command may still require project-specific services, packages, environment values, or setup.

## Custom profile

Create `kristin.project.json` in the project root:

```json
{
  "type": "Customer API",
  "test": {
    "executable": "python3",
    "arguments": ["-m", "pytest", "-q", "tests"]
  },
  "build": {
    "executable": "docker",
    "arguments": ["build", "-t", "customer-api:local", "."]
  },
  "run": {
    "executable": "python3",
    "arguments": ["-m", "uvicorn", "app:api", "--port", "8080"]
  }
}
```

Each operation has one executable and an argument array. Shell operators, pipes, redirects, and environment interpolation are not interpreted.

## Safety boundary

The profile improves predictability; it is not a sandbox. Desktop Quick Test captures bounded output, applies a timeout, and uses a reduced environment, but the process still has the operating-system permissions of the desktop user. Review custom commands before running them.

Agent-triggered build/run access remains subject to Kristin permission scopes and the governed coordinator. CLI `run --execute` is an explicit operator command outside the agent approval flow.

# Recovery for run `run_hklw4ohlv7ocm6ItzHe1N5AB0I`

## Do not resume the old run

The v1.1.6 run is terminal and has exhausted all 12 repair credits. Preserve it as diagnostic history. Start a fresh linked run after upgrading to the canonical v1.7.0+170 source head.

## Inspect the literal path in project `test88`

The diagnostic indicates that v1.1.6 may have created this literal Windows-relative path:

```text
`docs/design/wireframes.md`
```

That means the first directory component can be named `` `docs `` and the file can be named `wireframes.md` with a trailing backtick. Review the project root before changing anything.

PowerShell inspection from the registered project root:

```powershell
Get-ChildItem -LiteralPath . -Force
Get-ChildItem -LiteralPath '.\`docs' -Force -Recurse
```

To preserve the old artifact before correcting the path, first refuse to overwrite either recovery destination:

```powershell
$malformed = '.\`docs\design\wireframes.md`'
$recovered = '.\docs\design\wireframes.v116-recovered.md'
$canonical = '.\docs\design\wireframes.md'

if (-not (Test-Path -LiteralPath $malformed -PathType Leaf)) {
  throw "Malformed diagnostic artifact was not found: $malformed"
}
if (Test-Path -LiteralPath $recovered) {
  throw "Recovery copy already exists; inspect it before continuing: $recovered"
}

New-Item -ItemType Directory -Force -Path '.\docs\design' | Out-Null
Copy-Item -LiteralPath $malformed -Destination $recovered
Get-FileHash -LiteralPath $malformed -Algorithm SHA256
Get-FileHash -LiteralPath $recovered -Algorithm SHA256
```

Review `wireframes.v116-recovered.md`. If the canonical file already exists, compare and merge manually—do not overwrite it. Only when the canonical path is absent and the recovered content is approved should you move the malformed source into place:

```powershell
if (Test-Path -LiteralPath $canonical) {
  throw "Canonical artifact already exists; compare and merge manually: $canonical"
}
Move-Item -LiteralPath $malformed -Destination $canonical
```

Remove the now-empty literal backtick directory only after confirming it contains nothing else:

```powershell
Get-ChildItem -LiteralPath '.\`docs' -Force -Recurse
Remove-Item -LiteralPath '.\`docs' -Recurse
```

These commands are intentionally manual because the redacted diagnostic does not contain the physical project tree and cannot prove that the malformed directory contains no other user data.

## Regenerate the prompt and plan

The original request contains an unresolved `{{variable_name}}` assumption placeholder. Remove or resolve it before generating the fresh plan. Review that the first design task explicitly names `docs/design/wireframes.md` and grants only the necessary project read/write and inspection tools.

## Run the replay gate before retrying

From the v1.7.0 source tree:

```powershell
.\kristin.cmd test --replay-all --project .
```

Then create a new run. Do not edit the old run record or copy its exhausted counters into the new attempt.

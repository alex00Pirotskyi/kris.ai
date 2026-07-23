$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
& "$PSScriptRoot\..\tool\verify.ps1"

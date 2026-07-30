[CmdletBinding(SupportsShouldProcess=$true)] param([switch]$PurgeTestState)
$ErrorActionPreference='Stop'; if(Get-Service KristinP1Authority -ErrorAction SilentlyContinue){Stop-Service KristinP1Authority -Force -ErrorAction SilentlyContinue; sc.exe delete KristinP1Authority | Out-Null}
if($PurgeTestState){Remove-Item -Recurse -Force (Join-Path $env:ProgramFiles 'Kristin\P1Authority') -ErrorAction SilentlyContinue}

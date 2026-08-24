[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [ValidateSet('Install','Uninstall','Status')][string]$Mode,
  [string]$ServiceBinary,[string]$ConnectorLibrary,[string]$WorkerLauncher,
  [string]$PolicySnapshot,[string]$Revocations,[string]$Approvals,
  [string]$DesktopSid,[string]$DesktopExecutableSha256,[string]$DesktopPublisherCertificateSha256,
  [string]$GrantSecretHex,[string]$OwnerSecretHex,
  [string]$InstallRoot="$env:ProgramFiles\Kristin\P1Authority",
  [string]$AppContainerName='Kristin.P2.Worker'
)
$ErrorActionPreference='Stop'
function Assert-Admin { $p=[Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent(); if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Administrator required'} }
function Sha([string]$Path){(Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()}
Assert-Admin
$serviceName='KristinP1Authority';$dataRoot=Join-Path $env:ProgramData 'Kristin\P1Authority';$connectorRoot=Join-Path $env:LOCALAPPDATA 'Kristin\authority-service';$config=Join-Path $dataRoot 'service.json'
switch($Mode){
 'Install' {
  foreach($f in @($ServiceBinary,$ConnectorLibrary,$WorkerLauncher,$PolicySnapshot,$Revocations,$Approvals)){if(-not(Test-Path -LiteralPath $f -PathType Leaf)){throw "Missing $f"}}
  if($DesktopExecutableSha256 -notmatch '^[0-9a-f]{64}$' -or $DesktopPublisherCertificateSha256 -notmatch '^[0-9a-f]{64}$'){throw 'Desktop identity invalid'}
  New-Item -ItemType Directory -Force $InstallRoot,$dataRoot,$connectorRoot | Out-Null
  Copy-Item -Force $ServiceBinary (Join-Path $InstallRoot 'kristin_p1_authority_service.exe')
  Copy-Item -Force $ConnectorLibrary (Join-Path $InstallRoot 'kristin_p1a_connector.dll')
  Copy-Item -Force $WorkerLauncher (Join-Path $InstallRoot 'kristin_p2_worker_launcher.exe')
  Copy-Item -Force $PolicySnapshot (Join-Path $dataRoot 'policy.json');Copy-Item -Force $Revocations (Join-Path $dataRoot 'revocations.json');Copy-Item -Force $Approvals (Join-Path $dataRoot 'approvals.json')
  $launcher=Join-Path $InstallRoot 'kristin_p2_worker_launcher.exe';$appSid=& $launcher --provision-appcontainer $AppContainerName; if($LASTEXITCODE -ne 0 -or $appSid -notmatch '^S-1-15-2-'){throw 'AppContainer provisioning failed'}
  $serviceExe=Join-Path $InstallRoot 'kristin_p1_authority_service.exe'; & $serviceExe --provision-key 'KristinP1AuthorityPermitV63';if($LASTEXITCODE){throw 'CNG key provisioning failed'}
  $GrantSecretHex | & $serviceExe --store-lsa-secret-stdin 'KristinP1AuthorityGrantV63';if($LASTEXITCODE){throw 'Grant LSA secret failed'}
  $OwnerSecretHex | & $serviceExe --store-lsa-secret-stdin 'KristinP1AuthorityOwnerV63';if($LASTEXITCODE){throw 'Owner LSA secret failed'}
  $cfg=@{schemaVersion='2.0.0';pipeName='\\.\pipe\KristinP1AuthorityV63';desktopSid=$DesktopSid;workerAppContainerSid=$appSid;cngKeyName='KristinP1AuthorityPermitV63';grantLsaSecretName='KristinP1AuthorityGrantV63';ownerLsaSecretName='KristinP1AuthorityOwnerV63';policySnapshotPath=(Join-Path $dataRoot 'policy.json');statePath=(Join-Path $dataRoot 'state.log');auditPath=(Join-Path $dataRoot 'audit.log');revocationsPath=(Join-Path $dataRoot 'revocations.json');approvalsPath=(Join-Path $dataRoot 'approvals.json');desktopExecutableSha256=$DesktopExecutableSha256;desktopPublisherCertificateSha256=$DesktopPublisherCertificateSha256;serviceInstanceId='p1a-windows-v63'}
  $cfg|ConvertTo-Json -Depth 8|Set-Content -Encoding utf8NoBOM $config
  & sc.exe create $serviceName binPath= ('"'+$serviceExe+'" --service-config "'+$config+'"') start= auto obj= 'NT AUTHORITY\LocalService';if($LASTEXITCODE){throw 'Service create failed'}
  & sc.exe sidtype $serviceName restricted | Out-Null
  & icacls.exe $dataRoot /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' 'NT SERVICE\KristinP1Authority:(OI)(CI)F' | Out-Null
  & sc.exe start $serviceName | Out-Null
  $connector=@{schemaVersion='2.0.0';connectorLibraryPath=(Join-Path $InstallRoot 'kristin_p1a_connector.dll');maxResponseBytes=4194304;completionEligible=$false;endpoint=@{platform='windows';transport='windows-named-pipe';address='\\.\pipe\KristinP1AuthorityV63';serviceInstanceId='p1a-windows-v63';serviceBuildSha256=(Sha $serviceExe);connectorLibrarySha256=(Sha (Join-Path $InstallRoot 'kristin_p1a_connector.dll'));installerSha256=(Sha $PSCommandPath);serverIdentity=@{serviceSid='NT SERVICE\KristinP1Authority';desktopSid=$DesktopSid;workerSid=$appSid};osEnforcedIsolation=$true;workerPrincipalSeparated=$true;typedOperationsOnly=$true;nonExportableKeys=$true};provenance=@{authorityType='p1-isolated-authority-service-v2';runtimeEligible=$true;securityIsolationActive=$true;privateAuthorityMaterialPresent=$false;arbitraryMessageSigningApi=$false;p1AmendmentMerged=$false;p1AmendmentSchemaVersion='3.0.0';independentP1aSecurityReviewApproved=$false;workerDenialTriPlatformPassed=$false;behavioralWindowsPassed=$false;behavioralMacosPassed=$false;behavioralLinuxPassed=$false;mergedCommit=('0'*40);mergedTree=('0'*40);aggregateManifestSha256=('0'*64);policySnapshotSha256=(Sha (Join-Path $dataRoot 'policy.json'))}}
  $connector|ConvertTo-Json -Depth 10|Set-Content -Encoding utf8NoBOM (Join-Path $connectorRoot 'connector-v2.json')
 }
 'Uninstall' { & sc.exe stop $serviceName 2>$null|Out-Null;& sc.exe delete $serviceName 2>$null|Out-Null;Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $InstallRoot,$dataRoot,$connectorRoot }
 'Status' { Get-Service -Name $serviceName }
}

#!/usr/bin/env python3
"""P2 runtime must be CWD-independent and contain no P1 authority service."""
from __future__ import annotations
import hashlib,json,pathlib,subprocess,sys,tempfile
def sha(p):return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
def tree(root):
 rows=[]
 for p in sorted(pathlib.Path(root).rglob('*'),key=lambda x:x.as_posix()):
  if p.is_file():rows.append(f'{p.relative_to(root).as_posix()}\0{sha(p)}')
 return hashlib.sha256('\n'.join(rows).encode()).hexdigest()
def main():
 script=pathlib.Path(__file__).with_name('p2_stage_runtime_bundle.py').resolve()
 with tempfile.TemporaryDirectory(prefix='p2-runtime-contract-v63-') as td:
  t=pathlib.Path(td);project=t/'source';out=t/'app-data/runtime/p2/current';unrelated=t/'unrelated';unrelated.mkdir()
  (project/'automation_host/src').mkdir(parents=True);(project/'automation_host/package.json').write_text('{}\n');(project/'automation_host/src/host.mjs').write_text("console.log('host');\n")
  (project/'lib/product').mkdir(parents=True);contract=project/'lib/product/p1_authority_service_contract_v1.dart';contract.write_text('abstract interface class P1AuthorityServiceClientV1 {}\n')
  node=t/'fake-node';node.write_text('#!/bin/sh\nexit 0\n');node.chmod(0o755);adapter=t/'adapter';adapter.write_text('#!/bin/sh\nexit 0\n');adapter.chmod(0o755);launcher=t/'restricted-worker-launcher';launcher.write_text('#!/bin/sh\nexit 0\n');launcher.chmod(0o755);worker_policy=t/'worker-policy.json'
  worker_policy.write_text(json.dumps({'schemaVersion':'2.0.0','platform':'linux','nodeExecutable':str((out/'node'/node.name).resolve()),'nodeSha256':sha(node),'hostScript':str((out/'automation_host/src/host.mjs').resolve()),'hostScriptSha256':sha(project/'automation_host/src/host.mjs'),'workingDirectory':str((out/'automation_host').resolve()),'launcherPath':str(launcher.resolve()),'launcherSha256':sha(launcher),'sourceCommit':'a'*40,'sourceTree':'b'*40,'packageSha256':'c'*64,'authorityAddress':'/run/kristin/p1a-v63.sock','linux':{'workerUid':65534,'workerGid':65534,'unshareMount':True,'unshareIpc':True,'unshareUts':True},'windows':{'appContainerName':'Kristin.Agent.Worker.Test','capabilitySids':[]},'macos':{'sandboxProfile':'no-network','expectedRequirement':'anchor apple generic','authorityClientEntitlement':False},'allowedEnvironmentKeys':['TEMP','TMP','LANG','LC_ALL','TERM']})+'\n')
  provisioning=t/'provisioning.json';provisioning.write_text(json.dumps({'schemaVersion':'1.0.0','provisioningType':'kristin-p2-application-runtime-environment-v1','containsSecrets':False,'environment':{'KRISTIN_P2_COMMIT_SHA':'a'*40}})+'\n')
  cmd=[sys.executable,str(script),'--project',str(project),'--destination',str(out),'--node-executable',str(node),'--source-commit','a'*40,'--source-tree','b'*40,'--provisioning-json',str(provisioning),'--restricted-worker-launcher',str(launcher),'--restricted-worker-policy',str(worker_policy),'--interactive-desktop-adapter',str(adapter)]
  r=subprocess.run(cmd,cwd=unrelated,text=True,capture_output=True);assert r.returncode==0,(r.stdout,r.stderr)
  result=json.loads(r.stdout);manifest=pathlib.Path(result['manifest']);value=json.loads(manifest.read_text());assert manifest.parent==out
  assert value['schemaVersion']=='3.0.0' and value['workingDirectoryIndependent'] is True and value['authorityServiceExternal'] is True and value['authorityServiceExecutableStaged'] is False and value['authorityBrokerStaged'] is False and value['rawAuthoritySecretsIncluded'] is False and value['p2DelegationOnly'] is True and value['restrictedWorkerLauncherExternal'] is True and value['restrictedWorkerLauncherOsEnforced'] is True
  resources=value['resources'];host_root=out/resources['automationHostRoot']['path'];assert resources['automationHostRoot']['treeSha256']==tree(host_root);assert value['identity']['p1AuthorityServiceContractSha256']==sha(contract);assert resources['restrictedWorkerLauncher']['kind']=='external-file' and pathlib.Path(resources['restrictedWorkerLauncher']['path']).resolve()==launcher.resolve() and resources['restrictedWorkerLauncher']['sha256']==sha(launcher);assert resources['restrictedWorkerPolicy']['sha256']==sha(worker_policy)
  for forbidden in ('p1-authority-crypto-broker.mjs','protectedAuthorityBroker.mjs','kristin_p1_authority_service','protectedKeyHandles.json'):
   assert not any(p.name==forbidden for p in out.rglob('*'))
  # Any attempt to place a broker in automation_host must fail.
  (project/'automation_host/src/p1-authority-crypto-broker.mjs').write_text("console.log('bad')\n")
  bad=subprocess.run(cmd,cwd=unrelated,text=True,capture_output=True);assert bad.returncode!=0
 print('P2 V63 application-owned delegation-only runtime contract: PASS');return 0
if __name__=='__main__':raise SystemExit(main())

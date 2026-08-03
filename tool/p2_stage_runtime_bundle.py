#!/usr/bin/env python3
"""Stage only the P2 worker runtime under an application-owned directory.

The separately installed P1A authority service is never copied into this
bundle. No key handles, broker executable, policy state, revocation database,
or owner-signing provider may be present in the staged tree.
"""
from __future__ import annotations
import argparse,hashlib,json,pathlib,re,shutil,stat
SKIP_PARTS={'.git','.dart_tool','build','__pycache__'}
FORBIDDEN_NAMES={
 'p1-authority-crypto-broker.mjs','protectedAuthorityBroker.mjs','protectedKeyHandles.json',
 'authority-key.pem','p1_authority_service','kristin_p1_authority_service','p1-authority-service.exe',
}
FORBIDDEN_PATH_PARTS={'control-plane','authority_service'}
FORBIDDEN_TEXT=re.compile(r'(BEGIN (?:RSA |EC |OPENSSH |)PRIVATE KEY|ipcKeyHex|grantKeyring|consumptionKeyring|messageBase64)',re.I)
def sha(path:pathlib.Path)->str:return hashlib.sha256(path.read_bytes()).hexdigest()
def tree_digest(root:pathlib.Path)->str:
 rows=[]
 for p in sorted(root.rglob('*'),key=lambda x:x.as_posix()):
  if p.is_symlink():raise SystemExit(f'runtime symlink rejected: {p}')
  if p.is_file():rows.append(f'{p.relative_to(root).as_posix()}\0{sha(p)}')
 return hashlib.sha256('\n'.join(rows).encode()).hexdigest()
def copy_file(src:pathlib.Path,dst:pathlib.Path,executable=False)->dict:
 src=src.resolve()
 if not src.is_file() or src.is_symlink():raise SystemExit(f'runtime input missing/symlinked: {src}')
 dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst);dst.chmod(0o755 if executable else 0o644)
 return {'kind':'file','path':dst.as_posix(),'sha256':sha(dst),'bytes':dst.stat().st_size,'executable':bool(executable)}
def relative(row,root):
 out=dict(row);out['path']=pathlib.Path(out['path']).relative_to(root).as_posix();return out
def reject_authority_surface(root:pathlib.Path):
 for p in root.rglob('*'):
  if not p.is_file():continue
  rel=p.relative_to(root)
  if p.name in FORBIDDEN_NAMES or any(part in FORBIDDEN_PATH_PARTS for part in rel.parts):raise SystemExit(f'P1 authority surface staged into P2 runtime: {rel}')
  if p.stat().st_size<=2*1024*1024:
   try:text=p.read_text(encoding='utf-8')
   except Exception:continue
   if FORBIDDEN_TEXT.search(text):raise SystemExit(f'authority secret/broker marker staged: {rel}')
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--project',default='.');ap.add_argument('--destination',required=True);ap.add_argument('--node-executable',required=True);ap.add_argument('--source-commit',required=True);ap.add_argument('--source-tree',required=True);ap.add_argument('--provisioning-json',required=True);ap.add_argument('--restricted-worker-launcher',required=True);ap.add_argument('--restricted-worker-policy',required=True);ap.add_argument('--windows-job-helper');ap.add_argument('--posix-watchdog');ap.add_argument('--interactive-desktop-adapter');ap.add_argument('--include-node-modules',action='store_true');ns=ap.parse_args()
 root=pathlib.Path(ns.project).resolve();out=pathlib.Path(ns.destination).resolve()
 if re.fullmatch(r'[0-9a-f]{40}',ns.source_commit) is None or re.fullmatch(r'[0-9a-f]{40}',ns.source_tree) is None:raise SystemExit('exact source commit/tree required')
 if out==root or root in out.parents:raise SystemExit('runtime destination must be outside governed source')
 if out.exists():shutil.rmtree(out)
 out.mkdir(parents=True,mode=0o755);resources={}
 node=pathlib.Path(ns.node_executable).resolve();resources['nodeExecutable']=relative(copy_file(node,out/'node'/node.name,True),out)
 launcher=pathlib.Path(ns.restricted_worker_launcher).resolve()
 if not launcher.is_file() or launcher.is_symlink():raise SystemExit(f'external restricted worker launcher missing/symlinked: {launcher}')
 launcher_sha=sha(launcher)
 resources['restrictedWorkerLauncher']={'kind':'external-file','path':launcher.as_posix(),'sha256':launcher_sha,'bytes':launcher.stat().st_size,'executable':True,'osEnforcedIdentityTransition':True}
 policy=pathlib.Path(ns.restricted_worker_policy).resolve();resources['restrictedWorkerPolicy']=relative(copy_file(policy,out/'provisioning'/'worker-policy.v2.json'),out)
 policy_value=json.loads((out/resources['restrictedWorkerPolicy']['path']).read_text(encoding='utf-8'))
 if policy_value.get('schemaVersion')!='2.0.0' or policy_value.get('platform') not in ('windows','macos','linux'):raise SystemExit('restricted worker policy identity invalid')
 source_host=root/'automation_host';host_root=out/'automation_host'
 if not source_host.is_dir():raise SystemExit('automation_host source missing')
 for src in sorted(source_host.rglob('*'),key=lambda x:x.as_posix()):
  rel=src.relative_to(source_host)
  if any(part in SKIP_PARTS for part in rel.parts) or ('node_modules' in rel.parts and not ns.include_node_modules):continue
  if src.is_symlink():raise SystemExit(f'automation-host symlink rejected: {src}')
  if src.is_file():copy_file(src,host_root/rel,bool(src.stat().st_mode&stat.S_IXUSR))
 reject_authority_surface(host_root)
 host=host_root/'src/host.mjs'
 if not host.is_file():raise SystemExit('required runtime host script missing')
 resources['automationHost']={'kind':'file','path':host.relative_to(out).as_posix(),'sha256':sha(host),'bytes':host.stat().st_size,'executable':False}
 resources['automationHostRoot']={'kind':'directory','path':host_root.relative_to(out).as_posix(),'treeSha256':tree_digest(host_root)}
 staged_node=(out/resources['nodeExecutable']['path']).resolve();staged_launcher=launcher;staged_host=host.resolve();staged_cwd=host_root.resolve()
 if pathlib.Path(policy_value.get('nodeExecutable','')).resolve()!=staged_node or policy_value.get('nodeSha256')!=resources['nodeExecutable']['sha256']:raise SystemExit('restricted worker policy node binding invalid')
 if pathlib.Path(policy_value.get('hostScript','')).resolve()!=staged_host or policy_value.get('hostScriptSha256')!=resources['automationHost']['sha256']:raise SystemExit('restricted worker policy host binding invalid')
 if pathlib.Path(policy_value.get('workingDirectory','')).resolve()!=staged_cwd:raise SystemExit('restricted worker policy cwd binding invalid')
 if pathlib.Path(str(policy_value.get('launcherPath',''))).resolve()!=staged_launcher or policy_value.get('launcherSha256')!=resources['restrictedWorkerLauncher']['sha256'] or not policy_value.get('authorityAddress'):raise SystemExit('restricted worker policy launcher/authority binding invalid')
 if policy_value.get('sourceCommit')!=ns.source_commit or policy_value.get('sourceTree')!=ns.source_tree or re.fullmatch(r'[0-9a-f]{64}',str(policy_value.get('packageSha256',''))) is None:raise SystemExit('restricted worker policy source/package binding invalid')
 for key,value in [('windowsJobHelper',ns.windows_job_helper),('posixWatchdog',ns.posix_watchdog),('interactiveDesktopAdapter',ns.interactive_desktop_adapter)]:
  if value:
   src=pathlib.Path(value).resolve();resources[key]=relative(copy_file(src,out/'native'/key/src.name,True),out)
 provisioning_src=pathlib.Path(ns.provisioning_json).resolve();provisioning=json.loads(provisioning_src.read_text(encoding='utf-8'))
 if provisioning.get('schemaVersion')!='1.0.0' or provisioning.get('provisioningType')!='kristin-p2-application-runtime-environment-v1' or provisioning.get('containsSecrets') is not False or not isinstance(provisioning.get('environment'),dict) or not provisioning['environment']:raise SystemExit('runtime provisioning JSON invalid')
 secret_name=re.compile(r'(secret|token|password|credential|api.?key|private.?key|seed|key.?handle|broker)',re.I)
 for key,value in provisioning['environment'].items():
  if not isinstance(key,str) or not isinstance(value,str) or not value or '\0' in value or secret_name.search(key):raise SystemExit(f'runtime provisioning entry invalid: {key!r}')
 resources['runtimeProvisioning']=relative(copy_file(provisioning_src,out/'provisioning/environment.v1.json'),out)
 contract=root/'lib/product/p1_authority_service_contract_v1.dart'
 if not contract.is_file():raise SystemExit('merged P1A authority service contract missing')
 contract_sha=sha(contract)
 build_rows=[f'{k}\0{json.dumps(v,sort_keys=True,separators=(",",":"))}' for k,v in sorted(resources.items())]
 runtime_build=hashlib.sha256(('\n'.join(build_rows)+'\n'+ns.source_commit+'\n'+ns.source_tree+'\n'+contract_sha).encode()).hexdigest()
 manifest={'schemaVersion':'3.0.0','bundleType':'kristin-p2-application-runtime-v3','identity':{'sourceCommit':ns.source_commit,'sourceTree':ns.source_tree,'runtimeBuildSha256':runtime_build,'p1AuthorityServiceContractSha256':contract_sha},'resources':resources,'workingDirectoryIndependent':True,'currentWorkingDirectoryUsed':False,'authorityServiceExternal':True,'authorityServiceExecutableStaged':False,'authorityBrokerStaged':False,'rawAuthoritySecretsIncluded':False,'p2DelegationOnly':True,'restrictedWorkerLauncherExternal':True,'restrictedWorkerLauncherOsEnforced':True}
 path=out/'runtime-manifest.v3.json';path.write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n');path.chmod(0o644)
 print(json.dumps({'runtimeRoot':str(out),'manifest':str(path),'manifestSha256':sha(path),'runtimeBuildSha256':runtime_build,'p1AuthorityServiceContractSha256':contract_sha},indent=2,sort_keys=True));return 0
if __name__=='__main__':raise SystemExit(main())

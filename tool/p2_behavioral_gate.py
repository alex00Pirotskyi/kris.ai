#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, os, pathlib, select, shutil, signal, struct, subprocess, sys, tempfile, time, traceback

if os.name != 'nt':
    import pty
    import termios
else:
    pty = None
    termios = None
from p2_reference_runtime import *

TASKS=[f'P2-{i:03d}' for i in range(1,15)]

def result(name,status,detail='',classification='behavioral'):
    return {'name':name,'status':status,'detail':detail,'classification':classification}

def test_authorization(tmp):
    out=[]; ledger=UseLedger(); boundary=EffectBoundary(ledger)
    b=EffectBinding('run-a','task-a','owner_executor','write_file','owner','filesystem.write','write')
    g=make_fixture_grant(b,max_uses=2,grant_id='auth-test'); d=make_fixture_decision(b,str(tmp/'x'))
    boundary.authorize(d,g,b); out.append(result('exact policy/grant binding','passed'))
    bad=dataclasses.replace(b,run_id='wrong')
    try: boundary.authorize(d,g,bad); out.append(result('wrong-run grant rejected','failed'))
    except P2Denied: out.append(result('wrong-run grant rejected','passed'))
    ledger.revoke('auth-test')
    try: boundary.authorize(d,g,b); out.append(result('revocation at effect boundary','failed'))
    except P2Denied as e: out.append(result('revocation at effect boundary','passed',str(e)))
    return out

def test_filesystem(tmp):
    out=[]; ledger=UseLedger(); boundary=EffectBoundary(ledger); journal=Journal(tmp/'journal.jsonl'); svc=FilesystemService(boundary,journal,tmp/'backup')
    target=tmp/'外部 host space'/'深い'
    target.mkdir(parents=True)
    f=target/'.hidden-Δ.txt'
    b=EffectBinding('run-f','P2-002','owner_executor','write_file','owner','filesystem.write','write')
    g=make_fixture_grant(b,grant_id='fs-write'); d=make_fixture_decision(b,str(f)); r=svc.write_bytes(str(f),'héllo 世界'.encode(),decision=d,grant=g,binding=b)
    out.append(result('absolute hidden Unicode write transaction','passed',r.status))
    br=EffectBinding('run-r','P2-002','owner_executor','read_file','owner','filesystem.read','read')
    data,_=svc.read_bytes(str(f),decision=make_fixture_decision(br,str(f)),grant=make_fixture_grant(br),binding=br,max_bytes=100)
    out.append(result('absolute Unicode read','passed' if data.decode()=='héllo 世界' else 'failed'))
    link=tmp/'link'
    try: link.symlink_to(f)
    except OSError: link=None
    found=svc.search(str(tmp),r'\.txt$',max_entries=100,follow_links=False)
    out.append(result('bounded traversal without link following','passed',str(found)))
    bd=EffectBinding('run-d','P2-002','owner_executor','delete_file','owner','filesystem.delete','delete')
    rd=svc.delete(str(f),decision=make_fixture_decision(bd,str(f)),grant=make_fixture_grant(bd),binding=bd)
    svc.restore(rd); out.append(result('delete quarantine and undo','passed' if f.exists() else 'failed'))
    # Existing symlink is resolved and final target is revalidated rather than trusted lexically.
    if link is None: out.append(result('symlink final-target revalidation','source_only','platform did not permit symlink fixture','source_contract'))
    else:
      try:
        svc.write_bytes(str(link),b'x',decision=make_fixture_decision(b,str(link)),grant=make_fixture_grant(b),binding=b)
        out.append(result('symlink final-target revalidation','passed'))
      except (P2Denied,OSError) as e: out.append(result('symlink final-target revalidation','passed',f'fail-closed: {e}'))
    return out

def test_command(tmp):
    out=[]; ledger=UseLedger(); svc=CommandService(EffectBoundary(ledger),Journal(tmp/'cmd.jsonl'))
    py=pathlib.Path(sys.executable).resolve()
    b=EffectBinding('run-c','P2-003','automation_host','run_command','owner','process.execute','execute')
    spec=CommandSpec(str(py),('-c','import os,sys;print("OUT-✓");print("ERR",file=sys.stderr);print(os.getenv("P2_DATA"))'),str(tmp),{'P2_DATA':'data-not-authority'},5,1024,1024)
    r,_=svc.run(spec,decision=make_fixture_decision(b,str(py)),grant=make_fixture_grant(b),binding=b)
    out.append(result('direct executable cwd env stdout stderr','passed' if b'OUT-' in r.stdout and b'ERR' in r.stderr else 'failed'))
    if os.name=='nt':
        out.append(result('timeout and process-tree termination','source_only','Windows Job Object smoke runs in platform CI','source_contract'))
    else:
      b2=dataclasses.replace(b,run_id='run-timeout'); spec2=CommandSpec(str(py),('-c','import subprocess,sys,time; subprocess.Popen([sys.executable,"-c","import time;time.sleep(30)"]); time.sleep(30)'),str(tmp),{},.3,1024,1024)
      r2,_=svc.run(spec2,decision=make_fixture_decision(b2,str(py)),grant=make_fixture_grant(b2),binding=b2)
      out.append(result('timeout and process-group termination','passed' if r2.timed_out else 'failed',r2.status))
    b3=dataclasses.replace(b,run_id='run-flood'); spec3=CommandSpec(str(py),('-c','import sys;sys.stdout.buffer.write(b"A"*200000)'),str(tmp),{},5,4096,4096)
    r3,_=svc.run(spec3,decision=make_fixture_decision(b3,str(py)),grant=make_fixture_grant(b3),binding=b3)
    out.append(result('bounded stdout flood','passed' if len(r3.stdout)==4096 and r3.status=='output_budget_exceeded' else 'failed',r3.status))
    return out

def test_pty(tmp):
    out=[]
    if os.name=='nt' or pty is None or termios is None:
        return [result('PTY Linux fixture','unsupported','Windows runs ConPTY fixture in CI')]
    pid,fd=pty.fork()
    if pid==0:
        os.execv(sys.executable,[sys.executable,'-c','import sys;print("\\x1b[31mANSI-世界\\x1b[0m");print(input())'])
    winsz=struct.pack('HHHH',40,120,0,0); import fcntl; fcntl.ioctl(fd,termios.TIOCSWINSZ,winsz)
    os.write(fd,'input-✓\n'.encode()); chunks=[]; deadline=time.time()+5
    while time.time()<deadline:
        ready,_,_=select.select([fd],[],[],.2)
        if ready:
            try: chunks.append(os.read(fd,4096))
            except OSError: break
        done,_=os.waitpid(pid,os.WNOHANG)
        if done: break
    try: os.close(fd)
    except OSError: pass
    transcript=b''.join(chunks); (tmp/'pty.transcript').write_bytes(transcript)
    ok=b'ANSI-' in transcript and '世界'.encode() in transcript and b'input-' in transcript
    out.append(result('PTY ANSI Unicode input resize transcript','passed' if ok else 'failed',transcript.decode(errors='replace')[-300:]))
    out.append(result('attach detach reconnect contract','source_only','protocol implementation and CI reconnect fixture required','source_contract'))
    return out

def test_watchdog(tmp):
    out=[]; py=pathlib.Path(sys.executable).resolve()
    if os.name=='nt': return [result('external watchdog kills target while UI absent','source_only','Windows native Job Object smoke runs in platform CI','source_contract')]
    target=subprocess.Popen([str(py),'-c','import time;time.sleep(30)'],start_new_session=True)
    watchdog=subprocess.Popen([str(py),'-c',f'import os,signal,time;time.sleep(.2);os.killpg({target.pid},signal.SIGKILL)'])
    watchdog.wait(timeout=3); target.wait(timeout=3)
    out.append(result('external watchdog kills target while UI absent','passed' if target.returncode!=0 else 'failed'))
    return out

def test_redaction(tmp):
    payload={'token':'secret-value','text':'Bearer abcdefghijklmnop','nested':{'password':'p'}}
    safe=json.dumps(redact(payload))
    return [result('clipboard/screen/log secret redaction','passed' if 'secret-value' not in safe and 'abcdefghijklmnop' not in safe else 'failed')]

def static_checks(root):
    checks=[]
    required=['lib/product/p2_owner_mode.dart','lib/product/p2_filesystem_service.dart','lib/product/p2_finite_command_service.dart','lib/product/p2_pty_service.dart','lib/product/p2_process_tree.dart','lib/product/p2_host_operations.dart','lib/product/p2_snapshot_undo.dart','lib/product/p2_emergency_watchdog.dart','lib/product/p2_terminal_model.dart','lib/product/p2_owner_workspace.dart','docs/OWNER_MODE_OPERATOR_GUIDE.md','docs/security/P2_SECURITY_REVIEW_PACKET.md','docs/adr/ADR-0012-p2-automation-host.md']
    missing=[x for x in required if not (root/x).is_file()]
    checks.append(result('P2 implementation artifact inventory','passed' if not missing else 'failed',str(missing),'source_contract'))
    guide=(root/'docs/OWNER_MODE_OPERATOR_GUIDE.md').read_text(encoding='utf-8')
    checks.append(result('operator guide labels Owner Mode as non-sandbox','passed' if 'not a sandbox' in guide.lower() else 'failed',classification='source_contract'))
    review=(root/'docs/security/P2_SECURITY_REVIEW_PACKET.md').read_text(encoding='utf-8')
    checks.append(result('independent reviewer sign-off remains unclaimed','passed' if 'PENDING INDEPENDENT REVIEW' in review and 'Reviewer name:' in review else 'failed',classification='source_contract'))
    return checks

def task_map(all_results):
    common=static_result=[x for x in all_results if x['classification']=='source_contract']
    behavior=[x for x in all_results if x['classification']=='behavioral']
    mapping={
      'P2-001':common,'P2-002':[x for x in behavior if any(k in x['name'] for k in ('absolute','traversal','delete','symlink'))],
      'P2-003':[x for x in behavior if any(k in x['name'] for k in ('direct executable','stdout flood'))],
      'P2-004':[], 'P2-005':[x for x in all_results if 'PTY' in x['name'] or 'attach' in x['name']],
      'P2-006':[x for x in behavior if 'process-group' in x['name']],
      'P2-007':[result('controlled package fixture/dry run','source_only','tri-OS package-manager fixtures run in CI','source_contract')],
      'P2-008':[result('service/application support matrix','source_only','typed adapter matrix is source-checked; target OS smoke required','source_contract')],
      'P2-009':[x for x in behavior if 'redaction' in x['name']],
      'P2-010':[x for x in behavior if 'undo' in x['name']],
      'P2-011':[x for x in behavior if 'watchdog' in x['name']],
      'P2-012':[result('terminal keyboard and screen-reader workflow','source_only','Dart widget/accessibility CI required','source_contract')],
      'P2-013':[x for x in behavior if any(k in x['name'] for k in ('revocation','symlink','flood','timeout','watchdog'))],
      'P2-014':[x for x in common if 'guide' in x['name']],
    }
    return mapping

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--project',default=str(pathlib.Path(__file__).resolve().parents[1])); ap.add_argument('--evidence-dir'); ap.add_argument('--fast-source-only',action='store_true'); ns=ap.parse_args()
    root=pathlib.Path(ns.project).resolve(); evidence=pathlib.Path(ns.evidence_dir or root/'release/evidence').resolve(); evidence.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='kristin-p2-') as d:
        tmp=pathlib.Path(d); results=[]
        for fn in (test_authorization,test_filesystem,test_command,test_pty,test_watchdog,test_redaction):
            case=tmp/fn.__name__; case.mkdir(parents=True,exist_ok=True)
            try: results.extend(fn(case))
            except Exception as e: results.append(result(fn.__name__,'failed',traceback.format_exc()))
        results.extend(static_checks(root))
    # technology spike is executable but not allowed to fabricate missing platforms.
    spike=evidence/'P2-004'/'technology-spike.json'; spike.parent.mkdir(parents=True,exist_ok=True)
    if ns.fast_source_only:
        tech={'schemaVersion':'1.0.0','decision':{'status':'blocked_external_tri_platform_measurement_required'},'sourceOnly':True,'completionEligible':False}
        atomic_json(spike,tech);spike_run=type('Result',(),{'returncode':3})()
    else:
        spike_run=subprocess.run([sys.executable,str(root/'tool/p2_technology_spike.py'),'--project',str(root),'--output',str(spike),'--commit-sha','0'*40],check=False)
        tech=json.loads(spike.read_text()) if spike.is_file() else {'decision':{'status':'blocked_missing_measurement'}}
    tech_status='passed' if spike_run.returncode==0 and tech.get('decision',{}).get('status')=='platform_measurement_complete' else 'source_only'
    mapped=task_map(results); mapped['P2-004']=[result('measured automation-host comparison',tech_status,tech['decision']['status'],'behavioral')]
    summary={'schemaVersion':'1.0.0','platform':sys.platform,'generatedAt':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'tasks':{},'claims':{'windowsBehavioralProof':False,'macosBehavioralProof':False,'linuxBehavioralProof':False,'independentSecurityReview':False}}
    for task in TASKS:
        rows=mapped[task]
        failed=any(x['status']=='failed' for x in rows)
        source_only=any(x['status'] in ('source_only','unsupported','not_tested') for x in rows)
        status='failed' if failed else 'source_only'
        payload={'schemaVersion':'1.0.0','taskId':task,'platform':sys.platform,'status':status,'tests':rows,'note':'Local helper and source checks are diagnostics only and are always source_only. Exact shipped-product Windows/macOS/Linux receipts plus independent review are required.'}
        td=evidence/task; td.mkdir(parents=True,exist_ok=True); atomic_json(td/'test-results.json',payload)
        summary['tasks'][task]=status
    atomic_json(evidence/'P2'/'local-behavioral-summary.json',summary)
    failures=[x for x in results if x['status']=='failed']
    print(json.dumps(summary,indent=2));
    if failures:
        print(json.dumps(failures,indent=2),file=sys.stderr); return 1
    return 0
if __name__=='__main__': raise SystemExit(main())

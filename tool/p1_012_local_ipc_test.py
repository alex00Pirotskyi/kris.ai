#!/usr/bin/env python3
from __future__ import annotations
import argparse,importlib.util,json,sys
from datetime import datetime,timezone,timedelta
from pathlib import Path
def load(path):
 spec=importlib.util.spec_from_file_location('ipc',path); m=importlib.util.module_from_spec(spec); sys.modules['ipc']=m; spec.loader.exec_module(m); return m
def main():
 p=argparse.ArgumentParser(); p.add_argument('--project',default='.'); p.add_argument('--json-output'); a=p.parse_args(); root=Path(a.project).resolve(); results=[]
 def add(n,o,d): results.append({"name":n,"passed":bool(o),"detail":d})
 m=load(root/'tool/local_authenticated_ipc.py'); key=b'kristin-p1-ipc-test-key-32-byte!!'[:32]; auth=m.LocalIpcAuthenticator({'desktop-host':key}); server,thread=m.run_loopback_server(auth)
 try:
  address=server.server_address; deadline=(datetime.now(timezone.utc)+timedelta(minutes=2)).isoformat().replace('+00:00','Z')
  good={'schemaVersion':'1.0.0','peerId':'desktop-host','requestId':'req-1','deadline':deadline,'body':{'operation':'ping'}}; good['mac']=m.request_mac(key,good)
  response=m.send_loopback_request(address,good); accepted=response.get('body',{}).get('accepted') is True and m.request_mac(key,response)==response.get('mac'); add('Mutually authenticated loopback request',accepted,str(response))
  bad=dict(good); bad['requestId']='req-2'; bad['mac']='00'*32; rejected=m.send_loopback_request(address,bad).get('error')=='ipc_auth_failed'; add('Unrelated local process rejected',rejected,'invalid peer proof failed')
  replay=m.send_loopback_request(address,good).get('error')=='ipc_replay'; add('Replay rejected',replay,'request id consumed once')
 finally:
  server.shutdown(); server.server_close()
 config=json.loads((root/'config/local_ipc.v1.json').read_text()); add('Tri-platform transport contract',set(config.get('transports',{}))=={'windows','macos','linux'} and config.get('mutualAuthentication') is True,str(config.get('transports')))
 tasks={x['id']:x for x in json.loads((root/'docs/roadmap/roadmap.yaml').read_text())['tasks']}; add('Roadmap state',tasks.get('P1-012',{}).get('status')=='DONE',f"P1-012={tasks.get('P1-012',{}).get('status')}")
 passed=all(x['passed'] for x in results); report={"schemaVersion":"1.0.0","taskId":"P1-012","caseCount":len(results),"passedCount":sum(x['passed'] for x in results),"failedCount":sum(not x['passed'] for x in results),"passed":passed,"results":results}; text=json.dumps(report,indent=2,sort_keys=True)+'\n'
 if a.json_output: out=root/a.json_output; out.parent.mkdir(parents=True,exist_ok=True); out.write_text(text,encoding='utf-8',newline='\n')
 print(text,end=''); return 0 if passed else 1
if __name__=='__main__': raise SystemExit(main())

#!/usr/bin/env python3
"""V63 Linux production-worker denial source contract.

The real distinct-UID install/connect/keystore/restart/uninstall proof is executed
only by run_linux_behavioral.sh on the controlled authority-isolated runner.
This source contract is completion-ineligible and never emits a platform PASS.
"""
from __future__ import annotations
import argparse,json,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--service-binary',required=True);p.add_argument('--worker-launcher',required=True);a=p.parse_args()
service=pathlib.Path(a.service_binary).resolve();launcher=pathlib.Path(a.worker_launcher).resolve()
for path in (service,launcher):
 if not path.is_file():raise SystemExit(f'missing binary: {path}')
for binary in (service,launcher):
 run=subprocess.run([str(binary),'--source-self-test'],text=True,capture_output=True)
 if run.returncode:raise SystemExit(run.stderr or run.stdout)
result={'schemaVersion':'2.0.0','receiptType':'p1a-linux-worker-denial-source-contract-v2','platform':'linux','status':'source_only','completionEligible':False,'productionRestrictedLauncherRequired':True,'dedicatedWorkerUidRequired':True,'authoritySocketAclDenialRequired':True,'providerSigningDenialRequired':True,'restartReplayDenialRequired':True,'controlledBehavioralScript':'authority_service/tests/run_linux_behavioral.sh'}
print(json.dumps(result,indent=2,sort_keys=True))

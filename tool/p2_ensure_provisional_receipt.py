#!/usr/bin/env python3
from __future__ import annotations
import argparse,hashlib,json,pathlib
def sha(p):return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
def main():
 a=argparse.ArgumentParser();a.add_argument('--attestation-receipt',required=True);a.add_argument('--output',required=True);a.add_argument('--reason',default='behavior_failed_before_receipt');n=a.parse_args();out=pathlib.Path(n.output)
 if out.is_file():return 0
 ap=pathlib.Path(n.attestation_receipt);att=json.loads(ap.read_text());binding=att.get('exactBinding')
 if att.get('schemaVersion')!='5.0.0' or att.get('receiptType')!='p2-controlled-runner-attestation-receipt-v5' or not isinstance(binding,dict):raise SystemExit('valid V5 attestation required')
 row={'schemaVersion':'5.0.0','receiptType':'p2-task-platform-provisional-v5','status':'provisional_blocked','completionEligible':False,'sourceOnly':False,'postRunCleanupRequired':True,'postRunCleanupObserved':False,'exactBinding':binding,'runnerAttestationSha256':sha(ap),'runnerAttestation':{'path':str(ap.resolve()),'sha256':sha(ap),'workerCannotAccessAuthorityService':att.get('workerCannotAccessAuthorityService'),'p2ReceivesAuthoritySecrets':att.get('p2ReceivesAuthoritySecrets')},'p1AuthorityService':att.get('p1AuthorityService'),'taskAssertions':{},'reason':n.reason}
 out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(row,indent=2,sort_keys=True)+'\n');return 0
if __name__=='__main__':raise SystemExit(main())

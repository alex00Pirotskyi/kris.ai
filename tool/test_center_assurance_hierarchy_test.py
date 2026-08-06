#!/usr/bin/env python3
from __future__ import annotations
import copy, sys, tempfile, unittest
from pathlib import Path
HERE=Path(__file__).resolve().parent; PROJECT=HERE.parent; sys.path.insert(0,str(HERE))
import test_center_assurance_hierarchy as H  # noqa:E402
F=Path('release/evidence/TEST_CENTER/P8-001/fixtures/assurance-execution-report.pass.json')

def at(v,p):
    for k in p: v=v[k]
    return v
def put(p,x):
    def m(v): at(v,p[:-1])[p[-1]]=x
    return m
def pop(p):
    def m(v): at(v,p[:-1]).pop(p[-1])
    return m
def dup(p):
    def m(v): a=at(v,p); a.append(copy.deepcopy(a[0]))
    return m
def pending(t,**u):
    def m(v): next(x for x in v['pendingMigrationBindings'] if x['testId']==t).update(u)
    return m
def both(*ms):
    return lambda v:[m(v) for m in ms]

def extra(v):
    x=copy.deepcopy(v['pendingMigrationBindings'][0]); x['testId']='tc.p1a.review.outcome'; v['pendingMigrationBindings'].append(x)
def source(v):
    v['executionResult'].update(testId='tc.p8.formal-test-hierarchy',assuranceClass='source_contract')
    v['hierarchyBinding'].update(testId='tc.p8.formal-test-hierarchy',levelId='architecture_lint',sourceOnly=True)
    v.update(assuranceLevel='architecture_lint',requestedSupportImpact='SOURCE_FOUNDATION')
def unknown(v):
    v['executionResult']['testId']=v['hierarchyBinding']['testId']='tc.unknown.actual-record'

DOC=[
('unknown level',put(('levels',1,'levelId'),'smoke')),('rank drift',put(('levels',2,'rank'),31)),
('invalid predecessor',put(('levels',2,'requiredPredecessorLevels'),['release'])),('missing binding',lambda v:v['testBindings'].pop()),
('duplicate binding',dup(('testBindings',))),('architecture promotion',put(('levels',0,'supportClaimCeiling'),'SOURCE_FOUNDATION')),
('release predecessors',put(('levels',7,'requiredPredecessorLevels'),['platform'])),('missing report schema',pop(('reportContract','executionReportSchema'))),
('missing migration',lambda v:v['pendingMigrationBindings'].pop()),('duplicate migration',dup(('pendingMigrationBindings',))),
('active overlap',put(('pendingMigrationBindings',0,'testId'),'tc.test-center.contracts')),
('Worker A identity drift',put(('pendingMigrationSource','commit'),'0'*40)),
('Worker A level drift',pending('tc.p2.behavioral-closure',levelId='integration')),
('p1a exit gate platform',pending('tc.p1a.exit-gate',levelId='platform')),('unreviewed Worker A ID',extra)]
REP=[
('missing assuranceLevel',pop(('assuranceLevel',))),('unknown assuranceLevel',put(('assuranceLevel',),'smoke')),
('level binding mismatch',both(put(('assuranceLevel',),'component'),put(('hierarchyBinding','levelId'),'component'))),
('wrapper mismatch',put(('hierarchyBinding','testId'),'tc.p8.formal-test-hierarchy')),
('class mismatch',put(('executionResult','assuranceClass'),'platform')),('cross candidate',put(('candidateCommit',),'3'*40)),
('above ceiling',put(('requestedSupportImpact',),'BEHAVIOR_SUPPORTED')),('unexecuted',put(('executionResult','resultState'),'SKIPPED')),
('non pass',put(('executionResult','resultState'),'FAIL')),('missing canonical field',pop(('executionResult','runner'))),
('canonical extra field',put(('executionResult','assuranceLevel'),'unit')),('wrapper extra field',put(('supportPromotion',),True)),
('source promotion',source),('unknown test',unknown)]

class T(unittest.TestCase):
    def setUp(self):
        self.hs=H.load(PROJECT/H.HIERARCHY_SCHEMA); self.rs=H.load(PROJECT/H.REPORT_SCHEMA); self.cs=H.load(PROJECT/H.CANONICAL_SCHEMA)
        self.h=H.load(PROJECT/H.HIERARCHY); self.r=H.load(PROJECT/H.REGISTRY); self.a=H.load(PROJECT/F)
    def docs(self,v): return H.validate_documents(self.hs,self.rs,v,self.r)
    def report(self,v): return H.validate_assurance_execution_report(v,report_schema=self.rs,canonical_schema=self.cs,hierarchy=self.h,registry=self.r)
    def test_32_deterministic_regressions(self):
        self.assertEqual(H.validate_project(PROJECT)['pendingMigrationBindingCount'],11); self.assertEqual(self.report(self.a)['assuranceLevel'],'unit')
        for name,mut in DOC:
            with self.subTest(name=name),self.assertRaises(H.HierarchyError): v=copy.deepcopy(self.h); mut(v); self.docs(v)
        for name,mut in REP:
            with self.subTest(name=name),self.assertRaises(H.HierarchyError): v=copy.deepcopy(self.a); mut(v); self.report(v)
        with tempfile.TemporaryDirectory() as d,self.assertRaises(H.HierarchyError): H.write_report(Path(d),Path('../outside.json'),H.validate_project(PROJECT))

if __name__=='__main__': unittest.main(verbosity=2)

#!/usr/bin/env python3
"""Verify P3 dependency snapshot commits are bound to their declared Git trees."""
from __future__ import annotations
import argparse,json,re,subprocess
from pathlib import Path
from typing import Any
DOCUMENT_PATH="release/evidence/P3-001/dependency-status.json"
GIT_OBJECT_RE=re.compile(r"^[0-9a-f]{40}$")
def _require_object(value:object,label:str,errors:list[str])->dict[str,Any]|None:
    if not isinstance(value,dict): errors.append(f"{label} must be an object"); return None
    return value
def _binding(record:object,label:str,errors:list[str],*,commit_key:str="commit",tree_key:str="tree")->tuple[str,str,str]|None:
    obj=_require_object(record,label,errors)
    if obj is None:return None
    commit=obj.get(commit_key); tree=obj.get(tree_key)
    if not isinstance(commit,str) or GIT_OBJECT_RE.fullmatch(commit) is None: errors.append(f"{label}.{commit_key} must be a 40-character lowercase Git object id"); return None
    if not isinstance(tree,str) or GIT_OBJECT_RE.fullmatch(tree) is None: errors.append(f"{label}.{tree_key} must be a 40-character lowercase Git object id"); return None
    return label,commit,tree
def collect_bindings(document:dict[str,Any],errors:list[str])->list[tuple[str,str,str]]:
    bindings=[]; dependencies=document.get("dependencies")
    if not isinstance(dependencies,list): errors.append("dependencies must be an array")
    else:
        seen=set()
        for index,dependency in enumerate(dependencies):
            label=f"dependencies[{index}]"; obj=_require_object(dependency,label,errors)
            if obj is None: continue
            task_id=obj.get("taskId")
            if not isinstance(task_id,str) or not task_id: errors.append(f"{label}.taskId must be non-empty"); continue
            if task_id in seen: errors.append(f"duplicate dependency taskId {task_id}"); continue
            seen.add(task_id); item=_binding(obj.get("implementation"),f"dependency {task_id} implementation",errors)
            if item is not None: bindings.append(item)
    repository=_require_object(document.get("repository"),"repository",errors)
    if repository is not None:
        for key in ("protectedMain","workerADependencyCandidate","workerBBranchCreationBase","workerBSynchronizedBase","workerC","workerJ"):
            item=_binding(repository.get(key),f"repository.{key}",errors)
            if item is not None: bindings.append(item)
        item=_binding(repository.get("workerD"),"repository.workerD",errors,commit_key="synchronizationCommit",tree_key="synchronizationTree")
        if item is not None: bindings.append(item)
    return bindings
def _git(root:Path,*args:str)->str:
    return subprocess.run(["git",*args],cwd=root,check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True).stdout.strip()
def validate_document(root:Path,document:dict[str,Any])->list[str]:
    errors=[]; bindings=collect_bindings(document,errors)
    if not bindings: errors.append("dependency document contains no Git bindings"); return errors
    for label,commit,declared_tree in bindings:
        try:
            resolved_commit=_git(root,"rev-parse","--verify",f"{commit}^{{commit}}"); actual_tree=_git(root,"rev-parse","--verify",f"{commit}^{{tree}}")
        except (OSError,subprocess.CalledProcessError): errors.append(f"{label} commit does not resolve in repository: {commit}"); continue
        if resolved_commit!=commit: errors.append(f"{label} does not resolve to the declared commit {commit}")
        if actual_tree!=declared_tree: errors.append(f"{label} tree mismatch: declared {declared_tree}, actual {actual_tree}")
    return errors
def validate(root:Path)->list[str]:
    path=root/DOCUMENT_PATH
    if path.is_symlink() or not path.is_file(): return [f"missing dependency document {DOCUMENT_PATH}"]
    try: document=json.loads(path.read_text(encoding="utf-8"))
    except (OSError,UnicodeError,json.JSONDecodeError) as error: return [f"dependency document is unreadable: {error}"]
    if not isinstance(document,dict): return ["dependency document must be an object"]
    return validate_document(root,document)
def main()->None:
    parser=argparse.ArgumentParser(); parser.add_argument("--check",action="store_true"); parser.add_argument("--project",default="."); args=parser.parse_args()
    if not args.check: raise SystemExit("--check is required; validator is non-mutating")
    errors=validate(Path(args.project).resolve())
    if errors: print("\n".join(f"FAIL {error}" for error in errors)); raise SystemExit(1)
    print("Worker D P3 dependency Git bindings: PASS")
if __name__=="__main__": main()

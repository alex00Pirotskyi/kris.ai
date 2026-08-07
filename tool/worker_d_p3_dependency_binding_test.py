from __future__ import annotations
import copy,importlib.util,json,unittest
from pathlib import Path
MODULE_PATH=Path(__file__).with_name("worker_d_p3_dependency_binding.py")
SPEC=importlib.util.spec_from_file_location("worker_d_p3_dependency_binding",MODULE_PATH);MODULE=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(MODULE)
ROOT=Path(__file__).resolve().parents[1]
def dependency_document()->dict:return json.loads((ROOT/MODULE.DOCUMENT_PATH).read_text(encoding="utf-8"))
class DependencyBindingTests(unittest.TestCase):
    def test_repository_bindings_pass(self):self.assertEqual([],MODULE.validate(ROOT))
    def test_nonexistent_commit_fails(self):
        mutated=copy.deepcopy(dependency_document());mutated["dependencies"][0]["implementation"]["commit"]="f"*40
        self.assertTrue(any("commit does not resolve" in e for e in MODULE.validate_document(ROOT,mutated)))
    def test_commit_tree_mismatch_fails(self):
        doc=dependency_document();mutated=copy.deepcopy(doc);mutated["dependencies"][0]["implementation"]["tree"]=doc["dependencies"][1]["implementation"]["tree"]
        self.assertTrue(any("tree mismatch" in e for e in MODULE.validate_document(ROOT,mutated)))
    def test_malformed_git_identity_fails(self):
        mutated=copy.deepcopy(dependency_document());mutated["repository"]["protectedMain"]["commit"]="not-a-git-object"
        self.assertTrue(any("repository.protectedMain.commit must be a 40-character" in e for e in MODULE.validate_document(ROOT,mutated)))
    def test_worker_d_synchronization_pair_is_checked(self):
        mutated=copy.deepcopy(dependency_document());mutated["repository"]["workerD"]["synchronizationTree"]="0"*40
        self.assertTrue(any("repository.workerD tree mismatch" in e for e in MODULE.validate_document(ROOT,mutated)))
    def test_duplicate_dependency_task_fails(self):
        mutated=copy.deepcopy(dependency_document());mutated["dependencies"].append(copy.deepcopy(mutated["dependencies"][0]))
        self.assertTrue(any("duplicate dependency taskId" in e for e in MODULE.validate_document(ROOT,mutated)))
if __name__=="__main__":unittest.main()

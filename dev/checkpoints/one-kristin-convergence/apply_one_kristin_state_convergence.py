#!/usr/bin/env python3
"""Apply the next One-Kristin state-ownership slice to an exact kris.ai checkout.

This script deliberately does not run git add/commit/push and does not edit
SOURCE_MANIFEST.sha256. It only transforms three source/test files after strict
context guards pass.
"""
from __future__ import annotations

import argparse
import difflib
import os
from pathlib import Path
import subprocess
import sys
import tempfile

BASE_HEAD = "dd2f46ba6df3fb25adc2c8c927e807147b8f16f2"
TARGETS = {
    "lib/product/kristin_conversation_session.dart": "session",
    "lib/product/chat_control_plane_studio.dart": "studio",
    "test/product/kristin_conversation_session_test.dart": "test",
}


class TransformError(RuntimeError):
    pass


def replace_count(text: str, old: str, new: str, *, label: str, expected: int = 1) -> str:
    count = text.count(old)
    if count != expected:
        raise TransformError(
            f"{label}: expected {expected} exact source match(es), found {count}. "
            "Refusing to patch a drifted checkout."
        )
    return text.replace(old, new)


def transform_session(text: str) -> str:
    text = replace_count(
        text,
        "import 'task_kernel/task_specification.dart';\n"
        "import 'task_kernel/universal_task_plan.dart';\n\n"
        "/// Who produced a visible message in the one Kristin conversation.\n",
        "import 'task_kernel/task_specification.dart';\n"
        "import 'task_kernel/task_understanding.dart';\n"
        "import 'task_kernel/universal_task_plan.dart';\n\n"
        "/// Which planning path produced the current canonical plan.\n"
        "enum ChatPlanningPath {\n"
        "  deterministic,\n"
        "  model,\n"
        "  fallback,\n"
        "}\n\n"
        "/// Who produced a visible message in the one Kristin conversation.\n",
        label="session import + ChatPlanningPath ownership",
    )

    text = replace_count(
        text,
        "  ChatInteractionDecision? _pendingDecision;\n"
        "  UnderstandingHistory? _understandingHistory;\n"
        "  TaskSpecification? _taskSpecification;\n",
        "  ChatInteractionDecision? _pendingDecision;\n"
        "  UnderstandingHistory? _understandingHistory;\n"
        "  UnderstandingPath _understandingPath = UnderstandingPath.deterministic;\n"
        "  List<String> _understandingRejections = const <String>[];\n"
        "  ChatPlanningPath _planningPath = ChatPlanningPath.deterministic;\n"
        "  ProjectProcessStatus? _projectProcessStatus;\n"
        "  String? _projectProcessProjectId;\n"
        "  TaskSpecification? _taskSpecification;\n",
        label="session canonical metadata fields",
    )

    text = replace_count(
        text,
        "  ChatInteractionDecision? get pendingDecision => _pendingDecision;\n"
        "  UnderstandingHistory? get understandingHistory => _understandingHistory;\n"
        "  TaskSpecification? get taskSpecification => _taskSpecification;\n",
        "  ChatInteractionDecision? get pendingDecision => _pendingDecision;\n"
        "  UnderstandingHistory? get understandingHistory => _understandingHistory;\n"
        "  UnderstandingPath get understandingPath => _understandingPath;\n"
        "  List<String> get understandingRejections =>\n"
        "      List<String>.unmodifiable(_understandingRejections);\n"
        "  ChatPlanningPath get planningPath => _planningPath;\n"
        "  ProjectProcessStatus? get projectProcessStatus =>\n"
        "      _projectProcessProjectId == _selectedProjectId\n"
        "          ? _projectProcessStatus\n"
        "          : null;\n"
        "  TaskSpecification? get taskSpecification => _taskSpecification;\n",
        label="session canonical metadata getters",
    )

    text = replace_count(
        text,
        "  void selectProject(String? projectId) {\n"
        "    _selectedProjectId = _normalizedOptional(projectId);\n"
        "  }\n",
        "  void selectProject(String? projectId) {\n"
        "    final normalized = _normalizedOptional(projectId);\n"
        "    if (_selectedProjectId == normalized) return;\n"
        "    _selectedProjectId = normalized;\n"
        "    // Project-process state is a projection of one selected project.\n"
        "    // Never let an async result from the previous project leak into\n"
        "    // the newly selected conversation context.\n"
        "    _projectProcessProjectId = null;\n"
        "    _projectProcessStatus = null;\n"
        "  }\n",
        label="project process invalidation",
    )

    text = replace_count(
        text,
        "    _pendingDecision = null;\n"
        "    _understandingHistory = null;\n"
        "    _taskSpecification = null;\n",
        "    _pendingDecision = null;\n"
        "    _understandingHistory = null;\n"
        "    _understandingPath = UnderstandingPath.deterministic;\n"
        "    _understandingRejections = const <String>[];\n"
        "    _taskSpecification = null;\n",
        label="turn understanding reset",
        expected=2,
    )

    text = replace_count(
        text,
        "    _lastReconciliation = null;\n"
        "    _prepared = null;\n",
        "    _lastReconciliation = null;\n"
        "    _planningPath = ChatPlanningPath.deterministic;\n"
        "    _prepared = null;\n",
        label="turn planning-path reset",
        expected=2,
    )

    text = replace_count(
        text,
        "  void setUnderstanding({\n"
        "    required ChatInteractionDecision decision,\n"
        "    required UnderstandingHistory history,\n"
        "    TaskSpecification? specification,\n"
        "  }) {\n"
        "    _pendingDecision = decision;\n"
        "    _understandingHistory = history;\n"
        "    _taskSpecification = specification;\n"
        "  }\n\n",
        "  void setPendingDecision(ChatInteractionDecision? decision) {\n"
        "    _pendingDecision = decision;\n"
        "  }\n\n"
        "  void setUnderstandingHistory(UnderstandingHistory? history) {\n"
        "    _understandingHistory = history;\n"
        "  }\n\n"
        "  void setUnderstandingMetadata({\n"
        "    required UnderstandingPath path,\n"
        "    required Iterable<String> rejections,\n"
        "  }) {\n"
        "    _understandingPath = path;\n"
        "    _understandingRejections = List<String>.unmodifiable(rejections);\n"
        "  }\n\n"
        "  void setUnderstanding({\n"
        "    required ChatInteractionDecision decision,\n"
        "    required UnderstandingHistory history,\n"
        "    TaskSpecification? specification,\n"
        "  }) {\n"
        "    _pendingDecision = decision;\n"
        "    _understandingHistory = history;\n"
        "    _taskSpecification = specification;\n"
        "  }\n\n",
        label="session understanding compatibility mutations",
    )

    text = replace_count(
        text,
        "  void setCompletedTasks(Iterable<CompletedTaskRecord> completed) {\n"
        "    _completedTasks = List<CompletedTaskRecord>.unmodifiable(completed);\n"
        "  }\n\n",
        "  void setPlanningFailure(PlanningFailure? failure) {\n"
        "    _planningFailure = failure;\n"
        "  }\n\n"
        "  void setLastReconciliation(PlanReconciliationResult? reconciliation) {\n"
        "    _lastReconciliation = reconciliation;\n"
        "  }\n\n"
        "  void setPlanningPath(ChatPlanningPath path) {\n"
        "    _planningPath = path;\n"
        "  }\n\n"
        "  void setActiveRequest(String request) {\n"
        "    _activeRequest = request.trim();\n"
        "  }\n\n"
        "  void setProjectProcessStatus({\n"
        "    required String projectId,\n"
        "    required ProjectProcessStatus? status,\n"
        "  }) {\n"
        "    final normalizedProjectId = _normalizedOptional(projectId);\n"
        "    if (normalizedProjectId == null ||\n"
        "        normalizedProjectId != _selectedProjectId) {\n"
        "      return;\n"
        "    }\n"
        "    _projectProcessProjectId = normalizedProjectId;\n"
        "    _projectProcessStatus = status;\n"
        "  }\n\n"
        "  void clearProjectProcessStatus() {\n"
        "    _projectProcessProjectId = null;\n"
        "    _projectProcessStatus = null;\n"
        "  }\n\n"
        "  void setCompletedTasks(Iterable<CompletedTaskRecord> completed) {\n"
        "    _completedTasks = List<CompletedTaskRecord>.unmodifiable(completed);\n"
        "  }\n\n",
        label="session planning/process compatibility mutations",
    )

    text = replace_count(
        text,
        "      _selectedProjectId = command.contract.projectId;\n"
        "      _selectedModelId = command.model.exactId;\n",
        "      selectProject(command.contract.projectId);\n"
        "      selectModel(command.model.exactId);\n",
        label="prepared command selected context",
    )

    text = replace_count(
        text,
        "    _selectedProjectId = run.command.contract.projectId;\n"
        "    _selectedModelId = run.command.model.exactId;\n",
        "    selectProject(run.command.contract.projectId);\n"
        "    selectModel(run.command.model.exactId);\n",
        label="durable run selected context",
    )
    return text


def transform_studio(text: str) -> str:
    enum_block = """/// Which planner actually produced the currently prepared command, so the
/// UI never implies a detailed model-authored decomposition exists when a
/// deterministic fallback was used instead.
///
/// Chat plans through [UniversalTaskKernel] now, so this records the
/// kernel outcome rather than which of two services was called.
enum ChatPlanningPath {
  /// No multi-task plan was generated: the request routed to direct
  /// conversation or a direct deterministic capability invocation.
  deterministic,

  /// A family planner produced a real, request-specific task graph.
  model,

  /// A KNOWN RECOVERABLE planning failure degraded to the deterministic
  /// conservative inspect/implement/verify envelope. Every other failure
  /// kind surfaces as a failure instead of arriving here -- see
  /// task_kernel/planning_failures.dart.
  fallback,
}

"""
    text = replace_count(text, enum_block, "", label="remove duplicate ChatPlanningPath enum")

    text = replace_count(
        text,
        "  ProjectProcessStatus? projectProcessStatus;\n",
        "  ProjectProcessStatus? get projectProcessStatus =>\n"
        "      conversationSession.projectProcessStatus;\n"
        "  set projectProcessStatus(ProjectProcessStatus? value) {\n"
        "    final projectId = selectedProjectId;\n"
        "    if (projectId == null) {\n"
        "      conversationSession.clearProjectProcessStatus();\n"
        "      return;\n"
        "    }\n"
        "    conversationSession.setProjectProcessStatus(\n"
        "      projectId: projectId,\n"
        "      status: value,\n"
        "    );\n"
        "  }\n",
        label="Studio project-process facade",
    )
    text = replace_count(
        text,
        "  ChatInteractionDecision? pendingDecision;\n",
        "  ChatInteractionDecision? get pendingDecision =>\n"
        "      conversationSession.pendingDecision;\n"
        "  set pendingDecision(ChatInteractionDecision? value) {\n"
        "    conversationSession.setPendingDecision(value);\n"
        "  }\n",
        label="Studio pending-decision facade",
    )
    text = replace_count(
        text,
        "  UnderstandingHistory? understandingHistory;\n",
        "  UnderstandingHistory? get understandingHistory =>\n"
        "      conversationSession.understandingHistory;\n"
        "  set understandingHistory(UnderstandingHistory? value) {\n"
        "    conversationSession.setUnderstandingHistory(value);\n"
        "  }\n",
        label="Studio understanding-history facade",
    )
    text = replace_count(
        text,
        "  PreparedCommand? prepared;\n",
        "  PreparedCommand? get prepared => conversationSession.prepared;\n"
        "  set prepared(PreparedCommand? value) {\n"
        "    final run = conversationSession.currentRun;\n"
        "    conversationSession.setPrepared(\n"
        "      value,\n"
        "      awaitingPermission: run != null\n"
        "          ? run.state == RunState.awaitingApproval\n"
        "          : (value?.contract.requiredPermissions.isNotEmpty ?? false),\n"
        "    );\n"
        "  }\n",
        label="Studio prepared-command facade",
    )
    text = replace_count(
        text,
        "  ChatPlanningPath planningPath = ChatPlanningPath.deterministic;\n",
        "  ChatPlanningPath get planningPath => conversationSession.planningPath;\n"
        "  set planningPath(ChatPlanningPath value) {\n"
        "    conversationSession.setPlanningPath(value);\n"
        "  }\n",
        label="Studio planning-path facade",
    )
    text = replace_count(
        text,
        "  TaskSpecification? taskSpecification;\n",
        "  TaskSpecification? get taskSpecification =>\n"
        "      conversationSession.taskSpecification;\n"
        "  set taskSpecification(TaskSpecification? value) {\n"
        "    conversationSession.setTaskSpecification(value);\n"
        "  }\n",
        label="Studio task-specification facade",
    )
    text = replace_count(
        text,
        "  UnderstandingPath understandingPath = UnderstandingPath.deterministic;\n",
        "  UnderstandingPath get understandingPath =>\n"
        "      conversationSession.understandingPath;\n"
        "  set understandingPath(UnderstandingPath value) {\n"
        "    conversationSession.setUnderstandingMetadata(\n"
        "      path: value,\n"
        "      rejections: conversationSession.understandingRejections,\n"
        "    );\n"
        "  }\n",
        label="Studio understanding-path facade",
    )
    text = replace_count(
        text,
        "  List<String> understandingRejections = const <String>[];\n",
        "  List<String> get understandingRejections =>\n"
        "      conversationSession.understandingRejections;\n"
        "  set understandingRejections(List<String> value) {\n"
        "    conversationSession.setUnderstandingMetadata(\n"
        "      path: conversationSession.understandingPath,\n"
        "      rejections: value,\n"
        "    );\n"
        "  }\n",
        label="Studio understanding-rejections facade",
    )
    text = replace_count(
        text,
        "  RoutingDecision? routingDecision;\n",
        "  RoutingDecision? get routingDecision =>\n"
        "      conversationSession.routingDecision;\n"
        "  set routingDecision(RoutingDecision? value) {\n"
        "    conversationSession.setRoutingDecision(value);\n"
        "  }\n",
        label="Studio routing facade",
    )
    text = replace_count(
        text,
        "  UniversalTaskPlan? canonicalPlan;\n",
        "  UniversalTaskPlan? get canonicalPlan => conversationSession.canonicalPlan;\n"
        "  set canonicalPlan(UniversalTaskPlan? value) {\n"
        "    conversationSession.setCanonicalPlan(\n"
        "      value,\n"
        "      failure: conversationSession.planningFailure,\n"
        "      reconciliation: conversationSession.lastReconciliation,\n"
        "    );\n"
        "  }\n",
        label="Studio canonical-plan facade",
    )
    text = replace_count(
        text,
        "  PlanningFailure? planningFailure;\n",
        "  PlanningFailure? get planningFailure =>\n"
        "      conversationSession.planningFailure;\n"
        "  set planningFailure(PlanningFailure? value) {\n"
        "    conversationSession.setPlanningFailure(value);\n"
        "  }\n",
        label="Studio planning-failure facade",
    )
    text = replace_count(
        text,
        "  List<CompletedTaskRecord> completedTasks = const <CompletedTaskRecord>[];\n",
        "  List<CompletedTaskRecord> get completedTasks =>\n"
        "      conversationSession.completedTasks;\n"
        "  set completedTasks(List<CompletedTaskRecord> value) {\n"
        "    conversationSession.setCompletedTasks(value);\n"
        "  }\n",
        label="Studio completed-task facade",
    )
    text = replace_count(
        text,
        "  PlanReconciliationResult? lastReconciliation;\n",
        "  PlanReconciliationResult? get lastReconciliation =>\n"
        "      conversationSession.lastReconciliation;\n"
        "  set lastReconciliation(PlanReconciliationResult? value) {\n"
        "    conversationSession.setLastReconciliation(value);\n"
        "  }\n",
        label="Studio reconciliation facade",
    )
    text = replace_count(
        text,
        "  String activeRequest = '';\n",
        "  String get activeRequest => conversationSession.activeRequest;\n"
        "  set activeRequest(String value) {\n"
        "    conversationSession.setActiveRequest(value);\n"
        "  }\n",
        label="Studio active-request facade",
    )
    return text


def transform_test(text: str) -> str:
    text = replace_count(
        text,
        "import 'package:kristin_local_agent/product/run_live_signals.dart';\n",
        "import 'package:kristin_local_agent/product/run_live_signals.dart';\n"
        "import 'package:kristin_local_agent/product/task_kernel/task_understanding.dart';\n",
        label="session test understanding import",
    )

    marker = "  });\n}\n\nAgentDeferredInteraction _interaction({"
    addition = """  });

  test('turn-scoped understanding and planning metadata reset canonically', () {
    final session = KristinConversationSession();
    session.setUnderstandingMetadata(
      path: UnderstandingPath.model,
      rejections: const <String>['invented target'],
    );
    session.setPlanningPath(ChatPlanningPath.model);
    session.setActiveRequest('  stale request  ');

    expect(session.understandingPath, UnderstandingPath.model);
    expect(session.understandingRejections, <String>['invented target']);
    expect(session.planningPath, ChatPlanningPath.model);
    expect(session.activeRequest, 'stale request');

    session.beginGovernedRequest('  next request  ');

    expect(session.understandingPath, UnderstandingPath.deterministic);
    expect(session.understandingRejections, isEmpty);
    expect(session.planningPath, ChatPlanningPath.deterministic);
    expect(session.activeRequest, 'next request');

    session.setUnderstandingMetadata(
      path: UnderstandingPath.model,
      rejections: const <String>['second rejection'],
    );
    session.setPlanningPath(ChatPlanningPath.fallback);
    expect(session.detachFinishedRun(), isTrue);

    expect(session.understandingPath, UnderstandingPath.deterministic);
    expect(session.understandingRejections, isEmpty);
    expect(session.planningPath, ChatPlanningPath.deterministic);
    expect(session.activeRequest, isEmpty);
  });

  test('project-process projection cannot leak across project selection', () {
    final session = KristinConversationSession();
    final process = ProjectProcessStatus(
      projectId: 'project-a',
      processId: 'process-a',
      label: 'Dev server',
      command: 'run-dev',
      pid: 4242,
      running: true,
      startedAt: DateTime.utc(2026, 8, 29),
      outputTail: 'ready',
      logFileName: 'process-a.log',
    );

    session.selectProject('project-a');
    session.setProjectProcessStatus(projectId: 'project-a', status: process);
    expect(session.projectProcessStatus, same(process));

    session.selectProject('project-b');
    expect(session.projectProcessStatus, isNull);

    // A stale async completion for the previous project is ignored.
    session.setProjectProcessStatus(projectId: 'project-a', status: process);
    expect(session.projectProcessStatus, isNull);
  });
}

AgentDeferredInteraction _interaction({"""
    text = replace_count(
        text,
        marker,
        addition,
        label="session convergence regression tests",
    )
    return text


TRANSFORMS = {
    "session": transform_session,
    "studio": transform_studio,
    "test": transform_test,
}


def _run_git(root: Path, *args: str) -> str:
    return subprocess.check_output(
        ["git", "-C", str(root), *args],
        text=True,
        stderr=subprocess.STDOUT,
    ).strip()


def verify_checkout(root: Path, *, allow_head_mismatch: bool, allow_dirty: bool) -> None:
    if not (root / ".git").exists():
        raise TransformError(f"{root} is not a git checkout")
    head = _run_git(root, "rev-parse", "HEAD")
    if head != BASE_HEAD and not allow_head_mismatch:
        raise TransformError(
            f"HEAD is {head}, expected recovered feature head {BASE_HEAD}. "
            "Use --allow-head-mismatch only after reviewing --diff output."
        )
    dirty = _run_git(root, "status", "--porcelain")
    if dirty and not allow_dirty:
        raise TransformError(
            "Checkout has uncommitted changes. Refusing to mix this migration with "
            "unknown edits. Use --allow-dirty only if you intentionally want that."
        )


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
            handle.write(content)
        os.replace(temp_name, path)
    except Exception:
        try:
            os.unlink(temp_name)
        except OSError:
            pass
        raise


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("repo", type=Path, help="path to a kris.ai checkout")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="validate all source guards; write nothing")
    mode.add_argument("--diff", action="store_true", help="print the exact unified diff; write nothing")
    mode.add_argument("--apply", action="store_true", help="apply the guarded transformations")
    parser.add_argument("--allow-head-mismatch", action="store_true")
    parser.add_argument("--allow-dirty", action="store_true")
    args = parser.parse_args()

    root = args.repo.resolve()
    try:
        verify_checkout(
            root,
            allow_head_mismatch=args.allow_head_mismatch,
            allow_dirty=args.allow_dirty,
        )
        originals: dict[str, str] = {}
        updated: dict[str, str] = {}
        for relative, kind in TARGETS.items():
            path = root / relative
            original = path.read_text(encoding="utf-8")
            transformed = TRANSFORMS[kind](original)
            if transformed == original:
                raise TransformError(f"{relative}: transform produced no change")
            originals[relative] = original
            updated[relative] = transformed

        if args.diff:
            for relative in TARGETS:
                sys.stdout.writelines(
                    difflib.unified_diff(
                        originals[relative].splitlines(keepends=True),
                        updated[relative].splitlines(keepends=True),
                        fromfile=f"a/{relative}",
                        tofile=f"b/{relative}",
                    )
                )
            return 0

        if args.check:
            print(f"OK: all guarded transformations match recovered head {BASE_HEAD}")
            for relative in TARGETS:
                print(f"  would update {relative}")
            return 0

        for relative in TARGETS:
            atomic_write(root / relative, updated[relative])
        print("Applied One-Kristin state convergence slice. Git metadata was not changed.")
        for relative in TARGETS:
            print(f"  updated {relative}")
        print("SOURCE_MANIFEST.sha256 intentionally not regenerated by this bundle.")
        return 0
    except (TransformError, OSError, subprocess.CalledProcessError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

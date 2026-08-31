#!/usr/bin/env python3
"""Static post-apply validation for the One-Kristin state convergence slice."""
from __future__ import annotations

import argparse
from pathlib import Path
import sys


def require(text: str, needle: str, label: str, errors: list[str]) -> None:
    if needle not in text:
        errors.append(f"missing {label}: {needle!r}")


def forbid(text: str, needle: str, label: str, errors: list[str]) -> None:
    if needle in text:
        errors.append(f"still contains {label}: {needle!r}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("repo", type=Path)
    args = parser.parse_args()
    root = args.repo.resolve()

    session = (root / "lib/product/kristin_conversation_session.dart").read_text(encoding="utf-8")
    studio = (root / "lib/product/chat_control_plane_studio.dart").read_text(encoding="utf-8")
    tests = (root / "test/product/kristin_conversation_session_test.dart").read_text(encoding="utf-8")
    errors: list[str] = []

    for needle, label in [
        ("enum ChatPlanningPath {", "canonical planning-path type"),
        ("UnderstandingPath _understandingPath", "canonical understanding path"),
        ("List<String> _understandingRejections", "canonical understanding rejections"),
        ("ProjectProcessStatus? _projectProcessStatus", "canonical project-process projection"),
        ("void setPendingDecision(", "pending-decision mutation"),
        ("void setUnderstandingMetadata(", "understanding metadata mutation"),
        ("void setPlanningPath(", "planning-path mutation"),
        ("void setProjectProcessStatus(", "project-process mutation"),
        ("_projectProcessProjectId = null;", "project-process invalidation"),
        ("selectProject(run.command.contract.projectId);", "run-selected project routing"),
    ]:
        require(session, needle, label, errors)

    for needle, label in [
        ("enum ChatPlanningPath {", "Studio-local planning-path enum"),
        ("ProjectProcessStatus? projectProcessStatus;", "Studio-local project process"),
        ("ChatInteractionDecision? pendingDecision;", "Studio-local pending decision"),
        ("UnderstandingHistory? understandingHistory;", "Studio-local understanding history"),
        ("PreparedCommand? prepared;", "Studio-local prepared command"),
        ("TaskSpecification? taskSpecification;", "Studio-local task specification"),
        ("RoutingDecision? routingDecision;", "Studio-local routing decision"),
        ("UniversalTaskPlan? canonicalPlan;", "Studio-local canonical plan"),
        ("PlanningFailure? planningFailure;", "Studio-local planning failure"),
        ("PlanReconciliationResult? lastReconciliation;", "Studio-local reconciliation"),
        ("String activeRequest = '';", "Studio-local active request"),
    ]:
        forbid(studio, needle, label, errors)

    for needle, label in [
        ("conversationSession.projectProcessStatus", "Studio process facade"),
        ("conversationSession.pendingDecision", "Studio decision facade"),
        ("conversationSession.understandingHistory", "Studio understanding facade"),
        ("conversationSession.prepared", "Studio prepared facade"),
        ("conversationSession.taskSpecification", "Studio task-spec facade"),
        ("conversationSession.routingDecision", "Studio routing facade"),
        ("conversationSession.canonicalPlan", "Studio plan facade"),
        ("conversationSession.lastReconciliation", "Studio reconciliation facade"),
        ("conversationSession.activeRequest", "Studio active-request facade"),
    ]:
        require(studio, needle, label, errors)

    for needle, label in [
        ("turn-scoped understanding and planning metadata reset canonically", "metadata reset regression test"),
        ("project-process projection cannot leak across project selection", "project process scoping regression test"),
        ("UnderstandingPath.model", "model understanding test state"),
        ("ChatPlanningPath.fallback", "fallback planning test state"),
    ]:
        require(tests, needle, label, errors)

    if errors:
        print("Validation failed:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1
    print("OK: static One-Kristin ownership validation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

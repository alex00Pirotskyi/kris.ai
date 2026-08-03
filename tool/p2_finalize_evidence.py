#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import pathlib
import shutil
import subprocess
import sys
import time

from p2_evidence_contract import (
    PLATFORMS,
    TASKS,
    sha256_file,
    validate_owner_approval,
    validate_platform_receipt,
    validate_review,
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--project', default='.')
    parser.add_argument('--reviewed-sha', required=True)
    parser.add_argument('--reviewed-tree', required=True)
    parser.add_argument('--package-sha256', required=True)
    parser.add_argument('--owner-approval', required=True)
    parser.add_argument('--security-review', required=True)
    parser.add_argument('--base-main-sha', required=True)
    parser.add_argument('--base-main-tree', required=True)
    parser.add_argument('--p1-base-verification', required=True)
    parser.add_argument('--platform-receipt', action='append', required=True)
    args = parser.parse_args()
    root = pathlib.Path(args.project).resolve()

    if len(args.platform_receipt) != 3:
        raise SystemExit('exactly three platform receipts required')
    receipt_paths = [pathlib.Path(value).resolve() for value in args.platform_receipt]
    receipts: dict[str, dict] = {}
    receipt_path_by_platform: dict[str, pathlib.Path] = {}
    for path in receipt_paths:
        row = validate_platform_receipt(path, commit_sha=args.reviewed_sha)
        platform = row['platform']
        if platform in receipts:
            raise SystemExit(f'duplicate platform receipt: {platform}')
        receipts[platform] = row
        receipt_path_by_platform[platform] = path
    if set(receipts) != set(PLATFORMS):
        raise SystemExit('one exact receipt per platform required')

    digests = {
        platform: sha256_file(receipt_path_by_platform[platform])
        for platform in PLATFORMS
    }
    owner_path = pathlib.Path(args.owner_approval).resolve()
    review_path = pathlib.Path(args.security_review).resolve()
    p1_base_path = pathlib.Path(args.p1_base_verification).resolve()
    if not p1_base_path.is_file():
        raise SystemExit('P1 exact-base verification receipt required')
    p1_base = json.loads(p1_base_path.read_text(encoding='utf-8'))
    p1_base_digest = sha256_file(p1_base_path)
    if (
        p1_base.get('schemaVersion') != '3.0.0'
        or p1_base.get('receiptType')
        != 'kristin-p1-p1a-exact-base-verification-v3'
        or p1_base.get('status') != 'passed'
        or p1_base.get('baseCommit') != args.base_main_sha
        or p1_base.get('baseTree') != args.base_main_tree
    ):
        raise SystemExit('P1/P1A V63 exact-base verification receipt binding invalid')
    required_p1a = {
        'p1aStatus': 'passed',
        'p1aCompletionClaim': True,
        'p1aDependencySatisfied': True,
        'p1aTaskCompleted': True,
        'p1aMergedMainCommit': args.base_main_sha,
    }
    for key, value in required_p1a.items():
        if p1_base.get(key) != value:
            raise SystemExit(f'P1A exact-base verification field invalid: {key}')

    def require_hex_digest(value: object, label: str) -> str:
        text = str(value or '')
        if len(text) != 64 or any(ch not in '0123456789abcdef' for ch in text):
            raise SystemExit(f'P1A exact-base verification digest invalid: {label}')
        return text

    for key in (
        'aggregateManifestSha256',
        'executedExitResultSha256',
        'p1aAggregateManifestSha256',
        'p1aExecutedExitResultSha256',
        'p1aEvidenceTrustSha256',
    ):
        require_hex_digest(p1_base.get(key), key)

    expected_platforms = set(PLATFORMS)
    platform_receipts = p1_base.get('p1aPlatformReceiptSha256')
    if not isinstance(platform_receipts, dict) or set(platform_receipts) != expected_platforms:
        raise SystemExit('P1A exact-base platform receipt graph invalid')
    for platform, digest in platform_receipts.items():
        require_hex_digest(digest, f'p1aPlatformReceiptSha256.{platform}')

    component_graph = p1_base.get('p1aPlatformComponentGraph')
    if not isinstance(component_graph, dict) or set(component_graph) != expected_platforms:
        raise SystemExit('P1A exact-base platform component graph invalid')
    for platform, components in component_graph.items():
        if not isinstance(components, dict) or not components:
            raise SystemExit(f'P1A exact-base component graph empty: {platform}')
        for component, digest in components.items():
            require_hex_digest(digest, f'p1aPlatformComponentGraph.{platform}.{component}')

    required_behavioral_jobs = [
        'p1a-behavioral-windows',
        'p1a-behavioral-macos',
        'p1a-behavioral-linux',
    ]
    if p1_base.get('p1aRequiredBehavioralJobs') != required_behavioral_jobs:
        raise SystemExit('P1A exact-base behavioral workflow contract invalid')
    if not isinstance(p1_base.get('p1aIndependentSecurityReview'), dict):
        raise SystemExit('P1A exact-base independent review binding missing')
    owner = validate_owner_approval(
        owner_path,
        reviewed_commit=args.reviewed_sha,
        reviewed_tree=args.reviewed_tree,
        package_sha256=args.package_sha256,
        base_main_sha=args.base_main_sha,
        base_main_tree=args.base_main_tree,
        p1_base_verification_sha256=p1_base_digest,
    )
    review = validate_review(
        review_path,
        reviewed_commit=args.reviewed_sha,
        reviewed_tree=args.reviewed_tree,
        package_sha256=args.package_sha256,
        platform_receipt_digests=digests,
        base_main_sha=args.base_main_sha,
        base_main_tree=args.base_main_tree,
        p1_base_verification_sha256=p1_base_digest,
    )

    for task in TASKS:
        command = [
            sys.executable,
            str(root / 'tool/p2_task_gate.py'),
            '--project',
            str(root),
            '--task',
            task,
            '--reviewed-sha',
            args.reviewed_sha,
            '--require-behavioral',
        ]
        for path in receipt_paths:
            command.extend(['--platform-receipt', str(path)])
        subprocess.run(command, check=True)

    now = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    completed = root / 'tasks/completed'
    completed.mkdir(parents=True, exist_ok=True)
    aggregate = root / 'release/evidence/P2'
    aggregate.mkdir(parents=True, exist_ok=True)

    # Preserve the exact independent-review source artifact, not only the
    # normalized JSON decision wrapper.
    external_reference = pathlib.Path(review['reviewArtifactReference'])
    if not external_reference.is_absolute():
        external_reference = (review_path.parent / external_reference).resolve()
    suffix = external_reference.suffix or '.bin'
    external_target = aggregate / f'independent-security-review-artifact{suffix}'
    shutil.copyfile(external_reference, external_target)
    external_digest = sha256_file(external_target)
    if external_digest != review['reviewArtifactSha256']:
        raise SystemExit('copied independent review artifact digest mismatch')

    platform_refs = {
        platform: {
            'path': (
                str(receipt_path_by_platform[platform].relative_to(root))
                if receipt_path_by_platform[platform].is_relative_to(root)
                else str(receipt_path_by_platform[platform])
            ),
            'sha256': digests[platform],
            'workflowRunId': receipts[platform]['workflowRunId'],
            'jobId': receipts[platform]['jobId'],
            'jobName': receipts[platform]['jobName'],
            'artifactName': receipts[platform]['artifactName'],
            'artifactSha256': receipts[platform]['artifactSha256'],
            'artifactRoot': receipts[platform]['artifactRoot'],
        }
        for platform in PLATFORMS
    }

    # P2-004 becomes accepted only after strict v4 candidate observations are
    # embedded in exact task-specific receipts for every platform. No implementation
    # is selected here by preference or a source marker.
    accepted_adr = {
        'schemaVersion': '1.0.0',
        'adr': 'ADR-0012-p2-automation-host',
        'status': 'accepted',
        'selected': 'validated-by-identical-p2-004-v4-platform-observations',
        'reviewedCommit': args.reviewed_sha,
        'reviewedTree': args.reviewed_tree,
        'packageSha256': args.package_sha256,
        'acceptedAt': now,
        'platformMeasurements': {
            platform: {
                'receiptSha256': digests[platform],
                'taskResultSha256': receipts[platform]['taskAssertions']['P2-004']['taskResultSha256'],
                'assertions': [
                    {
                        'assertionId': item['assertionId'],
                        'resultHash': item['resultHash'],
                        'evidenceSha256': item['evidenceSha256'],
                    }
                    for item in receipts[platform]['taskAssertions']['P2-004']['assertions']
                ],
            }
            for platform in PLATFORMS
        },
        'independentReviewDecision': review['decision'],
    }
    accepted_adr_path = root / 'release/evidence/P2-004/ACCEPTED_ADR.json'
    accepted_adr_path.write_text(json.dumps(accepted_adr, indent=2) + '\n')

    p1_base_target = aggregate / 'p1-p1a-exact-base-verification.json'
    shutil.copyfile(p1_base_path, p1_base_target)
    if sha256_file(p1_base_target) != p1_base_digest:
        raise SystemExit('copied P1 exact-base receipt digest mismatch')
    owner_digest = sha256_file(owner_path)
    review_digest = sha256_file(review_path)
    for task in TASKS:
        directory = root / 'release/evidence' / task
        manifest = json.loads((directory / 'manifest.json').read_text())
        manifest.update(
            {
                'schemaVersion': '3.0.0',
                'status': 'passed',
                'reviewedCommit': args.reviewed_sha,
                'reviewedTree': args.reviewed_tree,
                'packageSha256': args.package_sha256,
                'completedAt': now,
                'baseMainSha': args.base_main_sha,
                'baseMainTree': args.base_main_tree,
                'p1BaseVerificationPath': str(p1_base_target.relative_to(root)),
                'p1BaseVerificationSha256': p1_base_digest,
                'p1aAggregateManifestSha256': p1_base['p1aAggregateManifestSha256'],
                'p1aExecutedExitResultSha256': p1_base['p1aExecutedExitResultSha256'],
                'p1aEvidenceTrustSha256': p1_base['p1aEvidenceTrustSha256'],
                'p1aPlatformReceiptSha256': p1_base['p1aPlatformReceiptSha256'],
                'p1aPlatformComponentGraph': p1_base['p1aPlatformComponentGraph'],
                'p1aRequiredBehavioralJobs': p1_base['p1aRequiredBehavioralJobs'],
                'ownerApproval': {
                    'status': 'approved',
                    'ownerName': owner['ownerName'],
                    'approvedAt': owner['approvedAt'],
                    'artifactSha256': owner_digest,
                },
                'independentReview': {
                    'decision': review['decision'],
                    'reviewerName': review['reviewerName'],
                    'reviewerOrganizationOrRelationship': review[
                        'reviewerOrganizationOrRelationship'
                    ],
                    'reviewDate': review['reviewDate'],
                    'decisionArtifactSha256': review_digest,
                    'externalArtifactPath': str(external_target.relative_to(root)),
                    'externalArtifactSha256': external_digest,
                },
                'platformReceipts': platform_refs,
                'taskBehavioralAssertions': {
                    platform: {
                        'taskResultPath': receipts[platform]['taskAssertions'][task]['taskResultPath'],
                        'taskResultSha256': receipts[platform]['taskAssertions'][task]['taskResultSha256'],
                        'assertions': [
                            {
                                'assertionId': item['assertionId'],
                                'resultHash': item['resultHash'],
                                'evidencePath': item['evidencePath'],
                                'evidenceSha256': item['evidenceSha256'],
                            }
                            for item in receipts[platform]['taskAssertions'][task]['assertions']
                        ],
                    }
                    for platform in PLATFORMS
                },
                'acceptedAdrPath': 'release/evidence/P2-004/ACCEPTED_ADR.json' if task == 'P2-004' else None,
                'completedTaskPacket': f'tasks/completed/{task}.md',
                'sourceOnlyIsNotBehavioralProof': True,
            }
        )
        (directory / 'manifest.json').write_text(
            json.dumps(manifest, indent=2) + '\n'
        )
        (directory / 'OWNER_APPROVAL.md').write_text(
            f'# {task} owner approval\n\n'
            'Status: **APPROVED**\n\n'
            f"Owner: {owner['ownerName']}\n\n"
            f"Approved at: `{owner['approvedAt']}`\n\n"
            f'Reviewed source commit: `{args.reviewed_sha}`\n\n'
            f'Reviewed tree: `{args.reviewed_tree}`\n\n'
            f'Package SHA-256: `{args.package_sha256}`\n\n'
            f'Approval artifact SHA-256: `{owner_digest}`\n'
        )
        (completed / f'{task}.md').write_text(
            f"# {task} — {manifest['name']}\n\n"
            'Status: **DONE**\n\n'
            'The task passed task-specific behavioral assertions on Windows, '
            'macOS, and Linux for reviewed source commit '
            f'`{args.reviewed_sha}`. Owner approval and an independent security '
            f'review are hash-bound in `release/evidence/{task}/manifest.json`.\n'
        )

    review_target = aggregate / 'independent-security-review.json'
    review_target.write_text(json.dumps(review, indent=2) + '\n')
    owner_target = aggregate / 'owner-approval.json'
    owner_target.write_text(json.dumps(owner, indent=2) + '\n')
    (aggregate / 'manifest.json').write_text(
        json.dumps(
            {
                'schemaVersion': '2.0.0',
                'phase': 'P2',
                'status': 'passed',
                'reviewedCommit': args.reviewed_sha,
                'reviewedTree': args.reviewed_tree,
                'packageSha256': args.package_sha256,
                'completedAt': now,
                'baseMainSha': args.base_main_sha,
                'baseMainTree': args.base_main_tree,
                'p1BaseVerificationPath': str(p1_base_target.relative_to(root)),
                'p1BaseVerificationSha256': p1_base_digest,
                'p1aAggregateManifestSha256': p1_base['p1aAggregateManifestSha256'],
                'p1aExecutedExitResultSha256': p1_base['p1aExecutedExitResultSha256'],
                'p1aEvidenceTrustSha256': p1_base['p1aEvidenceTrustSha256'],
                'p1aPlatformReceiptSha256': p1_base['p1aPlatformReceiptSha256'],
                'p1aPlatformComponentGraph': p1_base['p1aPlatformComponentGraph'],
                'p1aRequiredBehavioralJobs': p1_base['p1aRequiredBehavioralJobs'],
                'tasks': TASKS,
                'platformReceipts': platform_refs,
                'ownerApprovalSha256': sha256_file(owner_target),
                'independentSecurityReviewSha256': sha256_file(review_target),
                'independentSecurityReviewArtifactPath': str(
                    external_target.relative_to(root)
                ),
                'independentSecurityReviewArtifactSha256': external_digest,
                'acceptedAutomationHostAdrPath': str(accepted_adr_path.relative_to(root)),
                'acceptedAutomationHostAdrSha256': sha256_file(accepted_adr_path),
                'evidenceCommitScopeOnly': True,
            },
            indent=2,
        )
        + '\n'
    )
    print('P2 evidence finalized: PASS')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

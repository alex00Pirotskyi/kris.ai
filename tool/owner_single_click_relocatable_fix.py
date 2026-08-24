#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def rep(path: str, old: str, new: str) -> None:
    p = ROOT / path
    text = p.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, got {count}: {old[:120]!r}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')


# The Dart resolver hashes directory rows after a global relative-path sort.
# Match that canonical order in the Node configurator. A depth-first walk is
# not equivalent when a sibling file and directory share a lexical prefix.
rep(
    'tool/configure-owner-risk-runtime.mjs',
    "  walk(root);\n  return crypto.createHash('sha256').update(rows.join('\\n')).digest('hex');",
    "  walk(root);\n  rows.sort();\n  return crypto.createHash('sha256').update(rows.join('\\n')).digest('hex');",
)

# Product bundles must be path-independent. QA keeps its historical absolute
# paths so existing QA receipts/fixtures remain unchanged.
rep(
    'tool/configure-owner-risk-runtime.mjs',
    "const policy = {\n  schemaVersion: '2.0.0', platform,\n  authorityAddress: platform === 'windows' ? String.raw`\\\\.\\pipe\\KristinOwnerRiskQa` : '/tmp/kristin-owner-risk-qa.sock',\n  nodeExecutable: path.resolve(node), nodeSha256: shaFile(node),\n  hostScript: path.resolve(host), hostScriptSha256: shaFile(host),\n  workingDirectory: path.resolve(hostRoot),\n  launcherPath: path.resolve(launcher), launcherSha256: shaFile(launcher),",
    "const runtimeRelative = value => path.relative(root, value).split(path.sep).join('/');\nconst policy = {\n  schemaVersion: '2.0.0', platform,\n  authorityAddress: productCurrentAccount\n    ? (platform === 'windows' ? String.raw`\\\\.\\pipe\\KristinCurrentAccountOwner` : '/tmp/kristin-current-account-owner.sock')\n    : (platform === 'windows' ? String.raw`\\\\.\\pipe\\KristinOwnerRiskQa` : '/tmp/kristin-owner-risk-qa.sock'),\n  nodeExecutable: productCurrentAccount ? runtimeRelative(node) : path.resolve(node), nodeSha256: shaFile(node),\n  hostScript: productCurrentAccount ? runtimeRelative(host) : path.resolve(host), hostScriptSha256: shaFile(host),\n  workingDirectory: productCurrentAccount ? runtimeRelative(hostRoot) : path.resolve(hostRoot),\n  launcherPath: productCurrentAccount ? runtimeRelative(launcher) : path.resolve(launcher), launcherSha256: shaFile(launcher),",
)
rep(
    'tool/configure-owner-risk-runtime.mjs',
    "  ownerRiskQa: true, osIsolationWaived: true, productCurrentAccount,\n};",
    "  ownerRiskQa: !productCurrentAccount, osIsolationWaived: true, productCurrentAccount,\n};",
)
rep(
    'tool/configure-owner-risk-runtime.mjs',
    "    KRISTIN_P2_COMMIT_SHA: sourceCommit,\n    KRISTIN_P2_SOURCE_PACKAGE_SHA256: p2PackageSha256,\n    KRISTIN_P2_E2E_ROOT: root, KRISTIN_P2_RUNNER_ID: `owner-risk-qa-${platform}`,\n    KRISTIN_P2_RUNNER_GROUP: 'github-hosted-tri-platform-qa',",
    "    KRISTIN_P2_COMMIT_SHA: sourceCommit,\n    KRISTIN_P2_SOURCE_PACKAGE_SHA256: p2PackageSha256,\n    ...(!productCurrentAccount ? {\n      KRISTIN_P2_E2E_ROOT: root,\n      KRISTIN_P2_RUNNER_ID: `owner-risk-qa-${platform}`,\n      KRISTIN_P2_RUNNER_GROUP: 'github-hosted-tri-platform-qa',\n    } : {}),",
)

# In product mode, worker policy paths are relative to the runtime root. The
# launcher resolves them from the policy location rather than process cwd.
rep(
    'automation_host/src/owner-risk-launcher.mjs',
    "const node = path.resolve(policy.nodeExecutable);\nconst host = path.resolve(policy.hostScript);\nconst self = fileURLToPath(import.meta.url);",
    "const runtimeRoot = path.resolve(path.dirname(policyPath), '..');\nconst runtimePath = value => productCurrentAccount\n  ? path.resolve(runtimeRoot, value)\n  : path.resolve(value);\nconst node = runtimePath(policy.nodeExecutable);\nconst host = runtimePath(policy.hostScript);\nconst self = fileURLToPath(import.meta.url);",
)
rep(
    'automation_host/src/owner-risk-launcher.mjs',
    "process.chdir(path.resolve(policy.workingDirectory));",
    "process.chdir(runtimePath(policy.workingDirectory));",
)

# The app-data copy is byte-for-byte. Do not rerun the configurator after copy:
# doing so would mutate the governed runtime closure and invalidate its digest.
p = ROOT / 'lib/product/p2_bundled_current_account_runtime.dart'
text = p.read_text(encoding='utf-8')
if "import 'p2_runtime_resource_resolver.dart';" not in text:
    text = text.replace(
        "import 'dart:io';\n",
        "import 'dart:io';\n\nimport 'p2_runtime_resource_resolver.dart';\n",
        1,
    )
start_marker = "    final provisioning = File(\n"
end_marker = "    return true;\n"
start = text.find(start_marker)
end = text.find(end_marker, start)
if start < 0 or end < 0:
    raise SystemExit('p2_bundled_current_account_runtime.dart: relocation block anchors missing')
end += len(end_marker)
replacement = """    final resolved = await P2ApplicationOwnedRuntimeResourceResolver(\n      applicationDataRoot: applicationDataRoot.absolute,\n      executablePath:\n          '${applicationDataRoot.absolute.path}${Platform.pathSeparator}kristin-runtime-probe',\n    ).resolve();\n    final resolvedRoot = await resolved.root.resolveSymbolicLinks();\n    final expectedRoot = await targetRoot.resolveSymbolicLinks();\n    if (resolvedRoot != expectedRoot ||\n        resolved.provisionedEnvironment[\n                'KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT'] !=\n            '1' ||\n        resolved.provisionedEnvironment.containsKey('KRISTIN_OWNER_RISK_QA')) {\n      throw StateError('p2_current_account_relocated_runtime_invalid');\n    }\n    return true;\n"""
text = text[:start] + replacement + text[end:]
p.write_text(text, encoding='utf-8', newline='\n')

print('OWNER_SINGLE_CLICK_RELOCATABLE_FIX_OK')

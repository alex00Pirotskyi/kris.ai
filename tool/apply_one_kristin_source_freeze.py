#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
path = root / 'test/product/source_contract_test.dart'
text = path.read_text(encoding='utf-8')


def insert_after(marker: str, insertion: str) -> None:
    global text
    if insertion.strip() in text:
        return
    if text.count(marker) != 1:
        raise SystemExit(f'source-contract marker is not unique: {marker!r}')
    text = text.replace(marker, marker + insertion, 1)


insert_after(
    "        'lib/product/capability_doctor.dart',\n",
    "        'lib/product/capability_invocation.dart',\n",
)
insert_after(
    "        'lib/product/chat_control_plane.dart',\n",
    "        'lib/product/chat_control_plane_streaming.dart',\n",
)
insert_after(
    "        'lib/product/kristin_conversation_session.dart',\n",
    "        'lib/product/utility_time.dart',\n",
)
insert_after(
    "        'lib/product/task_kernel/complexity_router.dart',\n",
    "        'lib/product/task_kernel/kernel_task_graph_executor.dart',\n"
    "        'lib/product/task_kernel/plan_compile_repair.dart',\n",
)
insert_after(
    "        'lib/product/task_kernel/planning_failures.dart',\n",
    "        'lib/product/task_kernel/semantic_slash_understanding.dart',\n"
    "        'lib/product/task_kernel/semantic_steering.dart',\n",
)
insert_after(
    "        'lib/product/task_kernel/task_families.dart',\n",
    "        'lib/product/task_kernel/task_family_executor.dart',\n"
    "        'lib/product/task_kernel/task_specification_patch.dart',\n"
    "        'lib/product/task_kernel/task_specification_patch_classifier.dart',\n",
)

expected_new = (
    'lib/product/capability_invocation.dart',
    'lib/product/chat_control_plane_streaming.dart',
    'lib/product/utility_time.dart',
    'lib/product/task_kernel/kernel_task_graph_executor.dart',
    'lib/product/task_kernel/plan_compile_repair.dart',
    'lib/product/task_kernel/semantic_slash_understanding.dart',
    'lib/product/task_kernel/semantic_steering.dart',
    'lib/product/task_kernel/task_family_executor.dart',
    'lib/product/task_kernel/task_specification_patch.dart',
    'lib/product/task_kernel/task_specification_patch_classifier.dart',
)
for relative in expected_new:
    token = f"        '{relative}',"
    if text.count(token) != 1:
        raise SystemExit(f'expected exactly one governed inventory entry for {relative}')

path.write_text(text, encoding='utf-8')
print(f'Added {len(expected_new)} exact One Kristin library paths to governed source inventory.')

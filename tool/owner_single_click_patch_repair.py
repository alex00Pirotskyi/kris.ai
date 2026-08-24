#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).resolve().with_name('owner_single_click_patch.py')
text = path.read_text(encoding='utf-8')

old = '''replace_once(
    'lib/product/p2_runtime_resource_resolver.dart',
    "      'KRISTIN_OWNER_RISK_QA',\\n",
    "      'KRISTIN_OWNER_RISK_QA',\\n      'KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT',\\n",
)
'''
new = '''replace_once(
    'lib/product/p2_runtime_resource_resolver.dart',
    "      'RUNNER_NAME',\\n      'KRISTIN_OWNER_RISK_QA',\\n    };",
    "      'RUNNER_NAME',\\n      'KRISTIN_OWNER_RISK_QA',\\n      'KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT',\\n    };",
)
'''
if text.count(old) != 1:
    raise SystemExit('resolver patch anchor repair failed')
text = text.replace(old, new, 1)

old = '''replace_once(
    'lib/product/p2_product_runtime_bootstrap.dart',
    "      'KRISTIN_OWNER_RISK_QA',\\n",
    "      'KRISTIN_OWNER_RISK_QA',\\n      'KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT',\\n",
)
'''
new = '''replace_once(
    'lib/product/p2_product_runtime_bootstrap.dart',
    "      'RUNNER_NAME',\\n      'KRISTIN_OWNER_RISK_QA',\\n    };",
    "      'RUNNER_NAME',\\n      'KRISTIN_OWNER_RISK_QA',\\n      'KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT',\\n    };",
)
'''
if text.count(old) != 1:
    raise SystemExit('bootstrap patch anchor repair failed')
text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8', newline='\n')
print('OWNER_SINGLE_CLICK_PATCH_REPAIR_OK')

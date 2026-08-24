#!/usr/bin/env python3
from pathlib import Path
import runpy

self_path = Path(__file__).resolve()
path = self_path.with_name('owner_single_click_chain_fix.py')
text = path.read_text(encoding='utf-8')
old = "        identity['productCurrentAccount'] != productCurrentAccount ||\\n"
new = "        (identity['productCurrentAccount'] == true) != productCurrentAccount ||\\n"
if text.count(old) != 1:
    raise SystemExit('bind identity compatibility anchor missing')
text = text.replace(old, new, 1)
old = "            workerIdentity['productCurrentAccount'] == false &&\\n"
new = "            workerIdentity['productCurrentAccount'] != true &&\\n"
if text.count(old) != 1:
    raise SystemExit('proof identity compatibility anchor missing')
text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8', newline='\n')

fast_fix = self_path.with_name('owner_single_click_fast_command_fix.py')
if not fast_fix.is_file():
    raise SystemExit('fast command repair helper missing')
runpy.run_path(str(fast_fix), run_name='__main__')

print('OWNER_SINGLE_CLICK_CHAIN_REPAIR_OK')

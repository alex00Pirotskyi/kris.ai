from pathlib import Path

path = Path('.repo-p5-004-finalize.py')
text = path.read_text(encoding='utf-8')
old = '''replace_once(
    'lib/product/p5_information_architecture/p5_prototype.dart',
    """  @override
  void dispose() {
""",
    """  @override
  void initState() {
    super.initState();
    unawaited(_initializeP5ShellLayout());
  }

  @override
  void dispose() {
    _shellLayoutSaveDebounce?.cancel();
""",
)
'''
new = '''replace_once(
    'lib/product/p5_information_architecture/p5_prototype.dart',
    """  @override
  void dispose() {
    unawaited(_webBrowser?.close());
""",
    """  @override
  void initState() {
    super.initState();
    unawaited(_initializeP5ShellLayout());
  }

  @override
  void dispose() {
    _shellLayoutSaveDebounce?.cancel();
    unawaited(_webBrowser?.close());
""",
)
'''
count = text.count(old)
if count != 1:
    raise SystemExit(f'expected one materializer dispose replacement block, found {count}')
path.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')
print('P5_004_PROTOTYPE_DISPOSE_ANCHOR_FIXED')

from pathlib import Path

path = Path('lib/product/chat_control_plane_studio.dart')
text = path.read_text(encoding='utf-8')
old = """  bool get awaitingPermission => conversationSession.awaitingPermission;
  set awaitingPermission(bool value) =>
      conversationSession.setAwaitingPermission(value);
"""
new = """  bool get awaitingPermission => conversationSession.awaitingPermission;
  set awaitingPermission(bool value) {
    // A legacy side-action cleanup may request `false`, but durable run state
    // remains authoritative. Only a refreshed non-awaiting run (or no run)
    // may clear the permission projection.
    if (!value && conversationSession.runAwaitingApproval) {
      return;
    }
    conversationSession.setAwaitingPermission(value);
  }
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected permission projection shape: {text.count(old)} matches')
path.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')

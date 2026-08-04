# Known limitations

- External evidence signers, trust documents, protected hardware keys, self-hosted runner attestations, and independent security review are intentionally not required in V70-R5.
- The owner-risk authority grants effects to the current OS account and may be run as administrator/root. This can modify or destroy accessible data.
- GitHub-hosted automated tests do not replace manual interactive clipboard, screen, active-window, PTY UX, application-control, and destructive recovery testing on real QA desktops.
- The macOS QA app and bundled native executables are re-signed ad hoc after runtime staging; Windows and Linux QA artifacts are not publisher-signed.
- Formal P1A/P2 completion flags remain false. TRAIN-02 is not automatically marked DONE by this QA lane.
- A later production release must restore or redesign the formal security/evidence boundary.

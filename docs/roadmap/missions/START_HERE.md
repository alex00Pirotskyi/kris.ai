# Mission execution — start here

1. Read `docs/roadmap/MASTER.md` and the declared scope of `docs/roadmap/roadmap.yaml`.
2. Run `python tool/mission_control.py --project . validate`.
3. Run `python tool/mission_control.py --project . status`.
4. Resume with `python tool/mission_control.py --project . resume --mission MISSION-004 --worker C`.
5. Re-resolve the branch, PR, exact head/tree, CI, reviews, dependencies, and path ownership before editing.
6. Update state and add a checkpoint after every significant push or before yield/transfer.

A worker is replaceable. The mission contract, state, claim, checkpoint, evidence, branch, PR, and exact CI are durable memory.

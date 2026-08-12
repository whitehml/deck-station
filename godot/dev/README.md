# dev/

Development-only Godot scripts: headless smoke and integration tests that
exercise the `RobotClient` contract.

This directory is excluded from the export via `exclude_filter="dev/*"` in
`export_presets.cfg`, so nothing here ships in the release bundle.

## Contents

- `dev_smoke.gd` — Headlessly drives the full client lifecycle, asserting each
  step across the GDExtension boundary that the Rust-side loopback test can't
  reach. Prints `SMOKE OK` and exits on success.

## Running

Stage the bridge, temporarily register the script as an autoload, then run
headless against the mock:

```sh
cd rust && cargo xtask stage
# add DevSmoke="*res://dev/dev_smoke.gd" to [autoload] in godot/project.godot
DECK_DS_MOCK=1 godot4 --headless --path godot
```

The autoload line is temporary — do not commit it.

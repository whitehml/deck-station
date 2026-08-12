# Deck Station

Native replacement for the FTC Driver Station app, targeting primarily the
Steam Deck, nominally operable in desktop environments.
See `CONTROLS.md` for the full input map.

> [!WARNING]
> **For development/outreach/practice use only — NOT COMPETITION LEGAL.** Do
> not attempt to use this driver station in official FTC competition.

This is the app you run on the Steam Deck to drive the robot: the on-screen
interface, the gamepad and camera plumbing, and everything needed to package it
for the Deck. When you move a stick or tap a button, it talks to the robot over
WiFi using the `robocol` protocol.

---

# Installation

## Steam Deck

The Deck runs Linux x86_64. A bundle unpacks to a small tree: the
`deck-station.x86_64` launcher and `installed.json` at the root, over the build
itself — the Godot executable plus `librobocol_godot.so`, the native robocol
bridge Godot loads at runtime — under `versions/<version>/`.

```
~/deck/
    deck-station.x86_64              <- run/shortcut this; it never moves
    installed.json
    versions/<version>/
        deck-station.x86_64
        librobocol_godot.so
```

The launcher hands off to whichever build `installed.json` names, so updates
drop in a new `versions/` directory without disturbing your Steam shortcut or
its controller layout. Get it one of two ways:

### Download a release

Grab `deck-station-<version>-linux-x86_64.tar.gz` from the GitHub **Releases**
page and unpack it into an empty directory on the deck/target environment.

```sh
mkdir -p ~/deck && tar -xzf deck-station-*-linux-x86_64.tar.gz -C ~/deck
```

After that first install, update in place from **Settings ▸ Check for
Updates…** — no re-download, no unpacking. It needs internet access, so leave
the robot's WiFi first; the app says so if you're still connected.

Releases tagged `DS-<sdk>.<patch>` are stable. That tag names the
baseline Driver Station release the build is compatible with. The app's own
version is the `VERSION` file at the repo root, and that is what appears in the
bundle names and in **Settings**. The rolling `latest` prerelease is rebuilt
from `main` on every push, and is what the in-app updater currently follows. Windows builds ship alongside as
`deck-station-<version>-windows-x86_64.zip`, same layout with
`deck-station.exe` + `robocol_godot.dll`. `SHA256SUMS` covers every bundle and
the updater checks the download against it.

<p align="center"><strong>— OR —</strong></p>

### Build from source

Install the toolchain first:

- Rust — via [rustup](https://rustup.rs). The bridge pins 1.97.0 via
  `rust/rust-toolchain.toml`, so rustup installs it automatically on first build.
  Linux/WSL2 also needs a C toolchain: `sudo apt install build-essential`.
- Godot 4.4.1 (standard, non-.NET) from godotengine.org, on `PATH` as `godot4`,
  plus the matching export templates (Editor -> Manage Export Templates ->
  Download and Install).

Then `cargo xtask export` stages the release `.so` and runs the Godot "Linux"
export into `build/`; copy that to the Deck:

```sh
cd rust && cargo xtask export
rsync -a build/ deck@steamdeck:~/deck/
```

### Set it up in Steam

**Add it to Steam.** In Desktop Mode: **Steam ▸ Games ▸ Add a Non-Steam Game**,
browse to `~/deck/deck-station.x86_64`. Under **Controller ▸ Edit Layout**,
start from the **Gamepad** template (xinput passthrough) and add the recommended
back-grip bindings:

| Deck input | Recommended binding | App meaning (CONTROLS.md) |
|---|---|---|
| L4 / L5 | Key `F1` / `F2` | Left/right pane: tap = step source, hold = radial |
| R4 | Key `F3` | Tap = STOP · hold = sticks/d-pad drive the UI |
| R5 | Key `F4` | Tap = click at cursor · hold = slot-swap radial |
| Trackpads | Mouse / left click | Cursor + click (R5 is primary) |

Return to Gaming Mode and launch from **Library ▸ Play**.

Join the Control Hub's WiFi and launch the app, it should auto-connect to the
Control Hub.

## Desktop Environment (Any OS)

The app also runs on a plain Linux, Windows, or macOS desktop. Build and launch
from source (see [Development](#development)) with `cd rust && cargo xtask dev`,
or on Linux unpack the release tarball and run `./deck-station.x86_64` directly.

Without Steam Input there are no back grips — their four actions map to plain
keyboard keys (L4 → `F1`, L5 → `F2`, R4 → `F3`, R5 → `F4`), and the cursor is
just your mouse. Plug in any xinput pad for robot control.

---

# Development

`cargo xtask` builds the bridge for the host OS (`.so`/`.dll`/`.dylib`), stages
it under the name Godot expects, and drives Godot — so the full app (UI, mock,
and real robot) runs from source on Linux, Windows, and macOS. Run from `rust/`:

```sh
cargo xtask dev      # build + stage bridge, connect to a real RC
cargo xtask mock     # same, but build fake_rc and connect to it on loopback
```

Pass switches as environment variables before the command, e.g.
`DECK_DS_PEER=192.168.43.1 cargo xtask dev`. On the Deck, the same variables go
in the Steam entry's launch options (**Properties ▸ Shortcut**, before
`%command%` — e.g. `DECK_DS_MOCK=1 %command%`). `DECK_DS_MOCK=1` spawns `fake_rc`
on loopback and points the bridge at it, so mock exercises the same path as a
real robot:

| variable | effect |
|---|---|
| `DECK_DS_MOCK=1` | spawn `fake_rc` and connect to it (needs `fake_rc` built) |
| `DECK_DS_PEER` | robot address (default tries 192.168.43.1 / .49.1) |
| `DECK_DS_PEER_PORT` | robot Robocol port (default 20884) |
| `DECK_DS_BIND_PORT` | local port; `0` = ephemeral (default 20884) |
| `DECK_LIMELIGHT_STREAM` | Limelight stream URL (default: Control Hub address) |

## Linting / CI

CI gates every push/PR on gdformat + gdlint over `godot/` and cargo fmt + clippy
over `rust/`. The gd tools come from gdtoolkit (`pip install "gdtoolkit==4.*"`);
`rustfmt`/`clippy` ship with the pinned toolchain. Run the same checks locally
before a PR:

```sh
./scripts/lint.sh            # check
./scripts/lint.sh --fix      # auto-format, then re-check
```
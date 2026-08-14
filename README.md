# Deck Station

Native replacement for the FTC Driver Station app, targeting primarily the
Steam Deck, nominally operable in desktop environments.
See `CONTROLS.md` for the full input map.

> [!WARNING]
> For development/outreach/practice use only. **NOT COMPETITION LEGAL.** Do
> not attempt to use this driver station in official FTC competition.

This is the app you run on the Steam Deck to drive the robot: the on-screen
interface, the gamepad and camera plumbing, and everything needed to package it
for the Deck. When you move a stick or tap a button, it talks to the robot over
WiFi using the `robocol` protocol.

---

# Installation

## Steam Deck

The Deck runs Linux, so the Linux download is the one you want. There are three
steps: put the files on the Deck, add it to Steam, then connect to the robot.

### Step 1: Put the files on the Deck

Switch the Deck to Desktop Mode and open this page in a browser on the Deck
itself. From the GitHub **Releases** page, download
`deck-station-<version>-linux-x86_64.tar.gz`. Then open a
[terminal](https://pimylifeup.com/steam-deck-open-terminal/) and unpack it into
a new, empty folder:

```sh
mkdir -p ~/deck && tar -xzf deck-station-*-linux-x86_64.tar.gz -C ~/deck
```

You get one file to run, plus a folder holding everything else:

```
~/deck/
    deck-station.x86_64              <- this is the one you run
    bin/
        deck-station.x86_64
        librobocol_godot.so
```

The file at the top is a small launcher. All it does is start the real app
inside `bin/`. Keeping the two separate is what lets the app update itself later
without breaking your Steam shortcut: an update is written into a new `bin.new/`
folder, and the launcher swaps it into place the next time you start the app. So
point your shortcut at the file at the top, and leave `bin/` alone.

### Step 2: Add it to Steam

Still in Desktop Mode:

1. Go to **Steam ▸ Games ▸ Add a Non-Steam Game**.
2. Browse to `~/deck/deck-station.x86_64`. Pick the one at the top, not the copy
   inside `bin/`.
3. Select the new entry, open **Controller ▸ Edit Layout**, and start from the
   **Gamepad** template, which passes the sticks and buttons straight through.
4. Add the back-grip bindings below. The grips are not ordinary gamepad buttons,
   so Steam sends them as keyboard keys and the app reads them that way.

| Deck input | Recommended binding | App meaning (CONTROLS.md) |
|---|---|---|
| L4 / L5 | Key `F1` / `F2` | Left/right pane: tap = step source, hold = radial |
| R4 | Key `F3` | Tap = STOP · hold = sticks/d-pad drive the UI |
| R5 | Key `F4` | Tap = click at cursor · hold = slot-swap radial |
| Trackpads | Mouse / left click | Cursor + click (R5 is primary) |

### Step 3: Connect to the robot

Return to Gaming Mode and launch it from **Library ▸ Play**. Join the Control
Hub's WiFi from the Deck, and the app connects to the robot on its own.

### Updating later

Open **Settings ▸ Check for Updates** in the app. It downloads and installs the
new version for you, and the change takes effect the next time you start the
app. There is nothing to download or unpack by hand.

Updating needs internet access, so leave the robot's WiFi and join a normal
network first. The app tells you if you are still connected to the robot.

## Other computers (Windows, Linux, macOS)

The app also runs on an ordinary desktop, no Deck required. On Linux, unpack the
release tarball and run `./deck-station.x86_64`. On Windows, unpack the zip and
run `deck-station.exe`. On macOS, see below. To run it from source on any of the
three, see [Development](#development) and use `cd rust && cargo xtask dev`.

### macOS

Releases carry `deck-station-<version>-macos-universal.dmg`, a Universal 2 build
covering both Apple Silicon and Intel. Open it and drag `deck-station` to
Applications. There is no launcher stub and no `bin/`, and so no in-app updater
either: **Check for Updates** reports the install as unmanaged and points back
at the Releases page. To update, download a newer `.dmg` and drag it over the
installed app.

The build is ad-hoc signed, not notarized (there is no Apple Developer ID behind
this project), so Gatekeeper blocks it on first launch. Getting past that means
deliberately granting this app an exception to macOS's protections. How you do
that differs by macOS version, so running this build assumes you know how to
make that exception on your own machine, and are willing to.

---

# Development

## Build from source

Install the toolchain first:

- Rust, via [rustup](https://rustup.rs). The bridge pins 1.97.0 via
  `rust/rust-toolchain.toml`, so rustup installs it automatically on the first
  build. Linux/WSL2 also needs a C toolchain:
  `sudo apt install build-essential`.
- Godot 4.4.1 (standard, non-.NET) from godotengine.org, on `PATH` as `godot4`,
  plus the matching export templates (Editor -> Manage Export Templates ->
  Download and Install).

`cargo xtask` builds the bridge for the host OS (`.so`/`.dll`/`.dylib`), stages
it under the name Godot expects, and drives Godot. The full app (UI, mock, and
real robot) runs from source on Linux, Windows, and macOS. Run it from `rust/`:

```sh
cargo xtask dev      # build + stage bridge, connect to a real RC
cargo xtask mock     # same, but build fake_rc and connect to it on loopback
```

To produce a release build, and optionally copy it to the Deck:

```sh
cd rust && cargo xtask export
rsync -a build/ deck@steamdeck:~/deck/
```

## Running

Pass switches as environment variables before the `cargo xtask` command, e.g.
`DECK_DS_PEER=192.168.43.1 cargo xtask dev`. On the Deck, the same variables go
in the Steam entry's launch options (**Properties ▸ Shortcut**, before
`%command%`, e.g. `DECK_DS_MOCK=1 %command%`). `DECK_DS_MOCK=1` spawns `fake_rc`
on loopback and points the bridge at it, so mock exercises the same path as a
real robot.

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
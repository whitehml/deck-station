# Headless Driver-Station Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a desktop AI agent a scriptable, JSON-in/JSON-out way to drive an FTC robot through the `robocol` protocol, without the Godot UI.

**Architecture:** Two new binaries in the `external/robocol` workspace — `ds_agentd` (a daemon that owns one persistent `RobocolClient` connection and a cached `DaemonState`) and `ds_agent` (a thin CLI that turns argv into one JSON request, round-trips it to the daemon over a Unix domain socket, and prints the JSON reply). A small shared `ds_agent_ipc` library crate holds the socket path and line-framing logic both binaries must agree on byte-for-byte.

**Tech Stack:** Rust 2024 (matching the submodule's pinned `1.97.1` toolchain), `serde`/`serde_json` (already a workspace dependency), `std::os::unix::net` for IPC (no new external dependency), the existing `robocol` crate for the protocol client.

**Spec:** [docs/superpowers/specs/2026-09-10-headless-driver-station-agent-design.md](../specs/2026-09-10-headless-driver-station-agent-design.md)

## Global Constraints

- Implementation lives entirely in the `external/robocol` submodule checkout (a separate git repo, `github.com/whitehml/robocol`), not in `deck-station`'s own `rust/` workspace.
- No changes to the `robocol` crate's public API. `ds_agentd` builds its own JSON views of `OpModeMeta`/`Telemetry` rather than adding `Serialize` derives upstream (`ConfigMeta` already derives `Serialize`, so it's used as-is).
- IPC is a Unix domain socket only (`std::os::unix::net`). The submodule's CI (`external/robocol/.github/workflows/ci.yml`) runs solely on `ubuntu-latest`, so this doesn't affect CI; it does mean `ds_agentd`/`ds_agent` won't build on Windows in this phase — call this out in the crate docs, don't silently paper over it. Windows named-pipe support is an explicit non-goal for this plan.
- All wire fields (both the request JSON `ds_agent` sends and the response JSON `ds_agentd` sends back) are `snake_case`, matching Rust field names directly — no camelCase, no manual `#[serde(rename)]` needed anywhere in this plan.
- Every response line is exactly one JSON object terminated by `\n`, written in one `write_all` call so partial reads never interleave (see `ds_agent_ipc::write_message`).
- Run `external/robocol/scripts/lint.sh` before every commit that touches Rust code in the submodule — it mirrors CI (`cargo fmt --check`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo test --workspace`) and the new crates must pass it clean.
- Every new pub item gets doc comments in the same terse style already used in `robocol/src/client.rs` and `ds_cli/src/main.rs` — one line unless a wire-format quirk needs explaining.

---

## File Structure

```
external/robocol/
  Cargo.toml                      # add ds_agent_ipc, ds_agentd, ds_agent to members
  ds_agent_ipc/
    Cargo.toml
    src/lib.rs                    # socket_path(), read_message(), write_message()
  ds_agentd/
    Cargo.toml
    src/main.rs                   # argv parsing, RobocolClient wiring, accept loop
    src/state.rs                  # DaemonState + apply_event() + to_json()
    src/waiters.rs                # WaiterRegistry (request/response) + Subscribers (watch)
    src/request.rs                # Request enum (serde) + handle_request() dispatch
    src/connection.rs             # per-connection handling incl. run_watch()
    tests/
      end_to_end.rs               # spawns fake_rc + ds_agentd, drives real IPC
  ds_agent/
    Cargo.toml
    src/main.rs                   # build_request() from argv, connect_or_spawn(), daemon subcommand
```

Each `ds_agentd` module has one job: `state.rs` is the pure data cache (event in, JSON out — no I/O, fully unit-testable), `waiters.rs` is the pub/sub plumbing (also pure, no I/O), `request.rs` is the JSON protocol surface (depends on `state.rs` + `waiters.rs` + `RobocolClient`), `connection.rs` is the only place that touches a live socket, and `main.rs` is just wiring. `ds_agent/src/main.rs` stays a single file — it's a thin CLI with no internal state to split out.

---

### Task 1: `ds_agent_ipc` — socket path and line framing

Both binaries must resolve the exact same socket path and speak the exact same newline-delimited-JSON framing, or they can't talk to each other. This is the one piece of logic that has to be shared rather than duplicated.

**Files:**
- Create: `external/robocol/ds_agent_ipc/Cargo.toml`
- Create: `external/robocol/ds_agent_ipc/src/lib.rs`
- Modify: `external/robocol/Cargo.toml:4` (add `"ds_agent_ipc"` to `members`)

**Interfaces:**
- Produces: `pub fn socket_path() -> std::path::PathBuf`, `pub fn write_message(stream: &mut impl std::io::Write, value: &serde_json::Value) -> std::io::Result<()>`, `pub fn read_message(reader: &mut impl std::io::BufRead) -> std::io::Result<Option<String>>` (returns `Ok(None)` on clean EOF, `Ok(Some(line))` with the trailing `\n` stripped otherwise).

- [ ] **Step 1: Create the crate manifest**

```toml
# external/robocol/ds_agent_ipc/Cargo.toml
[package]
name = "ds_agent_ipc"
version = "0.1.0"
edition = "2024"
license = "MIT"
description = "Shared socket-path and line-framing logic for ds_agentd/ds_agent"

[dependencies]
serde_json = "1"
libc = "0.2"
```

- [ ] **Step 2: Add the crate to the workspace**

```toml
# external/robocol/Cargo.toml
[workspace]
resolver = "3"
members = ["robocol", "fake_rc", "ds_cli", "capture/decode", "ds_agent_ipc"]
```

- [ ] **Step 3: Write the failing tests**

```rust
// external/robocol/ds_agent_ipc/src/lib.rs
//! Socket path and line-framing shared by `ds_agentd` and `ds_agent`. Both
//! binaries must resolve the same path and speak the same framing, so this
//! logic lives once instead of being duplicated on both sides of the pipe.

use std::io::{self, BufRead, Write};
use std::path::PathBuf;

/// Where `ds_agentd` binds its Unix domain socket and `ds_agent` connects.
/// Prefers `$XDG_RUNTIME_DIR` (cleaned up by the OS on logout); falls back to
/// a per-user path under `/tmp` so this also works in a plain SSH session.
pub fn socket_path() -> PathBuf {
    if let Some(dir) = std::env::var_os("XDG_RUNTIME_DIR") {
        return PathBuf::from(dir).join("ds_agentd.sock");
    }
    let uid = unsafe { libc::getuid() };
    PathBuf::from(format!("/tmp/ds_agentd-{uid}.sock"))
}

/// Writes one JSON value as a single line: the whole `\n`-terminated buffer
/// goes out in one `write_all`, so a reader never sees a partial object.
pub fn write_message(stream: &mut impl Write, value: &serde_json::Value) -> io::Result<()> {
    let mut line = serde_json::to_vec(value).map_err(io::Error::other)?;
    line.push(b'\n');
    stream.write_all(&line)
}

/// Reads one `\n`-terminated line, with the newline stripped. `Ok(None)`
/// means clean EOF (the peer closed the connection); any other read error
/// (including an unterminated final line) still surfaces as `Err`.
pub fn read_message(reader: &mut impl BufRead) -> io::Result<Option<String>> {
    let mut line = String::new();
    let n = reader.read_line(&mut line)?;
    if n == 0 {
        return Ok(None);
    }
    if line.ends_with('\n') {
        line.pop();
        if line.ends_with('\r') {
            line.pop();
        }
    }
    Ok(Some(line))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    #[test]
    fn round_trips_one_message() {
        let mut buf = Vec::new();
        write_message(&mut buf, &serde_json::json!({"ok": true, "n": 1})).unwrap();
        let mut reader = std::io::BufReader::new(Cursor::new(buf));
        let line = read_message(&mut reader).unwrap().unwrap();
        let value: serde_json::Value = serde_json::from_str(&line).unwrap();
        assert_eq!(value["ok"], true);
        assert_eq!(value["n"], 1);
    }

    #[test]
    fn reads_multiple_messages_in_sequence() {
        let mut buf = Vec::new();
        write_message(&mut buf, &serde_json::json!({"seq": 1})).unwrap();
        write_message(&mut buf, &serde_json::json!({"seq": 2})).unwrap();
        let mut reader = std::io::BufReader::new(Cursor::new(buf));
        let first = read_message(&mut reader).unwrap().unwrap();
        let second = read_message(&mut reader).unwrap().unwrap();
        assert!(first.contains("\"seq\":1"));
        assert!(second.contains("\"seq\":2"));
    }

    #[test]
    fn clean_eof_yields_none() {
        let mut reader = std::io::BufReader::new(Cursor::new(Vec::new()));
        assert!(read_message(&mut reader).unwrap().is_none());
    }

    #[test]
    fn socket_path_prefers_xdg_runtime_dir() {
        // SAFETY: test runs single-threaded within this process's env mutation.
        unsafe { std::env::set_var("XDG_RUNTIME_DIR", "/tmp/ds-agent-test-runtime") };
        assert_eq!(
            socket_path(),
            PathBuf::from("/tmp/ds-agent-test-runtime/ds_agentd.sock")
        );
        unsafe { std::env::remove_var("XDG_RUNTIME_DIR") };
    }
}
```

- [ ] **Step 4: Run the tests to verify they fail (crate doesn't exist as a workspace member yet until Step 2, so run after both steps 1-3 are in place)**

Run: `cd external/robocol && cargo test -p ds_agent_ipc`
Expected: compiles and passes — this crate has no prior implementation to be "failing" against, so this step confirms the code as written is correct, not that it fails first (there's no red phase for pure scaffolding).

- [ ] **Step 5: Run `scripts/lint.sh` and fix anything it flags**

Run: `cd external/robocol && scripts/lint.sh`
Expected: `All checks passed.`

- [ ] **Step 6: Commit**

```bash
cd external/robocol
git add Cargo.toml ds_agent_ipc
git commit -m "Add ds_agent_ipc: shared socket path and line framing"
```

---

### Task 2: `ds_agentd` state cache — `DaemonState`

The daemon needs an in-memory snapshot of everything the robot has told it, updated as `robocol::Event`s arrive, independent of any socket or client — this is what makes `status` instant and what `init`/`run`/`config`/`activate-config`/`delete-config` validate opmode/config names against.

**Files:**
- Create: `external/robocol/ds_agentd/Cargo.toml`
- Create: `external/robocol/ds_agentd/src/main.rs` (placeholder `fn main() {}` for now — filled in Task 4)
- Create: `external/robocol/ds_agentd/src/state.rs`
- Modify: `external/robocol/Cargo.toml:4` (add `"ds_agentd"`)

**Interfaces:**
- Consumes: `robocol::client::Event`, `robocol::cmd::{OpModeMeta, ConfigMeta, parse_config_list}`, `robocol::types::RobotState`, `robocol::packets::Telemetry`.
- Produces: `pub struct DaemonState`, `DaemonState::new() -> Self`, `DaemonState::apply_event(&mut self, event: &Event)`, `DaemonState::find_config(&self, name: &str) -> Option<ConfigMeta>`, `DaemonState::find_opmode(&self, name: &str) -> bool`, `DaemonState::to_json(&self) -> serde_json::Value`. Fields `connected: bool` and `last_inited: Option<String>` are read directly by `request.rs` in Task 4.

- [ ] **Step 1: Create the crate manifest**

```toml
# external/robocol/ds_agentd/Cargo.toml
[package]
name = "ds_agentd"
version = "0.1.0"
edition = "2024"
license = "MIT"
description = "Headless daemon holding one persistent robocol connection for ds_agent"

[[bin]]
name = "ds_agentd"
path = "src/main.rs"

[dependencies]
robocol = { path = "../robocol" }
ds_agent_ipc = { path = "../ds_agent_ipc" }
serde_json = "1"
```

- [ ] **Step 2: Add to the workspace and stub `main.rs`**

```toml
# external/robocol/Cargo.toml
members = ["robocol", "fake_rc", "ds_cli", "capture/decode", "ds_agent_ipc", "ds_agentd"]
```

```rust
// external/robocol/ds_agentd/src/main.rs
mod state;

fn main() {}
```

- [ ] **Step 3: Write the failing tests**

```rust
// external/robocol/ds_agentd/src/state.rs
//! In-memory cache of everything the robot controller has told us, built
//! from the `robocol::Event` stream. Pure data — no sockets, no threads —
//! so `status` can answer instantly and name-lookups (opmode/config) don't
//! need to round-trip the robot.

use std::collections::HashMap;

use robocol::client::Event;
use robocol::cmd::{ConfigMeta, OpModeMeta, parse_config_list};
use robocol::packets::Telemetry;
use robocol::types::RobotState;

pub struct DaemonState {
    pub connected: bool,
    pub peer: Option<String>,
    pub robot_state: Option<RobotState>,
    pub opmodes: Vec<OpModeMeta>,
    /// Name most recently confirmed by `Event::OpModeInited`, so `run` with
    /// no argument can fall back to it the way `ds_cli`'s REPL session does.
    pub last_inited: Option<String>,
    pub active_config: Option<String>,
    pub configs: Vec<ConfigMeta>,
    pub device_types: Option<String>,
    pub last_scan: Option<String>,
    /// Most recent `CMD_DISCOVER_LYNX_MODULES_RESP` payload. Not keyed by
    /// serial: `Event::LynxModules` only carries the RC's raw response, not
    /// the serial it was requested for, so per-serial caching isn't possible
    /// from this event alone — the `lynx-modules` command itself still
    /// returns the right answer, via a fresh wait on this event, per call.
    pub last_lynx_modules: Option<String>,
    pub telemetry: HashMap<String, Telemetry>,
}

impl DaemonState {
    pub fn new() -> Self {
        DaemonState {
            connected: false,
            peer: None,
            robot_state: None,
            opmodes: Vec::new(),
            last_inited: None,
            active_config: None,
            configs: Vec::new(),
            device_types: None,
            last_scan: None,
            last_lynx_modules: None,
            telemetry: HashMap::new(),
        }
    }

    pub fn apply_event(&mut self, event: &Event) {
        match event {
            Event::Connected { peer } => {
                self.connected = true;
                self.peer = Some(peer.to_string());
            }
            Event::Disconnected => {
                self.connected = false;
                self.peer = None;
                self.robot_state = None;
            }
            Event::RobotState(state) => self.robot_state = Some(*state),
            Event::OpModeList(list) => self.opmodes = list.clone(),
            Event::OpModeInited(name) => self.last_inited = Some(name.clone()),
            Event::ActiveConfiguration(extra) => self.active_config = Some(extra.clone()),
            Event::ConfigurationList(extra) => self.configs = parse_config_list(extra),
            Event::UserDeviceList(extra) => self.device_types = Some(extra.clone()),
            Event::ScanResult(extra) => self.last_scan = Some(extra.clone()),
            Event::LynxModules(extra) => self.last_lynx_modules = Some(extra.clone()),
            Event::Telemetry(t) => {
                self.telemetry.insert(t.tag.clone(), t.clone());
            }
            _ => {}
        }
    }

    pub fn find_config(&self, name: &str) -> Option<ConfigMeta> {
        self.configs.iter().find(|c| c.name == name).cloned()
    }

    pub fn find_opmode(&self, name: &str) -> bool {
        self.opmodes.iter().any(|m| m.name == name)
    }

    pub fn to_json(&self) -> serde_json::Value {
        let opmodes: Vec<serde_json::Value> = self
            .opmodes
            .iter()
            .map(|m| serde_json::json!({"name": m.name, "flavor": m.flavor, "group": m.group}))
            .collect();
        let telemetry: serde_json::Map<String, serde_json::Value> = self
            .telemetry
            .iter()
            .map(|(tag, t)| {
                let strings: serde_json::Map<String, serde_json::Value> = t
                    .strings
                    .iter()
                    .map(|(k, v)| (k.clone(), serde_json::Value::String(v.clone())))
                    .collect();
                let numbers: serde_json::Map<String, serde_json::Value> = t
                    .numbers
                    .iter()
                    .map(|(k, v)| (k.clone(), serde_json::json!(v)))
                    .collect();
                (
                    tag.clone(),
                    serde_json::json!({"strings": strings, "numbers": numbers}),
                )
            })
            .collect();
        serde_json::json!({
            "ok": true,
            "connected": self.connected,
            "peer": self.peer,
            "robot_state": self.robot_state.map(|s| format!("{s:?}")),
            "opmodes": opmodes,
            "last_inited": self.last_inited,
            "active_config": self.active_config,
            "configs": self.configs,
            "device_types": self.device_types,
            "last_scan": self.last_scan,
            "last_lynx_modules": self.last_lynx_modules,
            "telemetry": telemetry,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::SocketAddr;

    #[test]
    fn starts_disconnected_with_empty_caches() {
        let state = DaemonState::new();
        assert!(!state.connected);
        assert!(state.opmodes.is_empty());
        assert!(state.find_config("anything").is_none());
        assert!(!state.find_opmode("anything"));
    }

    #[test]
    fn connected_then_disconnected_clears_robot_state() {
        let mut state = DaemonState::new();
        let peer: SocketAddr = "127.0.0.1:20884".parse().unwrap();
        state.apply_event(&Event::Connected { peer });
        state.apply_event(&Event::RobotState(RobotState::Running));
        assert!(state.connected);
        assert_eq!(state.robot_state, Some(RobotState::Running));

        state.apply_event(&Event::Disconnected);
        assert!(!state.connected);
        assert_eq!(state.robot_state, None);
        assert_eq!(state.peer, None);
    }

    #[test]
    fn opmode_list_populates_find_opmode() {
        let mut state = DaemonState::new();
        state.apply_event(&Event::OpModeList(vec![OpModeMeta {
            name: "Duo (TeleOp)".into(),
            flavor: "TELEOP".into(),
            group: "drive".into(),
        }]));
        assert!(state.find_opmode("Duo (TeleOp)"));
        assert!(!state.find_opmode("Nonexistent"));
    }

    #[test]
    fn opmode_inited_sets_last_inited() {
        let mut state = DaemonState::new();
        state.apply_event(&Event::OpModeInited("Duo (TeleOp)".into()));
        assert_eq!(state.last_inited.as_deref(), Some("Duo (TeleOp)"));
    }

    #[test]
    fn configuration_list_populates_find_config() {
        let mut state = DaemonState::new();
        let json = r#"[{"isDirty":false,"location":"Local","name":"my_config","resourceId":1}]"#;
        state.apply_event(&Event::ConfigurationList(json.to_string()));
        let meta = state.find_config("my_config").expect("config found");
        assert_eq!(meta.location, "Local");
        assert_eq!(meta.resource_id, 1);
    }

    #[test]
    fn telemetry_keeps_latest_per_tag() {
        let mut state = DaemonState::new();
        let mut first = Telemetry::default();
        first.tag = "auto".into();
        first.strings.push(("phase".into(), "start".into()));
        state.apply_event(&Event::Telemetry(first));

        let mut second = Telemetry::default();
        second.tag = "auto".into();
        second.strings.push(("phase".into(), "end".into()));
        state.apply_event(&Event::Telemetry(second));

        assert_eq!(state.telemetry.len(), 1);
        assert_eq!(state.telemetry["auto"].strings[0].1, "end");
    }

    #[test]
    fn to_json_reports_ok_true_and_connection_state() {
        let state = DaemonState::new();
        let json = state.to_json();
        assert_eq!(json["ok"], true);
        assert_eq!(json["connected"], false);
        assert!(json["opmodes"].as_array().unwrap().is_empty());
    }
}
```

- [ ] **Step 4: Wire the module into `main.rs` and run the tests**

`main.rs` already has `mod state;` from Step 2.

Run: `cd external/robocol && cargo test -p ds_agentd`
Expected: all `state::tests::*` pass. (`Telemetry` needs `Default` — confirm via `cargo doc -p robocol --no-deps --open` or by checking `external/robocol/robocol/src/packets/telemetry.rs`; if a field access differs from what's shown above, fix the test to match the real struct rather than the plan.)

- [ ] **Step 5: Lint and commit**

```bash
cd external/robocol
scripts/lint.sh
git add Cargo.toml ds_agentd
git commit -m "Add ds_agentd DaemonState: event-driven cache of robot status"
```

---

### Task 3: `ds_agentd` waiters — request/response correlation and watch fan-out

Two independent pub/sub needs sit on top of the same `Event` stream: (1) a request/response command like `list` needs to wait for exactly the next matching event and then stop waiting, (2) `watch` needs every subscriber to receive every event until it disconnects. Both are pure `Vec`-of-channels bookkeeping — no sockets — so they're fully unit-testable here, before `RobocolClient` enters the picture in Task 4.

**Files:**
- Create: `external/robocol/ds_agentd/src/waiters.rs`
- Modify: `external/robocol/ds_agentd/src/main.rs` (add `mod waiters;`)

**Interfaces:**
- Consumes: `robocol::client::Event`.
- Produces: `pub enum WaiterKind { OpModeList, OpModeInited, OpModeRunning, ActiveConfiguration, ConfigurationList, Configuration, UserDeviceList, ScanResult, LynxModules }`, `pub fn waiter_kind_of(event: &Event) -> Option<WaiterKind>`, `pub struct WaiterRegistry`, `WaiterRegistry::new() -> Self`, `WaiterRegistry::register(&mut self, kind: WaiterKind) -> std::sync::mpsc::Receiver<Event>`, `WaiterRegistry::resolve(&mut self, event: &Event)`, `pub struct Subscribers`, `Subscribers::new() -> Self`, `Subscribers::subscribe(&mut self) -> std::sync::mpsc::Receiver<Event>`, `Subscribers::broadcast(&mut self, event: &Event)`. Task 4's `main.rs` wraps both in `Arc<Mutex<_>>`.

- [ ] **Step 1: Write the failing tests**

```rust
// external/robocol/ds_agentd/src/waiters.rs
//! Two independent fan-out mechanisms sitting on top of the same
//! `robocol::Event` stream: `WaiterRegistry` resolves exactly one
//! request/response call per registration and then forgets it;
//! `Subscribers` keeps broadcasting to every `watch` connection until it
//! disconnects.

use std::sync::mpsc::{self, Receiver, Sender};

use robocol::client::Event;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WaiterKind {
    OpModeList,
    OpModeInited,
    OpModeRunning,
    ActiveConfiguration,
    ConfigurationList,
    Configuration,
    UserDeviceList,
    ScanResult,
    LynxModules,
}

pub fn waiter_kind_of(event: &Event) -> Option<WaiterKind> {
    match event {
        Event::OpModeList(_) => Some(WaiterKind::OpModeList),
        Event::OpModeInited(_) => Some(WaiterKind::OpModeInited),
        Event::OpModeRunning(_) => Some(WaiterKind::OpModeRunning),
        Event::ActiveConfiguration(_) => Some(WaiterKind::ActiveConfiguration),
        Event::ConfigurationList(_) => Some(WaiterKind::ConfigurationList),
        Event::Configuration(_) => Some(WaiterKind::Configuration),
        Event::UserDeviceList(_) => Some(WaiterKind::UserDeviceList),
        Event::ScanResult(_) => Some(WaiterKind::ScanResult),
        Event::LynxModules(_) => Some(WaiterKind::LynxModules),
        _ => None,
    }
}

pub struct WaiterRegistry {
    waiters: Vec<(WaiterKind, Sender<Event>)>,
}

impl WaiterRegistry {
    pub fn new() -> Self {
        WaiterRegistry { waiters: Vec::new() }
    }

    pub fn register(&mut self, kind: WaiterKind) -> Receiver<Event> {
        let (tx, rx) = mpsc::channel();
        self.waiters.push((kind, tx));
        rx
    }

    /// Delivers `event` to every waiter registered for its kind, then drops
    /// them — each registration is resolved (or forgotten, on send failure)
    /// exactly once. Waiters of other kinds are left untouched.
    pub fn resolve(&mut self, event: &Event) {
        let Some(kind) = waiter_kind_of(event) else {
            return;
        };
        self.waiters.retain(|(k, tx)| {
            if *k == kind {
                let _ = tx.send(event.clone());
                false
            } else {
                true
            }
        });
    }
}

pub struct Subscribers {
    list: Vec<Sender<Event>>,
}

impl Subscribers {
    pub fn new() -> Self {
        Subscribers { list: Vec::new() }
    }

    pub fn subscribe(&mut self) -> Receiver<Event> {
        let (tx, rx) = mpsc::channel();
        self.list.push(tx);
        rx
    }

    /// Sends `event` to every live subscriber, dropping any whose receiver
    /// has gone away (their `watch` connection closed).
    pub fn broadcast(&mut self, event: &Event) {
        self.list.retain(|tx| tx.send(event.clone()).is_ok());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolve_delivers_to_matching_kind_only() {
        let mut registry = WaiterRegistry::new();
        let opmode_rx = registry.register(WaiterKind::OpModeList);
        let config_rx = registry.register(WaiterKind::ActiveConfiguration);

        registry.resolve(&Event::OpModeList(vec![]));

        assert!(opmode_rx.try_recv().is_ok());
        assert!(config_rx.try_recv().is_err());
    }

    #[test]
    fn resolve_forgets_waiter_after_one_delivery() {
        let mut registry = WaiterRegistry::new();
        let rx = registry.register(WaiterKind::ScanResult);

        registry.resolve(&Event::ScanResult("first".into()));
        registry.resolve(&Event::ScanResult("second".into()));

        assert_eq!(rx.try_recv().unwrap(), Event::ScanResult("first".into()));
        assert!(rx.try_recv().is_err());
    }

    #[test]
    fn resolve_ignores_events_with_no_waiter_kind() {
        let mut registry = WaiterRegistry::new();
        let rx = registry.register(WaiterKind::OpModeList);
        registry.resolve(&Event::Disconnected);
        assert!(rx.try_recv().is_err());
    }

    #[test]
    fn dropped_receiver_is_pruned_on_next_matching_event() {
        let mut registry = WaiterRegistry::new();
        drop(registry.register(WaiterKind::ScanResult));
        // Resolving with a dropped receiver must not panic, and the dead
        // entry must be gone afterward (checked indirectly: a second
        // resolve with a fresh waiter only sees its own event).
        registry.resolve(&Event::ScanResult("ignored".into()));
        let rx = registry.register(WaiterKind::ScanResult);
        registry.resolve(&Event::ScanResult("seen".into()));
        assert_eq!(rx.try_recv().unwrap(), Event::ScanResult("seen".into()));
    }

    #[test]
    fn broadcast_reaches_every_subscriber() {
        let mut subs = Subscribers::new();
        let a = subs.subscribe();
        let b = subs.subscribe();
        subs.broadcast(&Event::Disconnected);
        assert_eq!(a.try_recv().unwrap(), Event::Disconnected);
        assert_eq!(b.try_recv().unwrap(), Event::Disconnected);
    }

    #[test]
    fn broadcast_drops_disconnected_subscribers() {
        let mut subs = Subscribers::new();
        {
            let _rx = subs.subscribe(); // dropped immediately
        }
        let live = subs.subscribe();
        subs.broadcast(&Event::Disconnected);
        assert_eq!(live.try_recv().unwrap(), Event::Disconnected);
        assert_eq!(subs.list.len(), 1);
    }
}
```

- [ ] **Step 2: Register the module**

```rust
// external/robocol/ds_agentd/src/main.rs
mod state;
mod waiters;

fn main() {}
```

- [ ] **Step 3: Run the tests**

Run: `cd external/robocol && cargo test -p ds_agentd`
Expected: all `waiters::tests::*` pass alongside the Task 2 `state::tests::*`.

- [ ] **Step 4: Lint and commit**

```bash
cd external/robocol
scripts/lint.sh
git add ds_agentd/src/main.rs ds_agentd/src/waiters.rs
git commit -m "Add ds_agentd WaiterRegistry and Subscribers for event fan-out"
```

---

### Task 4: `ds_agentd` request dispatch — full command surface

This is the daemon's actual JSON protocol: parse a `Request` off the wire, run it against a live `RobocolClient` + `DaemonState` + `WaiterRegistry`, and produce the reply. This task also wires up `RobocolClient` for real, so it's the first point the daemon can talk to an actual (or fake) robot.

**Files:**
- Create: `external/robocol/ds_agentd/src/request.rs`
- Modify: `external/robocol/ds_agentd/src/main.rs` (add `mod request;`)

**Interfaces:**
- Consumes: `DaemonState` (Task 2), `WaiterRegistry`/`WaiterKind` (Task 3), `robocol::{RobocolClient, ClientConfig, Event}`, `robocol::packets::Gamepad`.
- Produces: `pub enum Request` (serde `Deserialize`, `#[serde(tag = "cmd", rename_all = "kebab-case")]`), `pub fn handle_request(req: Request, client: &Arc<Mutex<RobocolClient>>, state: &Arc<Mutex<DaemonState>>, waiters: &Arc<Mutex<WaiterRegistry>>, timeout: Duration) -> serde_json::Value`. Task 5 (connection handling) is the only other module that calls `handle_request` or constructs `Request` via `serde_json::from_str`.

- [ ] **Step 1: Write the failing tests**

These tests build a `DaemonState`/`WaiterRegistry` pair, spawn a thread that resolves the waiter after a short delay (simulating the robot's reply), and call `handle_request` — no real socket or `RobocolClient` involved yet for the pure-logic parts; the two tests that need a live client use `fake_rc` via `RobocolClient::start`, since `RobocolClient` has no in-process mock and starting it against an address nobody answers is itself a valid "not connected" test case.

```rust
// external/robocol/ds_agentd/src/request.rs
//! The daemon's JSON protocol: parsing one request off the wire and turning
//! it into a `robocol` client call plus a reply, using `DaemonState` for
//! instant answers (`status`) and name lookups, and `WaiterRegistry` to
//! correlate a request with the `Event` that answers it.

use std::sync::{Arc, Mutex};
use std::time::Duration;

use robocol::client::{Event, RobocolClient};
use robocol::cmd::parse_config_list;
use robocol::packets::Gamepad;
use serde::Deserialize;

use crate::state::DaemonState;
use crate::waiters::{WaiterKind, WaiterRegistry};

#[derive(Debug, Deserialize)]
#[serde(tag = "cmd", rename_all = "kebab-case")]
pub enum Request {
    Ping,
    Status,
    List,
    Init {
        name: String,
    },
    Run {
        name: Option<String>,
    },
    Stop,
    Restart,
    ActiveConfig,
    Configs,
    Config {
        name: String,
    },
    SaveConfig {
        json: String,
    },
    ActivateConfig {
        name: String,
    },
    DeleteConfig {
        name: String,
    },
    DeviceTypes,
    Scan,
    LynxModules {
        serial: String,
    },
    Gamepad {
        #[serde(default)]
        left_stick_x: Option<f32>,
        #[serde(default)]
        left_stick_y: Option<f32>,
        #[serde(default)]
        right_stick_x: Option<f32>,
        #[serde(default)]
        right_stick_y: Option<f32>,
        #[serde(default)]
        left_trigger: Option<f32>,
        #[serde(default)]
        right_trigger: Option<f32>,
        #[serde(default)]
        dpad_up: Option<bool>,
        #[serde(default)]
        dpad_down: Option<bool>,
        #[serde(default)]
        dpad_left: Option<bool>,
        #[serde(default)]
        dpad_right: Option<bool>,
        #[serde(default)]
        a: Option<bool>,
        #[serde(default)]
        b: Option<bool>,
        #[serde(default)]
        x: Option<bool>,
        #[serde(default)]
        y: Option<bool>,
        #[serde(default)]
        start: Option<bool>,
        #[serde(default)]
        back: Option<bool>,
        #[serde(default)]
        left_bumper: Option<bool>,
        #[serde(default)]
        right_bumper: Option<bool>,
        #[serde(default)]
        left_stick_button: Option<bool>,
        #[serde(default)]
        right_stick_button: Option<bool>,
        #[serde(default)]
        duration_ms: Option<u64>,
    },
    Watch {
        #[serde(default)]
        types: Option<Vec<String>>,
    },
    Shutdown,
}

fn err(code: &str, message: impl Into<String>) -> serde_json::Value {
    serde_json::json!({"ok": false, "error": code, "message": message.into()})
}

fn not_connected() -> serde_json::Value {
    err("not_connected", "robot controller not connected yet")
}

fn check_known_opmode(state: &Arc<Mutex<DaemonState>>, name: &str) -> Option<serde_json::Value> {
    let state = state.lock().expect("state mutex poisoned");
    if state.opmodes.is_empty() || state.find_opmode(name) {
        None
    } else {
        Some(err(
            "unknown_opmode",
            format!("no opmode named {name:?}; run `list` first"),
        ))
    }
}

/// Registers a waiter, fires `send` (which must issue exactly one
/// `robocol` request), and blocks up to `timeout` for the matching event.
/// Fails fast with `not_connected` rather than waiting out the timeout when
/// the daemon has never seen `Event::Connected`.
fn wait_for_event(
    waiters: &Arc<Mutex<WaiterRegistry>>,
    state: &Arc<Mutex<DaemonState>>,
    kind: WaiterKind,
    timeout: Duration,
    send: impl FnOnce(),
) -> Result<Event, serde_json::Value> {
    if !state.lock().expect("state mutex poisoned").connected {
        return Err(not_connected());
    }
    let rx = waiters.lock().expect("waiters mutex poisoned").register(kind);
    send();
    rx.recv_timeout(timeout)
        .map_err(|_| err("timeout", "robot controller did not respond in time"))
}

fn build_gamepad(
    left_stick_x: Option<f32>,
    left_stick_y: Option<f32>,
    right_stick_x: Option<f32>,
    right_stick_y: Option<f32>,
    left_trigger: Option<f32>,
    right_trigger: Option<f32>,
    dpad_up: Option<bool>,
    dpad_down: Option<bool>,
    dpad_left: Option<bool>,
    dpad_right: Option<bool>,
    a: Option<bool>,
    b: Option<bool>,
    x: Option<bool>,
    y: Option<bool>,
    start: Option<bool>,
    back: Option<bool>,
    left_bumper: Option<bool>,
    right_bumper: Option<bool>,
    left_stick_button: Option<bool>,
    right_stick_button: Option<bool>,
) -> Gamepad {
    Gamepad {
        left_stick_x: left_stick_x.unwrap_or(0.0),
        left_stick_y: left_stick_y.unwrap_or(0.0),
        right_stick_x: right_stick_x.unwrap_or(0.0),
        right_stick_y: right_stick_y.unwrap_or(0.0),
        left_trigger: left_trigger.unwrap_or(0.0),
        right_trigger: right_trigger.unwrap_or(0.0),
        dpad_up: dpad_up.unwrap_or(false),
        dpad_down: dpad_down.unwrap_or(false),
        dpad_left: dpad_left.unwrap_or(false),
        dpad_right: dpad_right.unwrap_or(false),
        a: a.unwrap_or(false),
        b: b.unwrap_or(false),
        x: x.unwrap_or(false),
        y: y.unwrap_or(false),
        start: start.unwrap_or(false),
        back: back.unwrap_or(false),
        left_bumper: left_bumper.unwrap_or(false),
        right_bumper: right_bumper.unwrap_or(false),
        left_stick_button: left_stick_button.unwrap_or(false),
        right_stick_button: right_stick_button.unwrap_or(false),
        ..Gamepad::default()
    }
}

pub fn handle_request(
    req: Request,
    client: &Arc<Mutex<RobocolClient>>,
    state: &Arc<Mutex<DaemonState>>,
    waiters: &Arc<Mutex<WaiterRegistry>>,
    timeout: Duration,
) -> serde_json::Value {
    match req {
        Request::Ping => serde_json::json!({"ok": true}),
        Request::Status => state.lock().expect("state mutex poisoned").to_json(),
        Request::List => {
            let client = client.clone();
            match wait_for_event(waiters, state, WaiterKind::OpModeList, timeout, move || {
                client.lock().expect("client mutex poisoned").request_opmode_list();
            }) {
                Ok(Event::OpModeList(list)) => serde_json::json!({
                    "ok": true,
                    "opmodes": list.iter().map(|m| serde_json::json!({
                        "name": m.name, "flavor": m.flavor, "group": m.group,
                    })).collect::<Vec<_>>(),
                }),
                Ok(_) => unreachable!("WaiterKind::OpModeList only resolves with Event::OpModeList"),
                Err(e) => e,
            }
        }
        Request::Init { name } => {
            if let Some(e) = check_known_opmode(state, &name) {
                return e;
            }
            let client = client.clone();
            let send_name = name.clone();
            match wait_for_event(waiters, state, WaiterKind::OpModeInited, timeout, move || {
                client.lock().expect("client mutex poisoned").init_opmode(&send_name);
            }) {
                Ok(Event::OpModeInited(n)) => serde_json::json!({"ok": true, "name": n}),
                Ok(_) => unreachable!("WaiterKind::OpModeInited only resolves with Event::OpModeInited"),
                Err(e) => e,
            }
        }
        Request::Run { name } => {
            let name = match name.or_else(|| state.lock().expect("state mutex poisoned").last_inited.clone()) {
                Some(n) => n,
                None => return err("bad_args", "no opmode inited; call `init <name>` first or pass a name"),
            };
            if let Some(e) = check_known_opmode(state, &name) {
                return e;
            }
            let client = client.clone();
            let send_name = name.clone();
            match wait_for_event(waiters, state, WaiterKind::OpModeRunning, timeout, move || {
                client.lock().expect("client mutex poisoned").run_opmode(&send_name);
            }) {
                Ok(Event::OpModeRunning(n)) => serde_json::json!({"ok": true, "name": n}),
                Ok(_) => unreachable!("WaiterKind::OpModeRunning only resolves with Event::OpModeRunning"),
                Err(e) => e,
            }
        }
        Request::Stop => {
            client.lock().expect("client mutex poisoned").stop_opmode();
            serde_json::json!({"ok": true})
        }
        Request::Restart => {
            client.lock().expect("client mutex poisoned").restart_robot();
            serde_json::json!({"ok": true})
        }
        Request::ActiveConfig => {
            let client = client.clone();
            match wait_for_event(waiters, state, WaiterKind::ActiveConfiguration, timeout, move || {
                client.lock().expect("client mutex poisoned").request_active_config();
            }) {
                Ok(Event::ActiveConfiguration(extra)) => serde_json::json!({"ok": true, "config": extra}),
                Ok(_) => unreachable!("WaiterKind::ActiveConfiguration only resolves with Event::ActiveConfiguration"),
                Err(e) => e,
            }
        }
        Request::Configs => {
            let client = client.clone();
            match wait_for_event(waiters, state, WaiterKind::ConfigurationList, timeout, move || {
                client.lock().expect("client mutex poisoned").request_configurations();
            }) {
                Ok(Event::ConfigurationList(extra)) => {
                    serde_json::json!({"ok": true, "configs": parse_config_list(&extra)})
                }
                Ok(_) => unreachable!("WaiterKind::ConfigurationList only resolves with Event::ConfigurationList"),
                Err(e) => e,
            }
        }
        Request::Config { name } => {
            let Some(meta) = state.lock().expect("state mutex poisoned").find_config(&name) else {
                return err("unknown_config", format!("unknown config {name:?}; run `configs` first"));
            };
            let client = client.clone();
            match wait_for_event(waiters, state, WaiterKind::Configuration, timeout, move || {
                client
                    .lock()
                    .expect("client mutex poisoned")
                    .request_particular_configuration(&meta);
            }) {
                Ok(Event::Configuration(extra)) => serde_json::json!({"ok": true, "config": extra}),
                Ok(_) => unreachable!("WaiterKind::Configuration only resolves with Event::Configuration"),
                Err(e) => e,
            }
        }
        Request::SaveConfig { json } => {
            client.lock().expect("client mutex poisoned").save_configuration(&json);
            serde_json::json!({"ok": true})
        }
        Request::ActivateConfig { name } => {
            let Some(meta) = state.lock().expect("state mutex poisoned").find_config(&name) else {
                return err("unknown_config", format!("unknown config {name:?}; run `configs` first"));
            };
            client.lock().expect("client mutex poisoned").activate_configuration(&meta);
            serde_json::json!({"ok": true})
        }
        Request::DeleteConfig { name } => {
            let Some(meta) = state.lock().expect("state mutex poisoned").find_config(&name) else {
                return err("unknown_config", format!("unknown config {name:?}; run `configs` first"));
            };
            client.lock().expect("client mutex poisoned").delete_configuration(&meta);
            serde_json::json!({"ok": true})
        }
        Request::DeviceTypes => {
            let client = client.clone();
            match wait_for_event(waiters, state, WaiterKind::UserDeviceList, timeout, move || {
                client.lock().expect("client mutex poisoned").request_user_device_types();
            }) {
                Ok(Event::UserDeviceList(extra)) => serde_json::json!({"ok": true, "device_types": extra}),
                Ok(_) => unreachable!("WaiterKind::UserDeviceList only resolves with Event::UserDeviceList"),
                Err(e) => e,
            }
        }
        Request::Scan => {
            let client = client.clone();
            match wait_for_event(waiters, state, WaiterKind::ScanResult, timeout, move || {
                client.lock().expect("client mutex poisoned").scan();
            }) {
                Ok(Event::ScanResult(extra)) => serde_json::json!({"ok": true, "scan": extra}),
                Ok(_) => unreachable!("WaiterKind::ScanResult only resolves with Event::ScanResult"),
                Err(e) => e,
            }
        }
        Request::LynxModules { serial } => {
            let client = client.clone();
            let send_serial = serial.clone();
            match wait_for_event(waiters, state, WaiterKind::LynxModules, timeout, move || {
                client
                    .lock()
                    .expect("client mutex poisoned")
                    .discover_lynx_modules(&send_serial);
            }) {
                Ok(Event::LynxModules(extra)) => {
                    serde_json::json!({"ok": true, "serial": serial, "modules": extra})
                }
                Ok(_) => unreachable!("WaiterKind::LynxModules only resolves with Event::LynxModules"),
                Err(e) => e,
            }
        }
        Request::Gamepad {
            left_stick_x,
            left_stick_y,
            right_stick_x,
            right_stick_y,
            left_trigger,
            right_trigger,
            dpad_up,
            dpad_down,
            dpad_left,
            dpad_right,
            a,
            b,
            x,
            y,
            start,
            back,
            left_bumper,
            right_bumper,
            left_stick_button,
            right_stick_button,
            duration_ms,
        } => {
            let gamepad = build_gamepad(
                left_stick_x, left_stick_y, right_stick_x, right_stick_y, left_trigger,
                right_trigger, dpad_up, dpad_down, dpad_left, dpad_right, a, b, x, y, start,
                back, left_bumper, right_bumper, left_stick_button, right_stick_button,
            );
            client.lock().expect("client mutex poisoned").send_gamepad(gamepad);
            if let Some(ms) = duration_ms {
                std::thread::sleep(Duration::from_millis(ms));
                client
                    .lock()
                    .expect("client mutex poisoned")
                    .send_gamepad(Gamepad::default());
            }
            serde_json::json!({"ok": true})
        }
        // Watch and Shutdown are handled by the connection layer (Task 5),
        // which needs the raw stream to push a live stream / exit the
        // process; they never reach this dispatcher.
        Request::Watch { .. } | Request::Shutdown => {
            unreachable!("Watch and Shutdown are intercepted before handle_request is called")
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::SocketAddr;
    use std::sync::mpsc;

    fn deps() -> (Arc<Mutex<DaemonState>>, Arc<Mutex<WaiterRegistry>>) {
        (
            Arc::new(Mutex::new(DaemonState::new())),
            Arc::new(Mutex::new(WaiterRegistry::new())),
        )
    }

    fn unreachable_client() -> Arc<Mutex<RobocolClient>> {
        // Binds a real socket but points at an address nothing answers, so
        // it never emits Event::Connected — exactly the "not connected" case.
        let mut config = robocol::ClientConfig::default();
        config.bind_port = 0;
        config.peer_addrs = vec!["127.0.0.1".parse().unwrap()];
        config.peer_port = 1; // nothing listens on port 1
        let (client, _events) = RobocolClient::start(config).expect("bind UDP socket");
        Arc::new(Mutex::new(client))
    }

    #[test]
    fn status_answers_without_touching_the_client_or_waiters() {
        let (state, waiters) = deps();
        let client = unreachable_client();
        let reply = handle_request(Request::Status, &client, &state, &waiters, Duration::from_millis(50));
        assert_eq!(reply["ok"], true);
        assert_eq!(reply["connected"], false);
    }

    #[test]
    fn list_fails_fast_with_not_connected() {
        let (state, waiters) = deps();
        let client = unreachable_client();
        let reply = handle_request(Request::List, &client, &state, &waiters, Duration::from_secs(5));
        assert_eq!(reply["ok"], false);
        assert_eq!(reply["error"], "not_connected");
    }

    #[test]
    fn init_rejects_unknown_opmode_without_waiting() {
        let (state, waiters) = deps();
        let peer: SocketAddr = "127.0.0.1:20884".parse().unwrap();
        state.lock().unwrap().apply_event(&Event::Connected { peer });
        state.lock().unwrap().apply_event(&Event::OpModeList(vec![robocol::cmd::OpModeMeta {
            name: "Duo (TeleOp)".into(),
            flavor: "TELEOP".into(),
            group: "drive".into(),
        }]));
        let client = unreachable_client();
        let reply = handle_request(
            Request::Init { name: "Nonexistent".into() },
            &client,
            &state,
            &waiters,
            Duration::from_millis(50),
        );
        assert_eq!(reply["ok"], false);
        assert_eq!(reply["error"], "unknown_opmode");
    }

    #[test]
    fn list_resolves_once_the_matching_event_arrives() {
        let (state, waiters) = deps();
        let peer: SocketAddr = "127.0.0.1:20884".parse().unwrap();
        state.lock().unwrap().apply_event(&Event::Connected { peer });
        let client = unreachable_client();

        // Simulate the robot's reply landing on the waiter registry shortly
        // after the request goes out, the way the real event-pump thread
        // would (Task 6 wires that thread up for real).
        let waiters_bg = waiters.clone();
        let (ready_tx, ready_rx) = mpsc::channel::<()>();
        std::thread::spawn(move || {
            ready_rx.recv().unwrap();
            std::thread::sleep(Duration::from_millis(20));
            waiters_bg.lock().unwrap().resolve(&Event::OpModeList(vec![robocol::cmd::OpModeMeta {
                name: "Solo (TeleOp)".into(),
                flavor: "TELEOP".into(),
                group: "drive".into(),
            }]));
        });

        // handle_request's `send` closure runs before recv_timeout blocks,
        // so signal the background thread right as we call in.
        ready_tx.send(()).unwrap();
        let reply = handle_request(Request::List, &client, &state, &waiters, Duration::from_secs(1));
        assert_eq!(reply["ok"], true);
        assert_eq!(reply["opmodes"][0]["name"], "Solo (TeleOp)");
    }

    #[test]
    fn list_times_out_when_nothing_resolves_it() {
        let (state, waiters) = deps();
        let peer: SocketAddr = "127.0.0.1:20884".parse().unwrap();
        state.lock().unwrap().apply_event(&Event::Connected { peer });
        let client = unreachable_client();
        let reply = handle_request(Request::List, &client, &state, &waiters, Duration::from_millis(50));
        assert_eq!(reply["ok"], false);
        assert_eq!(reply["error"], "timeout");
    }
}
```

Add `serde` as a dependency (needed for `#[derive(Deserialize)]`):

```toml
# external/robocol/ds_agentd/Cargo.toml — add under [dependencies]
serde = { version = "1", features = ["derive"] }
```

- [ ] **Step 2: Register the module**

```rust
// external/robocol/ds_agentd/src/main.rs
mod request;
mod state;
mod waiters;

fn main() {}
```

- [ ] **Step 3: Run the tests**

Run: `cd external/robocol && cargo test -p ds_agentd`
Expected: all `request::tests::*` pass, alongside Task 2/3's tests.

- [ ] **Step 4: Lint and commit**

```bash
cd external/robocol
scripts/lint.sh
git add ds_agentd/Cargo.toml ds_agentd/src/main.rs ds_agentd/src/request.rs
git commit -m "Add ds_agentd request dispatch for the full ds_cli command surface"
```

---

### Task 5: `ds_agentd` connection handling — sockets, `watch`, `shutdown`

Everything up to here is pure logic. This task adds the one module that touches a live `UnixStream`: parsing one request line, branching `watch` into a streaming reply and `shutdown` into a process exit, and routing everything else through `handle_request`.

**Files:**
- Create: `external/robocol/ds_agentd/src/connection.rs`
- Modify: `external/robocol/ds_agentd/src/main.rs` (add `mod connection;`)

**Interfaces:**
- Consumes: `request::{Request, handle_request}` (Task 4), `waiters::{Subscribers, WaiterRegistry}` (Task 3), `state::DaemonState` (Task 2), `ds_agent_ipc::{read_message, write_message}` (Task 1).
- Produces: `pub fn handle_connection(stream: std::os::unix::net::UnixStream, client: Arc<Mutex<RobocolClient>>, state: Arc<Mutex<DaemonState>>, waiters: Arc<Mutex<WaiterRegistry>>, subscribers: Arc<Mutex<Subscribers>>, timeout: Duration)`. Task 6's accept loop spawns one thread per connection calling this directly.

- [ ] **Step 1: Write the failing tests**

The tests here use `UnixStream::pair()` — one end plays "the daemon's side" (fed to `handle_connection`), the other plays "the CLI's side" (what a real `ds_agent` would read/write) — so no real socket file or `RobocolClient` startup is needed to prove framing, `watch` filtering, and `shutdown`.

```rust
// external/robocol/ds_agentd/src/connection.rs
//! Per-connection handling: reads one request line, and either streams
//! `watch` events, exits the process for `shutdown`, or dispatches
//! everything else through `request::handle_request` for a single reply.

use std::io::BufReader;
use std::os::unix::net::UnixStream;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use robocol::client::{Event, RobocolClient};

use crate::request::{Request, handle_request};
use crate::state::DaemonState;
use crate::waiters::{Subscribers, WaiterRegistry};

fn event_type_name(event: &Event) -> Option<&'static str> {
    match event {
        Event::Connected { .. } => Some("connected"),
        Event::Disconnected => Some("disconnected"),
        Event::RobotState(_) => Some("state"),
        Event::Telemetry(_) => Some("telemetry"),
        Event::Stacktrace(_) => Some("stacktrace"),
        Event::CommandDropped { .. } => Some("command_dropped"),
        Event::ProtocolError(_) => Some("protocol_error"),
        Event::WebcamAvailable(_) => Some("webcam_available"),
        _ => None,
    }
}

fn event_to_watch_json(event: &Event, types: Option<&[String]>) -> Option<serde_json::Value> {
    let kind = event_type_name(event)?;
    if let Some(types) = types
        && !types.iter().any(|t| t == kind)
    {
        return None;
    }
    Some(match event {
        Event::Connected { peer } => serde_json::json!({"event": kind, "peer": peer.to_string()}),
        Event::Disconnected => serde_json::json!({"event": kind}),
        Event::RobotState(s) => serde_json::json!({"event": kind, "state": format!("{s:?}")}),
        Event::Telemetry(t) => {
            let strings: serde_json::Map<String, serde_json::Value> = t
                .strings
                .iter()
                .map(|(k, v)| (k.clone(), serde_json::Value::String(v.clone())))
                .collect();
            let numbers: serde_json::Map<String, serde_json::Value> = t
                .numbers
                .iter()
                .map(|(k, v)| (k.clone(), serde_json::json!(v)))
                .collect();
            serde_json::json!({"event": kind, "tag": t.tag, "strings": strings, "numbers": numbers})
        }
        Event::Stacktrace(trace) => serde_json::json!({"event": kind, "trace": trace}),
        Event::CommandDropped { name } => serde_json::json!({"event": kind, "name": name}),
        Event::ProtocolError(message) => serde_json::json!({"event": kind, "message": message}),
        Event::WebcamAvailable(available) => serde_json::json!({"event": kind, "available": available}),
        _ => return None,
    })
}

fn run_watch(stream: &mut UnixStream, subscribers: &Arc<Mutex<Subscribers>>, types: Option<Vec<String>>) {
    let rx = subscribers.lock().expect("subscribers mutex poisoned").subscribe();
    for event in rx {
        if let Some(json) = event_to_watch_json(&event, types.as_deref())
            && ds_agent_ipc::write_message(stream, &json).is_err()
        {
            break;
        }
    }
}

pub fn handle_connection(
    mut stream: UnixStream,
    client: Arc<Mutex<RobocolClient>>,
    state: Arc<Mutex<DaemonState>>,
    waiters: Arc<Mutex<WaiterRegistry>>,
    subscribers: Arc<Mutex<Subscribers>>,
    timeout: Duration,
) {
    let reader_stream = match stream.try_clone() {
        Ok(s) => s,
        Err(_) => return,
    };
    let mut reader = BufReader::new(reader_stream);
    let Ok(Some(line)) = ds_agent_ipc::read_message(&mut reader) else {
        return;
    };
    let req: Request = match serde_json::from_str(&line) {
        Ok(r) => r,
        Err(e) => {
            let _ = ds_agent_ipc::write_message(
                &mut stream,
                &serde_json::json!({"ok": false, "error": "bad_args", "message": e.to_string()}),
            );
            return;
        }
    };
    match req {
        Request::Watch { types } => run_watch(&mut stream, &subscribers, types),
        Request::Shutdown => {
            let _ = ds_agent_ipc::write_message(&mut stream, &serde_json::json!({"ok": true}));
            std::process::exit(0);
        }
        other => {
            let reply = handle_request(other, &client, &state, &waiters, timeout);
            let _ = ds_agent_ipc::write_message(&mut stream, &reply);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::BufRead;

    fn deps() -> (
        Arc<Mutex<RobocolClient>>,
        Arc<Mutex<DaemonState>>,
        Arc<Mutex<WaiterRegistry>>,
        Arc<Mutex<Subscribers>>,
    ) {
        let mut config = robocol::ClientConfig::default();
        config.bind_port = 0;
        config.peer_port = 1;
        let (client, _events) = RobocolClient::start(config).expect("bind UDP socket");
        (
            Arc::new(Mutex::new(client)),
            Arc::new(Mutex::new(DaemonState::new())),
            Arc::new(Mutex::new(WaiterRegistry::new())),
            Arc::new(Mutex::new(Subscribers::new())),
        )
    }

    #[test]
    fn ping_round_trips_over_a_real_socket_pair() {
        let (client, state, waiters, subscribers) = deps();
        let (mut cli_side, daemon_side) = UnixStream::pair().unwrap();
        ds_agent_ipc::write_message(&mut cli_side, &serde_json::json!({"cmd": "ping"})).unwrap();
        handle_connection(daemon_side, client, state, waiters, subscribers, Duration::from_millis(50));

        let mut reader = BufReader::new(cli_side);
        let mut line = String::new();
        reader.read_line(&mut line).unwrap();
        let reply: serde_json::Value = serde_json::from_str(line.trim_end()).unwrap();
        assert_eq!(reply["ok"], true);
    }

    #[test]
    fn bad_json_yields_bad_args() {
        let (client, state, waiters, subscribers) = deps();
        let (mut cli_side, daemon_side) = UnixStream::pair().unwrap();
        cli_side.set_nonblocking(false).unwrap();
        use std::io::Write;
        cli_side.write_all(b"not json\n").unwrap();
        handle_connection(daemon_side, client, state, waiters, subscribers, Duration::from_millis(50));

        let mut reader = BufReader::new(cli_side);
        let mut line = String::new();
        reader.read_line(&mut line).unwrap();
        let reply: serde_json::Value = serde_json::from_str(line.trim_end()).unwrap();
        assert_eq!(reply["ok"], false);
        assert_eq!(reply["error"], "bad_args");
    }

    #[test]
    fn watch_streams_only_requested_types() {
        let (client, state, waiters, subscribers) = deps();
        let (mut cli_side, daemon_side) = UnixStream::pair().unwrap();
        ds_agent_ipc::write_message(
            &mut cli_side,
            &serde_json::json!({"cmd": "watch", "types": ["disconnected"]}),
        )
        .unwrap();

        let subs = subscribers.clone();
        let handle = std::thread::spawn(move || {
            handle_connection(
                daemon_side,
                client,
                state,
                waiters,
                subs,
                Duration::from_secs(1),
            );
        });

        // Give handle_connection time to subscribe before broadcasting.
        std::thread::sleep(Duration::from_millis(50));
        subscribers.lock().unwrap().broadcast(&Event::RobotState(robocol::types::RobotState::Running));
        subscribers.lock().unwrap().broadcast(&Event::Disconnected);
        drop(cli_side.try_clone().unwrap()); // keep cli_side alive for the read below

        let mut reader = BufReader::new(cli_side);
        let mut line = String::new();
        reader.read_line(&mut line).unwrap();
        let event: serde_json::Value = serde_json::from_str(line.trim_end()).unwrap();
        assert_eq!(event["event"], "disconnected");

        drop(reader); // closes the CLI side, which ends handle_connection's watch loop
        handle.join().unwrap();
    }
}
```

- [ ] **Step 2: Register the module**

```rust
// external/robocol/ds_agentd/src/main.rs
mod connection;
mod request;
mod state;
mod waiters;

fn main() {}
```

- [ ] **Step 3: Run the tests**

Run: `cd external/robocol && cargo test -p ds_agentd`
Expected: all `connection::tests::*` pass. If `watch_streams_only_requested_types` is flaky on the `std::thread::sleep` synchronization, that's acceptable for this task (it's exercised for real, deterministically, in Task 7's end-to-end test) — but first try tightening the sleep or polling `subscribers.lock().unwrap().subscribe()` count before declaring it flaky.

- [ ] **Step 4: Lint and commit**

```bash
cd external/robocol
scripts/lint.sh
git add ds_agentd/src/main.rs ds_agentd/src/connection.rs
git commit -m "Add ds_agentd connection handling: watch streaming and shutdown"
```

---

### Task 6: `ds_agentd` main — real accept loop and process lifecycle

Wires everything from Tasks 2–5 into an actual running daemon: parses `--peer`/`--peer-port`/`--bind-port`, starts `RobocolClient`, spawns the event-pump thread, binds the Unix socket (handling the stale-socket case), and accepts connections in a loop, one thread per connection.

**Files:**
- Modify: `external/robocol/ds_agentd/src/main.rs`

**Interfaces:**
- Consumes: everything from Tasks 1–5.
- Produces: a runnable `ds_agentd` binary. No other task depends on `main.rs`'s internals directly, but Task 8's end-to-end test spawns this binary as a subprocess.

- [ ] **Step 1: Replace the stub `main.rs`**

```rust
// external/robocol/ds_agentd/src/main.rs
//! Headless daemon: owns one persistent `robocol::RobocolClient` connection
//! and answers `ds_agent` over a Unix domain socket. See
//! `docs/superpowers/specs/2026-09-10-headless-driver-station-agent-design.md`
//! in the deck-station repo for the wire protocol this implements.

mod connection;
mod request;
mod state;
mod waiters;

use std::net::IpAddr;
use std::os::unix::net::{UnixListener, UnixStream};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use robocol::{ClientConfig, RobocolClient};

use connection::handle_connection;
use state::DaemonState;
use waiters::{Subscribers, WaiterRegistry};

const DEFAULT_TIMEOUT: Duration = Duration::from_secs(5);

struct Args {
    peer: Option<IpAddr>,
    peer_port: Option<u16>,
    bind_port: Option<u16>,
}

fn parse_args() -> Args {
    let mut args = Args { peer: None, peer_port: None, bind_port: None };
    let raw: Vec<String> = std::env::args().skip(1).collect();
    let mut i = 0;
    while i < raw.len() {
        match raw[i].as_str() {
            "--peer" => {
                args.peer = raw.get(i + 1).and_then(|s| s.parse().ok());
                i += 2;
            }
            "--peer-port" => {
                args.peer_port = raw.get(i + 1).and_then(|s| s.parse().ok());
                i += 2;
            }
            "--bind-port" => {
                args.bind_port = raw.get(i + 1).and_then(|s| s.parse().ok());
                i += 2;
            }
            _ => i += 1,
        }
    }
    args
}

/// Timeout for request/response commands. `DS_AGENT_TIMEOUT_MS` lets tests
/// use something far shorter than the 5s production default.
fn resolve_timeout() -> Duration {
    std::env::var("DS_AGENT_TIMEOUT_MS")
        .ok()
        .and_then(|s| s.parse().ok())
        .map(Duration::from_millis)
        .unwrap_or(DEFAULT_TIMEOUT)
}

/// Binds the daemon's Unix socket, clearing a stale one left behind by a
/// crashed previous instance. If a live daemon already owns the path, exits
/// the process immediately rather than running two daemons against one
/// robot connection.
fn bind_socket() -> UnixListener {
    let path = ds_agent_ipc::socket_path();
    match UnixListener::bind(&path) {
        Ok(listener) => listener,
        Err(_) => {
            if UnixStream::connect(&path).is_ok() {
                eprintln!("ds_agentd already running at {}", path.display());
                std::process::exit(0);
            }
            let _ = std::fs::remove_file(&path);
            UnixListener::bind(&path).expect("bind ds_agentd socket after clearing stale file")
        }
    }
}

fn main() {
    let args = parse_args();
    let mut config = ClientConfig::default();
    if let Some(peer) = args.peer {
        config.peer_addrs = vec![peer];
    }
    if let Some(port) = args.peer_port {
        config.peer_port = port;
    }
    if let Some(port) = args.bind_port {
        config.bind_port = port;
    }

    let (client, events) = RobocolClient::start(config).expect("bind UDP socket");
    let client = Arc::new(Mutex::new(client));
    let state = Arc::new(Mutex::new(DaemonState::new()));
    let waiters = Arc::new(Mutex::new(WaiterRegistry::new()));
    let subscribers = Arc::new(Mutex::new(Subscribers::new()));

    {
        let state = state.clone();
        let waiters = waiters.clone();
        let subscribers = subscribers.clone();
        std::thread::spawn(move || {
            for event in events {
                state.lock().expect("state mutex poisoned").apply_event(&event);
                waiters.lock().expect("waiters mutex poisoned").resolve(&event);
                subscribers.lock().expect("subscribers mutex poisoned").broadcast(&event);
            }
        });
    }

    let timeout = resolve_timeout();
    let listener = bind_socket();
    for incoming in listener.incoming() {
        let Ok(stream) = incoming else { continue };
        let client = client.clone();
        let state = state.clone();
        let waiters = waiters.clone();
        let subscribers = subscribers.clone();
        std::thread::spawn(move || {
            handle_connection(stream, client, state, waiters, subscribers, timeout);
        });
    }
}
```

- [ ] **Step 2: Manually verify the daemon starts and answers `ping`**

Run in one terminal: `cd external/robocol && XDG_RUNTIME_DIR=/tmp cargo run -p ds_agentd -- --peer 127.0.0.1 --peer-port 1 --bind-port 0`

Run in another: `printf '{"cmd":"ping"}\n' | XDG_RUNTIME_DIR=/tmp socat - UNIX-CONNECT:/tmp/ds_agentd.sock` (or, if `socat` isn't installed, `nc -U /tmp/ds_agentd.sock` with the same input).

Expected: `{"ok":true}` printed, and the first terminal keeps running (doesn't exit).

Stop the daemon (Ctrl+C) and confirm restarting it doesn't fail on a stale socket:

Run: `cd external/robocol && XDG_RUNTIME_DIR=/tmp cargo run -p ds_agentd -- --peer 127.0.0.1 --peer-port 1 --bind-port 0` again.
Expected: starts cleanly (the stale-socket branch in `bind_socket` removes the leftover file from the Ctrl+C'd process, since nothing answers on it anymore).

- [ ] **Step 3: Lint and commit**

```bash
cd external/robocol
scripts/lint.sh
git add ds_agentd/src/main.rs
git commit -m "Wire ds_agentd into a runnable daemon: accept loop and process lifecycle"
```

---

### Task 7: `ds_agent` CLI

The thin client: turns argv into one JSON request, connects to the daemon (auto-spawning `ds_agentd` if it isn't running), and prints the reply.

**Files:**
- Create: `external/robocol/ds_agent/Cargo.toml`
- Create: `external/robocol/ds_agent/src/main.rs`
- Modify: `external/robocol/Cargo.toml:4` (add `"ds_agent"`)

**Interfaces:**
- Consumes: `ds_agent_ipc::{socket_path, read_message, write_message}` (Task 1). Talks to `ds_agentd` purely over JSON on the wire — no Rust-level dependency on `ds_agentd`'s crate.
- Produces: a runnable `ds_agent` binary, used directly (not imported) by Task 8's end-to-end test.

- [ ] **Step 1: Create the crate manifest**

```toml
# external/robocol/ds_agent/Cargo.toml
[package]
name = "ds_agent"
version = "0.1.0"
edition = "2024"
license = "MIT"
description = "Non-interactive JSON CLI for ds_agentd, for scripting or an AI agent"

[[bin]]
name = "ds_agent"
path = "src/main.rs"

[dependencies]
ds_agent_ipc = { path = "../ds_agent_ipc" }
serde_json = "1"
```

- [ ] **Step 2: Add to the workspace**

```toml
# external/robocol/Cargo.toml
members = ["robocol", "fake_rc", "ds_cli", "capture/decode", "ds_agent_ipc", "ds_agentd", "ds_agent"]
```

- [ ] **Step 3: Write the failing tests**

The argv-to-JSON builder is pure and unit-tested directly; the socket-connecting parts of `main` are exercised by Task 8's end-to-end test instead, since they need a running daemon.

```rust
// external/robocol/ds_agent/src/main.rs
//! Non-interactive CLI for `ds_agentd`. One invocation, one JSON request,
//! one reply on stdout — see `ds_cli` for the interactive REPL this mirrors.
//!
//! ```sh
//! ds_agent list
//! ds_agent init "Duo (TeleOp)"
//! ds_agent run
//! ds_agent gamepad --left-stick-y -0.5 --duration 300ms
//! ds_agent watch --types telemetry
//! ds_agent daemon status
//! ```

use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::time::{Duration, Instant};

fn build_request(args: &[String]) -> Result<serde_json::Value, String> {
    let Some(cmd) = args.first() else {
        return Err("usage: ds_agent <command> [args]".into());
    };
    match cmd.as_str() {
        "list" => Ok(serde_json::json!({"cmd": "list"})),
        "init" => {
            let name = args.get(1).ok_or("usage: ds_agent init <name>")?;
            Ok(serde_json::json!({"cmd": "init", "name": name}))
        }
        "run" => Ok(serde_json::json!({"cmd": "run", "name": args.get(1)})),
        "stop" => Ok(serde_json::json!({"cmd": "stop"})),
        "restart" => Ok(serde_json::json!({"cmd": "restart"})),
        "active-config" => Ok(serde_json::json!({"cmd": "active-config"})),
        "configs" => Ok(serde_json::json!({"cmd": "configs"})),
        "config" => {
            let name = args.get(1).ok_or("usage: ds_agent config <name>")?;
            Ok(serde_json::json!({"cmd": "config", "name": name}))
        }
        "save-config" => {
            let json = args.get(1).ok_or("usage: ds_agent save-config <json>")?;
            Ok(serde_json::json!({"cmd": "save-config", "json": json}))
        }
        "activate-config" => {
            let name = args.get(1).ok_or("usage: ds_agent activate-config <name>")?;
            Ok(serde_json::json!({"cmd": "activate-config", "name": name}))
        }
        "delete-config" => {
            let name = args.get(1).ok_or("usage: ds_agent delete-config <name>")?;
            Ok(serde_json::json!({"cmd": "delete-config", "name": name}))
        }
        "device-types" => Ok(serde_json::json!({"cmd": "device-types"})),
        "scan" => Ok(serde_json::json!({"cmd": "scan"})),
        "lynx-modules" => {
            let serial = args.get(1).ok_or("usage: ds_agent lynx-modules <serial>")?;
            Ok(serde_json::json!({"cmd": "lynx-modules", "serial": serial}))
        }
        "gamepad" => build_gamepad_request(&args[1..]),
        "status" => Ok(serde_json::json!({"cmd": "status"})),
        "watch" => build_watch_request(&args[1..]),
        other => Err(format!("unknown command: {other}")),
    }
}

const GAMEPAD_FLOAT_FLAGS: &[&str] = &[
    "left_stick_x", "left_stick_y", "right_stick_x", "right_stick_y", "left_trigger",
    "right_trigger",
];
const GAMEPAD_BOOL_FLAGS: &[&str] = &[
    "dpad_up", "dpad_down", "dpad_left", "dpad_right", "a", "b", "x", "y", "start", "back",
    "left_bumper", "right_bumper", "left_stick_button", "right_stick_button",
];

fn parse_duration_ms(value: &str) -> Result<u64, String> {
    if let Some(ms) = value.strip_suffix("ms") {
        ms.parse().map_err(|_| format!("invalid duration: {value}"))
    } else if let Some(s) = value.strip_suffix('s') {
        s.parse::<f64>()
            .map(|secs| (secs * 1000.0) as u64)
            .map_err(|_| format!("invalid duration: {value}"))
    } else {
        value.parse().map_err(|_| format!("invalid duration: {value}"))
    }
}

fn build_gamepad_request(args: &[String]) -> Result<serde_json::Value, String> {
    let mut map = serde_json::Map::new();
    map.insert("cmd".into(), serde_json::json!("gamepad"));
    let mut i = 0;
    while i < args.len() {
        let flag = args[i]
            .strip_prefix("--")
            .ok_or_else(|| format!("expected --flag, got {}", args[i]))?;
        let key = flag.replace('-', "_");
        if key == "duration" {
            let value = args.get(i + 1).ok_or("missing value for --duration")?;
            map.insert("duration_ms".into(), serde_json::json!(parse_duration_ms(value)?));
            i += 2;
            continue;
        }
        let value = args.get(i + 1).ok_or_else(|| format!("missing value for --{flag}"))?;
        if GAMEPAD_FLOAT_FLAGS.contains(&key.as_str()) {
            let parsed: f32 = value.parse().map_err(|_| format!("--{flag} expects a number"))?;
            map.insert(key, serde_json::json!(parsed));
        } else if GAMEPAD_BOOL_FLAGS.contains(&key.as_str()) {
            let parsed: bool = value.parse().map_err(|_| format!("--{flag} expects true/false"))?;
            map.insert(key, serde_json::json!(parsed));
        } else if key == "duration_ms" {
            let parsed: u64 = value.parse().map_err(|_| format!("--{flag} expects milliseconds"))?;
            map.insert(key, serde_json::json!(parsed));
        } else {
            return Err(format!("unknown gamepad flag: --{flag}"));
        }
        i += 2;
    }
    Ok(serde_json::Value::Object(map))
}

fn build_watch_request(args: &[String]) -> Result<serde_json::Value, String> {
    let mut types: Option<Vec<String>> = None;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--types" => {
                let list = args.get(i + 1).ok_or("usage: ds_agent watch [--types a,b,c]")?;
                types = Some(list.split(',').map(str::to_string).collect());
                i += 2;
            }
            other => return Err(format!("unknown watch flag: {other}")),
        }
    }
    Ok(serde_json::json!({"cmd": "watch", "types": types}))
}

fn connect_or_spawn() -> Result<UnixStream, String> {
    let path = ds_agent_ipc::socket_path();
    if let Ok(stream) = UnixStream::connect(&path) {
        return Ok(stream);
    }
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let daemon_path = exe.with_file_name("ds_agentd");
    std::process::Command::new(&daemon_path)
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
        .map_err(|e| format!("failed to start {}: {e}", daemon_path.display()))?;

    let deadline = Instant::now() + Duration::from_secs(3);
    loop {
        if let Ok(stream) = UnixStream::connect(&path) {
            return Ok(stream);
        }
        if Instant::now() >= deadline {
            return Err("ds_agentd did not become ready in time".into());
        }
        std::thread::sleep(Duration::from_millis(100));
    }
}

fn run_daemon_subcommand(args: &[String]) -> i32 {
    let path = ds_agent_ipc::socket_path();
    match args.first().map(String::as_str) {
        Some("status") => match UnixStream::connect(&path) {
            Ok(mut stream) => {
                let _ = ds_agent_ipc::write_message(&mut stream, &serde_json::json!({"cmd": "status"}));
                let mut reader = BufReader::new(stream);
                match ds_agent_ipc::read_message(&mut reader) {
                    Ok(Some(line)) => {
                        println!("{line}");
                        0
                    }
                    _ => {
                        println!(r#"{{"ok":false,"error":"daemon_unreachable"}}"#);
                        1
                    }
                }
            }
            Err(_) => {
                println!(r#"{{"ok":true,"running":false}}"#);
                0
            }
        },
        Some("stop") => match UnixStream::connect(&path) {
            Ok(mut stream) => {
                let _ = ds_agent_ipc::write_message(&mut stream, &serde_json::json!({"cmd": "shutdown"}));
                println!(r#"{{"ok":true}}"#);
                0
            }
            Err(_) => {
                println!(r#"{{"ok":true,"running":false}}"#);
                0
            }
        },
        _ => {
            eprintln!("usage: ds_agent daemon <status|stop>");
            2
        }
    }
}

fn main() {
    let raw_args: Vec<String> = std::env::args().skip(1).collect();
    if raw_args.first().map(String::as_str) == Some("daemon") {
        std::process::exit(run_daemon_subcommand(&raw_args[1..]));
    }

    let request = match build_request(&raw_args) {
        Ok(r) => r,
        Err(msg) => {
            eprintln!("{msg}");
            std::process::exit(2);
        }
    };
    let is_watch = request["cmd"] == "watch";

    let mut stream = match connect_or_spawn() {
        Ok(s) => s,
        Err(msg) => {
            println!(r#"{{"ok":false,"error":"daemon_unreachable","message":{msg:?}}}"#);
            std::process::exit(1);
        }
    };
    if ds_agent_ipc::write_message(&mut stream, &request).is_err() {
        eprintln!("failed to write to ds_agentd");
        std::process::exit(1);
    }

    let mut reader = BufReader::new(stream.try_clone().expect("clone stream"));
    if is_watch {
        loop {
            match ds_agent_ipc::read_message(&mut reader) {
                Ok(Some(line)) => println!("{line}"),
                _ => break,
            }
        }
        return;
    }
    match ds_agent_ipc::read_message(&mut reader) {
        Ok(Some(line)) => {
            println!("{line}");
            let ok = serde_json::from_str::<serde_json::Value>(&line)
                .map(|v| v["ok"] == true)
                .unwrap_or(false);
            std::process::exit(if ok { 0 } else { 1 });
        }
        _ => {
            eprintln!("no response from ds_agentd");
            std::process::exit(1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn list_needs_no_arguments() {
        let req = build_request(&["list".to_string()]).unwrap();
        assert_eq!(req, serde_json::json!({"cmd": "list"}));
    }

    #[test]
    fn init_requires_a_name() {
        assert!(build_request(&["init".to_string()]).is_err());
        let req = build_request(&["init".to_string(), "Duo (TeleOp)".to_string()]).unwrap();
        assert_eq!(req, serde_json::json!({"cmd": "init", "name": "Duo (TeleOp)"}));
    }

    #[test]
    fn run_without_a_name_sends_null() {
        let req = build_request(&["run".to_string()]).unwrap();
        assert_eq!(req, serde_json::json!({"cmd": "run", "name": null}));
    }

    #[test]
    fn unknown_command_is_an_error() {
        assert!(build_request(&["not-a-command".to_string()]).is_err());
    }

    #[test]
    fn gamepad_parses_floats_bools_and_duration() {
        let args: Vec<String> = ["gamepad", "--left-stick-y", "-0.5", "--a", "true", "--duration", "300ms"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        let req = build_request(&args).unwrap();
        assert_eq!(req["cmd"], "gamepad");
        assert_eq!(req["left_stick_y"], -0.5);
        assert_eq!(req["a"], true);
        assert_eq!(req["duration_ms"], 300);
    }

    #[test]
    fn gamepad_rejects_unknown_flags() {
        let args: Vec<String> = ["gamepad", "--not-a-flag", "1"].iter().map(|s| s.to_string()).collect();
        assert!(build_request(&args).is_err());
    }

    #[test]
    fn watch_parses_comma_separated_types() {
        let args: Vec<String> = ["watch", "--types", "telemetry,disconnected"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        let req = build_request(&args).unwrap();
        assert_eq!(req["types"], serde_json::json!(["telemetry", "disconnected"]));
    }

    #[test]
    fn watch_with_no_flags_sends_null_types() {
        let req = build_request(&["watch".to_string()]).unwrap();
        assert_eq!(req["types"], serde_json::Value::Null);
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `cd external/robocol && cargo test -p ds_agent`
Expected: all tests in `main.rs` pass.

- [ ] **Step 5: Lint and commit**

```bash
cd external/robocol
scripts/lint.sh
git add Cargo.toml ds_agent
git commit -m "Add ds_agent: non-interactive JSON CLI for ds_agentd"
```

---

### Task 8: End-to-end integration test against `fake_rc`

Proves the full stack — `ds_agent` argv parsing, socket auto-spawn, `ds_agentd`'s accept loop, real `RobocolClient` traffic, and `fake_rc` on the other end — the same way a human would exercise it with `ds_cli`, but scripted and run in CI.

**Files:**
- Create: `external/robocol/ds_agentd/tests/end_to_end.rs`

**Interfaces:**
- Consumes: the built `ds_agentd` and `ds_agent` binaries (via `env!("CARGO_BIN_EXE_ds_agentd")` / a path Cargo makes available cross-crate — see note in Step 1) and the built `fake_rc` binary.
- Produces: nothing consumed by other tasks — this is the final proof the plan works end to end.

- [ ] **Step 1: Add dev-dependencies needed to locate the sibling binaries**

Cargo only exposes `CARGO_BIN_EXE_<name>` for binaries in the *same* crate as the test. Since `ds_agent` and `fake_rc` are separate crates, add them as dev-dependencies of `ds_agentd` purely so Cargo builds them first and the test can find them by fixed relative path under the shared `target/` directory.

```toml
# external/robocol/ds_agentd/Cargo.toml — add a new section
[dev-dependencies]
ds_agent = { path = "../ds_agent" }
fake_rc = { path = "../fake_rc" }
```

- [ ] **Step 2: Write the test**

```rust
// external/robocol/ds_agentd/tests/end_to_end.rs
//! Drives the full `ds_agent` -> `ds_agentd` -> `fake_rc` stack the way a
//! human would drive `ds_cli` -> a real Control Hub, but scripted.

use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

struct ChildGuard(Child);
impl Drop for ChildGuard {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

fn bin_path(name: &str) -> PathBuf {
    // CARGO_BIN_EXE_ds_agentd is set for this crate's own binary; sibling
    // binaries built as dev-dependencies land in the same target dir, one
    // level up from ds_agentd's own exe path.
    let mut path = PathBuf::from(env!("CARGO_BIN_EXE_ds_agentd"));
    path.pop();
    path.push(name);
    path
}

fn run_agent(socket_dir: &std::path::Path, args: &[&str]) -> serde_json::Value {
    let output = Command::new(bin_path("ds_agent"))
        .args(args)
        .env("XDG_RUNTIME_DIR", socket_dir)
        .output()
        .expect("run ds_agent");
    let stdout = String::from_utf8_lossy(&output.stdout);
    serde_json::from_str(stdout.trim()).unwrap_or_else(|e| {
        panic!("ds_agent {args:?} did not print JSON: {e}\nstdout: {stdout}\nstderr: {}", String::from_utf8_lossy(&output.stderr))
    })
}

#[test]
fn drives_an_opmode_and_watches_telemetry_against_fake_rc() {
    let tmp = tempdir();
    let fake_rc_port: u16 = 20950;

    let mut fake_rc = ChildGuard(
        Command::new(bin_path("fake_rc"))
            .arg(fake_rc_port.to_string())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .expect("start fake_rc"),
    );

    let mut daemon = ChildGuard(
        Command::new(bin_path("ds_agentd"))
            .args(["--peer", "127.0.0.1", "--peer-port", &fake_rc_port.to_string(), "--bind-port", "0"])
            .env("XDG_RUNTIME_DIR", &tmp)
            .env("DS_AGENT_TIMEOUT_MS", "2000")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .expect("start ds_agentd"),
    );

    // Wait for the daemon's socket to exist before sending anything.
    let socket_path = tmp.join("ds_agentd.sock");
    let deadline = Instant::now() + Duration::from_secs(3);
    while !socket_path.exists() {
        assert!(Instant::now() < deadline, "ds_agentd socket never appeared");
        std::thread::sleep(Duration::from_millis(50));
    }

    // Wait for the daemon to actually connect to fake_rc (discovery + a
    // couple of heartbeats) before issuing commands that depend on it.
    let deadline = Instant::now() + Duration::from_secs(3);
    loop {
        let status = run_agent(&tmp, &["status"]);
        if status["connected"] == true {
            break;
        }
        assert!(Instant::now() < deadline, "ds_agentd never connected to fake_rc");
        std::thread::sleep(Duration::from_millis(100));
    }

    let list = run_agent(&tmp, &["list"]);
    assert_eq!(list["ok"], true);
    let opmodes = list["opmodes"].as_array().expect("opmodes array");
    assert!(opmodes.iter().any(|m| m["name"] == "Duo (TeleOp)"));

    let init = run_agent(&tmp, &["init", "Duo (TeleOp)"]);
    assert_eq!(init["ok"], true);
    assert_eq!(init["name"], "Duo (TeleOp)");

    let run = run_agent(&tmp, &["run"]); // no name: falls back to last_inited
    assert_eq!(run["ok"], true);
    assert_eq!(run["name"], "Duo (TeleOp)");

    let stop = run_agent(&tmp, &["stop"]);
    assert_eq!(stop["ok"], true);

    // Watch: fake_rc streams telemetry at 10 Hz, so a short-lived watch
    // process should see at least one line before it's killed.
    let mut watch = Command::new(bin_path("ds_agent"))
        .args(["watch", "--types", "telemetry"])
        .env("XDG_RUNTIME_DIR", &tmp)
        .stdout(Stdio::piped())
        .spawn()
        .expect("start ds_agent watch");
    let stdout = watch.stdout.take().expect("watch stdout");
    let mut reader = BufReader::new(stdout);
    let mut line = String::new();
    reader.read_line(&mut line).expect("read a telemetry line");
    let event: serde_json::Value = serde_json::from_str(line.trim_end()).expect("watch line is JSON");
    assert_eq!(event["event"], "telemetry");
    let _ = watch.kill();
    let _ = watch.wait();

    // Explicit teardown via `daemon stop`, ahead of ChildGuard's Drop kill,
    // proves the shutdown command itself works.
    let stopped = run_agent(&tmp, &["daemon", "stop"]);
    assert_eq!(stopped["ok"], true);
    std::thread::sleep(Duration::from_millis(200));
    let _ = daemon.0.try_wait();
    let _ = fake_rc.0.kill();
}

fn tempdir() -> PathBuf {
    let dir = std::env::temp_dir().join(format!("ds_agent_e2e_{}", std::process::id()));
    std::fs::create_dir_all(&dir).expect("create temp runtime dir");
    dir
}
```

- [ ] **Step 3: Run the test**

Run: `cd external/robocol && cargo test -p ds_agentd --test end_to_end`
Expected: `drives_an_opmode_and_watches_telemetry_against_fake_rc` passes. If `fake_rc`'s telemetry tag/opmode list differs from what's assumed above (check `external/robocol/fake_rc/src/main.rs`'s `OPMODES` constant and its telemetry-emitting code if this fails), adjust the assertions to match `fake_rc`'s actual behavior rather than changing `fake_rc` itself.

- [ ] **Step 4: Run the full workspace lint one more time**

Run: `cd external/robocol && scripts/lint.sh`
Expected: `All checks passed.` — this is the same command CI runs, so a clean pass here means the PR (Task 9) will be green.

- [ ] **Step 5: Commit**

```bash
cd external/robocol
git add ds_agentd/Cargo.toml ds_agentd/tests
git commit -m "Add end-to-end test driving ds_agent/ds_agentd against fake_rc"
```

---

### Task 9: Document `ds_agent` for the people who'll reach for it

The design's rollout section calls for documenting usage where a user would actually look: deck-station's own README, since that's "the app you run to drive the robot" and this is the headless alternative to it.

**Files:**
- Modify: `external/robocol/ds_agent/src/main.rs` (already has doc comments with usage examples from Task 7 — no change needed here)
- Modify: `/Users/vlad./Documents/GitHub/deck-station/README.md`

**Interfaces:** None — this is documentation only.

- [ ] **Step 1: Add a new section to deck-station's README**

Insert after the existing "Other computers (Windows, Linux, macOS)" section and before "Development" (check the current heading structure with `grep -n '^#' README.md` first, since line numbers may have shifted):

```markdown
## Headless: letting an agent drive

For scripting or handing control to a desktop AI agent instead of a human at
the UI, `external/robocol` ships `ds_agentd`/`ds_agent`: a small daemon that
holds the robot connection open, and a one-shot JSON CLI that talks to it.

```sh
cd external/robocol
cargo run -p ds_agent -- list
cargo run -p ds_agent -- init "Duo (TeleOp)"
cargo run -p ds_agent -- run
cargo run -p ds_agent -- watch --types telemetry
```

`ds_agent` starts `ds_agentd` automatically the first time it's needed. See
`external/robocol/ds_agent/src/main.rs`'s doc comment for the full command
list. This is Unix-only (macOS/Linux/Steam Deck) for now — no Windows named
pipe support yet.

> [!WARNING]
> Same disclaimer as the rest of this app: development/practice use only, not
> competition legal.
```

- [ ] **Step 2: Commit (in the deck-station repo, not the submodule)**

```bash
git add README.md
git commit -m "$(cat <<'EOF'
Document ds_agent for headless/agent-driven robot control

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## After this plan

Not part of this plan's tasks — flag these to the user rather than doing them automatically:

1. The `external/robocol` submodule now has local commits on top of whatever commit `deck-station` currently pins. Pushing those commits to `github.com/whitehml/robocol` (and opening a PR there) is a separate, explicit step — ask before pushing.
2. Once that's merged upstream, bump `deck-station`'s submodule pointer (`git -C external/robocol pull`, then `git add external/robocol && git commit`) and commit the doc change from Task 9 alongside it, or as a follow-up.
3. An MCP server wrapping `ds_agent` (so an MCP-aware agent gets typed tools instead of shelling out) is explicitly out of scope for this plan, per the design doc's non-goals.

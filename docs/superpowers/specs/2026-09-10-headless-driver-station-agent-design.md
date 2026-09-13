# Headless driver-station access for a desktop AI agent

Status: draft
Repo of implementation: `external/robocol` submodule (github.com/whitehml/robocol),
pinned by `deck-station`

## Motivation

Deck Station is a Godot GUI. Driving it requires a human at a gamepad/mouse.
There's no way today for a desktop AI agent (Claude Code or similar, running
on the same machine that's joined the Control Hub's WiFi) to list opmodes,
run/stop them, manage configs, or read telemetry without a person operating
the UI.

`external/robocol/ds_cli` already wraps the `robocol` client in an
interactive REPL for humans (`list`, `init <name>`, `run`, `stop`, config
commands, `scan`, gamepad pulse). This design adds a non-interactive,
JSON-in/JSON-out sibling so an agent can drive the same capability by
shelling out to a command, rather than by parsing a human REPL's prose.

## Non-goals

- Not competition legal, same disclaimer as Deck Station itself.
- No changes to the `robocol` protocol/client crate's public API beyond what's
  needed to observe events from two consumers (`ds_cli` and the new daemon).
- No webcam frame streaming through the CLI/daemon in this phase — expose
  `WebcamAvailable` in `watch` output, but not raw JPEG bytes.
- No MCP server in this phase. The CLI is designed so an MCP wrapper is a
  thin follow-on (each tool call ends up shelling out to `ds_agent` or
  talking the same IPC protocol), but building it is out of scope here.

## Architecture

Two new binaries in `external/robocol`, added as workspace members alongside
`robocol`, `fake_rc`, `ds_cli`, `capture/decode`:

- **`ds_agentd`** — daemon. Owns one persistent `RobocolClient`. Subscribes to
  its `Event` stream and maintains an in-memory snapshot (`DaemonState`):
  connection status, last `OpModeList`, last active-config string, last
  `ConfigurationList`, last telemetry per tag, last `UserDeviceList`,
  last `ScanResult`/`LynxModules` per serial. Listens on a Unix domain socket
  for line-delimited JSON requests, one connection per `ds_agent` invocation.
- **`ds_agent`** — CLI. Parses argv into one JSON request, connects to the
  daemon's socket (auto-spawning `ds_agentd` detached if the socket doesn't
  exist or is stale), sends the request, prints the JSON response to stdout,
  and exits with status 0/1 based on `ok`.

Both link directly against the `robocol` crate the same way `ds_cli` does —
`ds_agentd` is the only one that touches `RobocolClient`; `ds_agent` only
speaks the local IPC protocol.

## Socket, daemon lifecycle, single instance

- Socket path: `$XDG_RUNTIME_DIR/ds_agentd.sock` if set, else
  `/tmp/ds_agentd-$UID.sock`.
- `ds_agentd` binds the socket at startup; if bind fails because the path
  exists, it connects to it first to check for a live daemon (a one-line
  `{"cmd":"ping"}`) — if that fails, the socket is stale and gets removed and
  rebound; if it succeeds, `ds_agentd` exits immediately (another instance
  already owns it).
- `ds_agent`'s auto-spawn path: try connecting; on `ECONNREFUSED` or missing
  socket, spawn `ds_agentd` detached (own process group, stdio to
  `/dev/null`), poll the socket with backoff up to ~3s, then proceed. This
  mirrors `ds_cli`'s own discovery guesses (`config.peer_addrs` defaults to
  `192.168.43.1` / `192.168.49.1`); `ds_agentd` accepts an optional
  `--peer <addr>` the same way `ds_cli` takes an optional argv[1].
- `ds_agent daemon status` reports whether a daemon is running and its RC
  connection state; `ds_agent daemon stop` sends a shutdown request.

## IPC protocol

Newline-delimited JSON over the Unix socket, one request/response (or
request/stream) per connection.

Request: `{"cmd": "<name>", ...args}`

Response, request/response commands: a single line,
`{"ok": true, ...payload}` or `{"ok": false, "error": "<code>", "message": "<human text>"}`.

Response, `watch`: zero or more `{"event": "<type>", ...payload}` lines
followed by connection close (on `ds_agent`'s own SIGINT/exit) — no final
`ok` line, since it's a stream, not a single result.

Error codes: `daemon_unreachable`, `not_connected` (RC not connected yet),
`unknown_opmode`, `unknown_config`, `timeout` (robot didn't emit the expected
event in time), `bad_args`.

## Command surface

Full parity with `ds_cli`'s command set, each a one-shot `ds_agent <args>`:

| CLI | IPC cmd | Waits for | JSON payload |
|---|---|---|---|
| `list` | `list` | `Event::OpModeList` | `{"opmodes":[{"name","flavor","group"}]}` |
| `init <name>` | `init` | `Event::OpModeInited` | `{"name"}` |
| `run [name]` | `run` | `Event::OpModeRunning` | `{"name"}` |
| `stop` | `stop` | ack only | `{}` |
| `restart` | `restart` | ack only | `{}` |
| `active-config` | `active-config` | `Event::ActiveConfiguration` | `{"config":"<extra>"}` |
| `configs` | `configs` | `Event::ConfigurationList` | `{"configs":[ConfigMeta...]}` (via `cmd::parse_config_list`) |
| `config <name>` | `config` | `Event::Configuration` | `{"config":"<extra>"}` |
| `save-config <json>` | `save-config` | ack only | `{}` |
| `activate-config <name>` | `activate-config` | ack only | `{}` |
| `delete-config <name>` | `delete-config` | ack only | `{}` |
| `device-types` | `device-types` | `Event::UserDeviceList` | `{"deviceTypes":"<extra>"}` |
| `scan` | `scan` | `Event::ScanResult` | `{"scan":"<extra>"}` |
| `lynx-modules <serial>` | `lynx-modules` | `Event::LynxModules` | `{"serial","modules":"<extra>"}` |
| `gamepad [--left-stick-x N] ... [--duration 300ms]` | `gamepad` | ack only | `{}` |
| `status` | `status` | none (cached) | full `DaemonState` snapshot |
| `watch [--types a,b,...]` | `watch` | streams | see above |

`config`/`activate-config`/`delete-config` resolve `name` against the
daemon's cached `ConfigurationList` the same way `ds_cli`'s `find_config`
does — if the name isn't known yet, error `unknown_config` telling the agent
to run `configs` first.

`gamepad` takes any subset of `Gamepad`'s stick/trigger/button flags as
flags (default zero/false), builds one `Gamepad` packet, sends it, and if
`--duration` is given, sleeps then sends a zeroed `Gamepad` — same pulse
behavior as `ds_cli`'s hardcoded `w`, generalized to arbitrary input instead
of one fixed forward-stick shortcut.

Request/response commands default to a 5s timeout waiting for their event;
exceeding it returns `{"ok":false,"error":"timeout",...}` rather than
hanging — the daemon keeps the outstanding robocol call in flight so a late
event still updates cached state even after the CLI has given up.

## Error handling

- `ds_agent` talking to a socket that refuses every connection attempt
  (spawn failed, crashed daemon) exits 1 with `{"ok":false,"error":"daemon_unreachable"}`
  on stderr as well as stdout, so scripting either stream works.
- Commands sent before the RC has connected (`Event::Connected` never seen)
  return `not_connected` immediately instead of waiting out the full
  timeout, since nothing will arrive.
- The daemon logs to stderr (own process, redirected to a logfile under the
  same runtime dir as the socket, e.g. `ds_agentd.log`) so `ds_agent daemon status`
  or a human can tail it for anything `ds_agent`'s per-call JSON doesn't
  capture (raw event trace, panics).

## Testing

- Unit tests in `ds_agentd` for: IPC request parsing, `DaemonState` update
  from each `Event` variant, config-name resolution against cached
  `ConfigurationList`, timeout behavior on a mocked event source.
- Integration test (new, under `external/robocol`, run via the submodule's
  existing `scripts/lint.sh` / CI) that starts `fake_rc`, starts `ds_agentd`
  pointed at it, and drives a real socket client through: connect → `list` →
  `init` → `run` → `stop`, plus a `watch` call asserting at least one
  `telemetry` event line arrives — exercising the full stack the same way a
  human would with `ds_cli`, but scripted.
- No changes needed to `robocol` or `fake_rc` themselves unless the
  integration test surfaces a gap.

## Rollout

1. Implement `ds_agentd` + `ds_agent` in `external/robocol`, add to its
   workspace `Cargo.toml`, open a PR against `whitehml/robocol`.
2. Once merged upstream, bump the `external/robocol` submodule pin in
   `deck-station` (matching how `robocol_godot`'s dependency comment already
   describes: "swap to a pinned git-dep once the wire formats stabilize").
3. Document `ds_agent` usage in `deck-station`'s README or a new doc, since
   that's where a user would look for "how do I let an agent drive this."
4. MCP server wrapper: future phase, not in this spec.

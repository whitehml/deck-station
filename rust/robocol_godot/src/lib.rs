//! GDExtension bridge: exposes `robocol::RobocolClient` to Godot as a
//! `RobocolBridge` node whose signal surface matches the `RobotClient`
//! singleton in `godot/autoloads/robot_client.gd`, so the UI talks to one
//! stable contract.
//!
//! Threading model: the robocol client runs its own thread; this node
//! drains its event channel in `process()` on the main thread, so all
//! signal emission is main-thread and Godot-safe.

#![cfg_attr(not(test), warn(clippy::pedantic))]
#![cfg_attr(
    not(test),
    deny(
        clippy::unwrap_used,
        clippy::expect_used,
        clippy::panic,
        clippy::todo,
        clippy::unimplemented,
        clippy::unreachable,
        clippy::dbg_macro
    )
)]
#![allow(
    clippy::doc_markdown,
    clippy::cast_possible_truncation,
    clippy::cast_sign_loss,
    clippy::cast_possible_wrap,
    clippy::cast_lossless,
    clippy::needless_pass_by_value,
    clippy::too_many_lines
)]

use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{Receiver, Sender, TryRecvError};
use std::sync::Arc;
use std::time::Instant;

use godot::classes::{Image, ImageTexture, Node};
use godot::prelude::*;

use robocol::client::{ClientConfig, Event, RobocolClient};
use robocol::cmd::{self, ConfigMeta, OpModeMeta};
use robocol::packets::{Gamepad, BATTERY_LEVEL_KEY, RC_BATTERY_STATUS_KEY, SYSTEM_KEY_PREFIX};
use robocol::types::GamepadType;
use robocol::video::{self, StreamConfig, VideoEvent};

struct RobocolGodot;

#[gdextension]
unsafe impl ExtensionLibrary for RobocolGodot {}

#[derive(GodotClass)]
#[class(base=Node)]
pub struct RobocolBridge {
    base: Base<Node>,
    client: Option<RobocolClient>,
    events: Option<Receiver<Event>>,
    phase: i64,
    selected_opmode: String,
    current_opmode: String,
    run_started: Option<Instant>,
    video_tx: Option<Sender<VideoEvent>>,
    video_events: Option<Receiver<VideoEvent>>,
    video_stops: HashMap<String, Arc<AtomicBool>>,
    video_connected: HashSet<String>,
    // Latest telemetry entries per RC telemetry tag, in first-seen order. The
    // RC sends the OpMode stream and system/camera streams under distinct tags;
    // merging them (rather than letting each packet overwrite the pane) is what
    // keeps the pane from flickering between unrelated streams.
    telemetry_by_tag: Vec<(String, VarArray)>,
    telemetry_debug: bool,
}

#[godot_api]
impl INode for RobocolBridge {
    fn init(base: Base<Node>) -> Self {
        RobocolBridge {
            base,
            client: None,
            events: None,
            phase: Self::PHASE_DISCONNECTED,
            selected_opmode: String::new(),
            current_opmode: String::new(),
            run_started: None,
            video_tx: None,
            video_events: None,
            video_stops: HashMap::new(),
            video_connected: HashSet::new(),
            telemetry_by_tag: Vec::new(),
            telemetry_debug: std::env::var_os("DECK_VIDEO_DEBUG").is_some(),
        }
    }

    fn process(&mut self, _delta: f64) {
        while let Some(events) = &self.events {
            match events.try_recv() {
                Ok(event) => self.dispatch(event),
                Err(TryRecvError::Empty) => break,
                Err(TryRecvError::Disconnected) => {
                    self.events = None;
                    self.dispatch(Event::Disconnected);
                    self.signals()
                        .client_error()
                        .emit(&GString::from("client thread ended unexpectedly"));
                    break;
                }
            }
        }
        let mut frames = Vec::new();
        if let Some(video_events) = &self.video_events {
            while let Ok(ev) = video_events.try_recv() {
                frames.push(ev);
            }
        }
        for ev in frames {
            self.dispatch_video(ev);
        }
    }

    fn exit_tree(&mut self) {
        self.stop_client();
    }
}

#[godot_api]
impl RobocolBridge {
    // Sole source of truth for phase numbering
    #[constant]
    const PHASE_DISCONNECTED: i64 = 0;
    #[constant]
    const PHASE_IDLE: i64 = 1;
    #[constant]
    const PHASE_INIT: i64 = 2;
    #[constant]
    const PHASE_RUNNING: i64 = 3;

    #[signal]
    fn connection_changed(connected: bool);
    #[signal]
    fn opmode_list_changed(opmodes: VarArray);
    #[signal]
    fn phase_changed(phase: i64, opmode_name: GString);
    #[signal]
    fn telemetry_received(entries: VarArray);
    #[signal]
    fn video_frame(source: GString, texture: Gd<ImageTexture>);
    #[signal]
    fn video_stream_ended(source: GString);
    #[signal]
    fn robot_state_changed(state: i64);
    #[signal]
    fn battery_voltage_changed(volts: f64);
    #[signal]
    fn stacktrace_received(text: GString);
    #[signal]
    fn client_error(message: GString);
    #[signal]
    fn active_config_changed(config: VarDictionary);
    #[signal]
    fn configurations_changed(configs: VarArray);
    #[signal]
    fn configuration_received(xml: GString);
    #[signal]
    fn user_device_list_received(json: GString);
    #[signal]
    fn scan_result_received(json: GString);
    #[signal]
    fn lynx_modules_received(json: GString);

    /// Starts the client thread. Empty array = default Control Hub / RC
    /// phone addresses.
    #[func]
    fn start_client(&mut self, peer_addrs: PackedStringArray, bind_port: i64, peer_port: i64) {
        if self.client.is_some() {
            return;
        }
        let mut config = ClientConfig::default();
        if bind_port >= 0 {
            let Ok(p) = u16::try_from(bind_port) else {
                godot_error!("RobocolBridge: bind_port {bind_port} out of range");
                return;
            };
            config.bind_port = p;
        }
        if peer_port > 0 {
            let Ok(p) = u16::try_from(peer_port) else {
                godot_error!("RobocolBridge: peer_port {peer_port} out of range");
                return;
            };
            config.peer_port = p;
        }
        if !peer_addrs.is_empty() {
            let mut addrs = Vec::new();
            for addr in peer_addrs.as_slice() {
                let Ok(ip) = addr.to_string().parse() else {
                    godot_error!("RobocolBridge: invalid peer address {addr}");
                    return;
                };
                addrs.push(ip);
            }
            config.peer_addrs = addrs;
        }
        match RobocolClient::start(config) {
            Ok((client, events)) => {
                self.client = Some(client);
                self.events = Some(events);
            }
            Err(e) => {
                let message = format!("failed to start robocol client: {e}");
                godot_error!("RobocolBridge: {message}");
                self.signals().client_error().emit(&GString::from(&message));
            }
        }
    }

    #[func]
    fn stop_client(&mut self) {
        self.client = None;
        self.events = None;
        for stop in self.video_stops.values() {
            stop.store(true, Ordering::Relaxed);
        }
        self.video_stops.clear();
        self.video_tx = None;
        self.video_events = None;
        self.video_connected.clear();
        self.telemetry_by_tag.clear();
        if self.phase != Self::PHASE_DISCONNECTED {
            self.set_phase(Self::PHASE_DISCONNECTED, "");
            self.signals().connection_changed().emit(false);
        }
    }

    /// Starts streaming one MJPEG-over-HTTP camera source on its own thread.
    /// `url` is `http://host:port/path`. Frames arrive via `video_frame`.
    #[func]
    fn add_video_stream(&mut self, source: GString, url: GString) {
        let source = source.to_string();
        if self.video_stops.contains_key(&source) {
            godot_error!("RobocolBridge: video stream '{source}' is already running");
            return;
        }
        let Some(cfg) = StreamConfig::parse(&source, &url.to_string()) else {
            godot_error!("RobocolBridge: invalid video stream url '{url}'");
            return;
        };
        let tx = if let Some(tx) = &self.video_tx {
            tx.clone()
        } else {
            let (tx, rx) = std::sync::mpsc::channel();
            self.video_tx = Some(tx.clone());
            self.video_events = Some(rx);
            tx
        };
        let stop = Arc::new(AtomicBool::new(false));
        let thread_stop = stop.clone();
        std::thread::spawn(move || video::run_stream(cfg, tx, thread_stop));
        self.video_stops.insert(source, stop);
    }

    #[func]
    fn select_opmode(&mut self, name: GString) {
        if self.phase == Self::PHASE_IDLE {
            self.selected_opmode = name.to_string();
        }
    }

    #[func]
    fn init_opmode(&mut self) {
        if self.phase != Self::PHASE_IDLE || self.selected_opmode.is_empty() {
            return;
        }
        self.with_client(|client| client.init_opmode(&self.selected_opmode));
    }

    #[func]
    fn start_opmode(&mut self) {
        if self.phase != Self::PHASE_INIT {
            return;
        }
        self.with_client(|client| client.run_opmode(&self.current_opmode));
    }

    #[func]
    fn stop_opmode(&mut self) {
        self.with_client(RobocolClient::stop_opmode);
    }

    #[func]
    fn restart_robot(&self) {
        self.with_client(RobocolClient::restart_robot);
    }

    #[func]
    fn request_active_config(&self) {
        self.with_client(RobocolClient::request_active_config);
    }

    #[func]
    fn request_configurations(&self) {
        self.with_client(RobocolClient::request_configurations);
    }

    #[func]
    fn request_particular_configuration(&self, config: VarDictionary) {
        self.with_config_meta(&config, RobocolClient::request_particular_configuration);
    }

    /// Only takes effect once the RC restarts, which the client does
    /// automatically as soon as the RC acks the activate.
    #[func]
    fn activate_configuration(&self, config: VarDictionary) {
        self.with_config_meta(&config, RobocolClient::activate_configuration);
    }

    #[func]
    fn delete_configuration(&self, config: VarDictionary) {
        self.with_config_meta(&config, RobocolClient::delete_configuration);
    }

    #[func]
    fn save_configuration(&self, meta_json: GString, xml: GString) {
        self.with_client(|client| client.save_configuration(&format!("{meta_json};{xml}")));
    }

    #[func]
    fn request_user_device_types(&self) {
        self.with_client(RobocolClient::request_user_device_types);
    }

    /// Live hardware scan, used by the config editor to detect what's
    /// currently plugged into the hub.
    #[func]
    fn scan(&self) {
        self.with_client(RobocolClient::scan);
    }

    /// `serial` is a `LynxUsbDevice`'s USB serial number, as reported by a
    /// `scan()` result.
    #[func]
    fn discover_lynx_modules(&self, serial: GString) {
        self.with_client(|client| client.discover_lynx_modules(&serial.to_string()));
    }

    #[func]
    fn run_elapsed(&self) -> f64 {
        match (self.phase, self.run_started) {
            (Self::PHASE_RUNNING, Some(t)) => t.elapsed().as_secs_f64(),
            _ => 0.0,
        }
    }

    /// Sends one gamepad state snapshot. `user` is 1 (gamepad1) or
    /// 2 (gamepad2); `state` keys mirror the Gamepad packet field names.
    #[func]
    fn send_gamepad(&mut self, user: i64, state: VarDictionary) {
        if !(1..=2).contains(&user) {
            godot_warn!("RobocolBridge: send_gamepad user {user} out of range, clamping");
        }
        let b = |key: &str| state.get(key).is_some_and(|v| v.booleanize());
        let f = |key: &str| {
            state
                .get(key)
                .and_then(|v| v.try_to::<f64>().ok())
                .unwrap_or(0.0) as f32
        };
        self.with_client(|client| {
            client.send_gamepad(Gamepad {
                user: user.clamp(1, 2) as u8,
                gamepad_type: GamepadType::LogitechF310,
                left_stick_x: f("left_stick_x"),
                left_stick_y: f("left_stick_y"),
                right_stick_x: f("right_stick_x"),
                right_stick_y: f("right_stick_y"),
                left_trigger: f("left_trigger"),
                right_trigger: f("right_trigger"),
                dpad_up: b("dpad_up"),
                dpad_down: b("dpad_down"),
                dpad_left: b("dpad_left"),
                dpad_right: b("dpad_right"),
                a: b("a"),
                b: b("b"),
                x: b("x"),
                y: b("y"),
                guide: b("guide"),
                start: b("start"),
                back: b("back"),
                left_bumper: b("left_bumper"),
                right_bumper: b("right_bumper"),
                left_stick_button: b("left_stick_button"),
                right_stick_button: b("right_stick_button"),
                touchpad: b("touchpad"),
                ..Default::default()
            });
        });
    }
}

impl RobocolBridge {
    fn with_client(&self, f: impl FnOnce(&RobocolClient)) {
        if let Some(client) = &self.client {
            f(client);
        }
    }

    fn with_config_meta(
        &self,
        config: &VarDictionary,
        f: impl FnOnce(&RobocolClient, &ConfigMeta),
    ) {
        let Some(meta) = dict_to_config_meta(config) else {
            godot_error!("RobocolBridge: invalid config dictionary");
            return;
        };
        self.with_client(|client| f(client, &meta));
    }

    fn set_phase(&mut self, phase: i64, opmode: &str) {
        if phase == Self::PHASE_INIT && (phase != self.phase || opmode != self.current_opmode) {
            self.telemetry_by_tag.clear();
        }
        self.phase = phase;
        self.current_opmode = opmode.to_string();
        if phase == Self::PHASE_RUNNING {
            self.run_started = Some(Instant::now());
        }
        self.signals()
            .phase_changed()
            .emit(phase, &GString::from(opmode));
    }

    fn update_telemetry(&mut self, tag: &str, entries: VarArray) {
        if self.telemetry_debug && !self.telemetry_by_tag.iter().any(|(t, _)| t == tag) {
            godot_print!("telemetry: new tag {tag:?} ({} entries)", entries.len());
        }
        match self.telemetry_by_tag.iter_mut().find(|(t, _)| t == tag) {
            Some((_, slot)) => *slot = entries,
            None => self.telemetry_by_tag.push((tag.to_string(), entries)),
        }
        let mut merged = VarArray::new();
        for (_, arr) in &self.telemetry_by_tag {
            for item in arr.iter_shared() {
                merged.push(&item);
            }
        }
        self.signals().telemetry_received().emit(&merged);
    }

    fn dispatch_video(&mut self, event: VideoEvent) {
        match event {
            VideoEvent::Frame { source, jpeg } => self.emit_frame(&source, &jpeg),
            VideoEvent::Disconnected { source } => self.emit_stream_ended(&source),
        }
    }

    fn emit_frame(&mut self, source: &str, jpeg: &[u8]) {
        let mut image = Image::new_gd();
        let bytes = PackedByteArray::from(jpeg);
        if image.load_jpg_from_buffer(&bytes) != godot::global::Error::OK {
            return;
        }
        let Some(texture) = ImageTexture::create_from_image(&image) else {
            return;
        };
        self.video_connected.insert(source.to_string());
        self.signals()
            .video_frame()
            .emit(&GString::from(source), &texture);
    }

    fn emit_stream_ended(&mut self, source: &str) {
        self.video_stops.remove(source);
        if self.video_connected.remove(source) {
            self.signals()
                .video_stream_ended()
                .emit(&GString::from(source));
        }
    }

    fn dispatch(&mut self, event: Event) {
        match event {
            Event::Connected { .. } => {
                self.set_phase(Self::PHASE_IDLE, "");
                self.signals().connection_changed().emit(true);
            }
            Event::Disconnected => {
                self.set_phase(Self::PHASE_DISCONNECTED, "");
                self.signals().connection_changed().emit(false);
                self.emit_stream_ended("webcam");
                self.telemetry_by_tag.clear();
            }
            Event::OpModeList(list) => {
                let mut opmodes = VarArray::new();
                for meta in list {
                    if meta.name != cmd::DEFAULT_OP_MODE {
                        opmodes.push(&opmode_meta_to_dict(&meta).to_variant());
                    }
                }
                self.signals().opmode_list_changed().emit(&opmodes);
            }
            Event::OpModeInited(name) => {
                if name == cmd::DEFAULT_OP_MODE {
                    self.set_phase(Self::PHASE_IDLE, "");
                } else {
                    self.set_phase(Self::PHASE_INIT, &name);
                }
            }
            Event::OpModeRunning(name) => {
                if name == cmd::DEFAULT_OP_MODE {
                    self.set_phase(Self::PHASE_IDLE, "");
                } else {
                    self.set_phase(Self::PHASE_RUNNING, &name);
                }
            }
            Event::Telemetry(t) => {
                let phase_tag = if self.phase == Self::PHASE_INIT {
                    "INIT"
                } else {
                    "RUN"
                };
                let mut entries = VarArray::new();
                for (key, value) in &t.strings {
                    if key == BATTERY_LEVEL_KEY || key == RC_BATTERY_STATUS_KEY {
                        continue;
                    }
                    if key.starts_with(SYSTEM_KEY_PREFIX) {
                        entries.push(&entry(value, GString::new().to_variant(), "SYSTEM"));
                    } else {
                        entries.push(&entry(value, GString::new().to_variant(), phase_tag));
                    }
                }
                for (key, value) in &t.numbers {
                    entries.push(&entry(key, (*value as f64).to_variant(), phase_tag));
                }
                if let Some(volts) = t.battery_voltage() {
                    self.signals().battery_voltage_changed().emit(volts as f64);
                }

                if !entries.is_empty() {
                    self.update_telemetry(&t.tag, entries);
                }
            }
            Event::RobotState(state) => {
                self.signals()
                    .robot_state_changed()
                    .emit(state.to_byte() as i8 as i64);
            }
            Event::Stacktrace(text) => {
                self.signals()
                    .stacktrace_received()
                    .emit(&GString::from(&text));
            }
            Event::CommandDropped { name } => {
                let message = format!("command {name} never acked");
                godot_warn!("RobocolBridge: {message}");
                self.signals().client_error().emit(&GString::from(&message));
            }
            Event::ProtocolError(e) => {
                godot_warn!("RobocolBridge: protocol error: {e}");
            }
            Event::Command { .. } | Event::WebcamAvailable(true) => {}
            Event::ActiveConfiguration(extra) => match serde_json::from_str::<ConfigMeta>(&extra) {
                Ok(meta) => self
                    .signals()
                    .active_config_changed()
                    .emit(&config_meta_to_dict(&meta)),
                Err(e) => godot_warn!("RobocolBridge: bad active-config payload: {e}"),
            },
            Event::ConfigurationList(extra) => {
                let mut configs = VarArray::new();
                for meta in cmd::parse_config_list(&extra) {
                    configs.push(&config_meta_to_dict(&meta).to_variant());
                }
                self.signals().configurations_changed().emit(&configs);
            }
            Event::Configuration(xml) => {
                self.signals()
                    .configuration_received()
                    .emit(&GString::from(&xml));
            }
            Event::UserDeviceList(json) => {
                self.signals()
                    .user_device_list_received()
                    .emit(&GString::from(&json));
            }
            Event::ScanResult(json) => {
                self.signals()
                    .scan_result_received()
                    .emit(&GString::from(&json));
            }
            Event::LynxModules(json) => {
                self.signals()
                    .lynx_modules_received()
                    .emit(&GString::from(&json));
            }
            Event::WebcamAvailable(false) => self.emit_stream_ended("webcam"),
            Event::WebcamFrame(jpeg) => self.emit_frame("webcam", &jpeg),
        }
    }
}

fn opmode_meta_to_dict(meta: &OpModeMeta) -> VarDictionary {
    let mut d = VarDictionary::new();
    d.set("name", meta.name.as_str());
    d.set("flavor", meta.flavor.as_str());
    d.set("group", meta.group.as_str());
    d
}

fn config_meta_to_dict(meta: &ConfigMeta) -> VarDictionary {
    let mut d = VarDictionary::new();
    d.set("isDirty", meta.is_dirty);
    d.set("location", meta.location.as_str());
    d.set("name", meta.name.as_str());
    d.set("resourceId", meta.resource_id);
    d
}

fn dict_to_config_meta(d: &VarDictionary) -> Option<ConfigMeta> {
    Some(ConfigMeta {
        is_dirty: d.get("isDirty")?.try_to::<bool>().ok()?,
        location: d.get("location")?.try_to::<GString>().ok()?.to_string(),
        name: d.get("name")?.try_to::<GString>().ok()?.to_string(),
        resource_id: d.get("resourceId")?.try_to::<i64>().ok()?,
    })
}

fn entry(key: &str, value: Variant, phase: &str) -> Variant {
    let mut d = VarDictionary::new();
    d.set("key", key);
    d.set("value", &value);
    d.set("phase", phase);
    d.to_variant()
}

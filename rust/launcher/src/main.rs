//! Stable launch stub.
//!
//! Sits at the fixed install path the desktop/Steam shortcut points at and
//! execs the app out of `bin/`. The updater only ever writes `bin.new/`; the
//! swap happens here, at the one moment nothing under `bin/` is open.

use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::process::Command;

#[cfg(target_os = "windows")]
const APP_CANDIDATES: &[&str] = &["deck-station.exe"];
#[cfg(target_os = "macos")]
const APP_CANDIDATES: &[&str] = &[
    "deck-station.app/Contents/MacOS/deck-station",
    "deck-station.x86_64",
];
#[cfg(not(any(target_os = "windows", target_os = "macos")))]
const APP_CANDIDATES: &[&str] = &["deck-station.x86_64"];

const LIVE: &str = "bin";
const STAGED: &str = "bin.new";
const RETIRED: &str = "bin.old";

fn main() {
    let root = match std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(Path::to_path_buf))
    {
        Some(dir) => dir,
        None => fail("cannot determine the install directory"),
    };

    reconcile(&root);

    let app = match app_in(&root.join(LIVE)) {
        Some(app) => app,
        None => fail(&format!(
            "no runnable build found in {}\n\
             The install looks incomplete — re-download a release bundle.",
            root.join(LIVE).display()
        )),
    };

    launch(&app, std::env::args_os().skip(1).collect());
}

/// Applies a staged update and repairs a swap that was interrupted partway.
///
/// The states this has to survive, in the order they occur: `bin` + `bin.new`
/// (update staged), `bin.old` + `bin.new` (retire done, promote not), `bin` +
/// `bin.old` (promote done, cleanup not). Any failure leaves a directory the
/// next run can still resolve into `bin`, so a torn swap never costs the
/// install. A staged directory with no app in it is left alone rather than
/// promoted over a working `bin/`.
fn reconcile(root: &Path) {
    let live = root.join(LIVE);
    let staged = root.join(STAGED);
    let retired = root.join(RETIRED);

    if app_in(&staged).is_some() {
        let retire = if live.is_dir() {
            let _ = std::fs::remove_dir_all(&retired);
            rename(&live, &retired)
        } else {
            true
        };
        if retire {
            rename(&staged, &live);
        }
    }

    if !live.is_dir() && retired.is_dir() {
        rename(&retired, &live);
    }

    if live.is_dir() {
        let _ = std::fs::remove_dir_all(&retired);
    }
}

fn rename(from: &Path, to: &Path) -> bool {
    match std::fs::rename(from, to) {
        Ok(()) => true,
        Err(err) => {
            eprintln!(
                "deck-station: cannot move {} to {}: {err}",
                from.display(),
                to.display()
            );
            false
        }
    }
}

fn app_in(dir: &Path) -> Option<PathBuf> {
    APP_CANDIDATES
        .iter()
        .map(|name| dir.join(name))
        .find(|app| app.is_file())
}

#[cfg(unix)]
fn launch(app: &Path, args: Vec<OsString>) -> ! {
    use std::os::unix::process::CommandExt;

    let err = Command::new(app).args(args).exec();
    fail(&format!("cannot run {}: {err}", app.display()))
}

#[cfg(windows)]
fn launch(app: &Path, args: Vec<OsString>) -> ! {
    match Command::new(app).args(args).status() {
        Ok(status) => std::process::exit(status.code().unwrap_or(0)),
        Err(err) => fail(&format!("cannot run {}: {err}", app.display())),
    }
}

fn fail(message: &str) -> ! {
    eprintln!("deck-station: {message}");
    message_box(message);
    std::process::exit(1)
}

#[cfg(windows)]
fn message_box(message: &str) {
    use std::os::windows::ffi::OsStrExt;

    fn wide(s: &str) -> Vec<u16> {
        std::ffi::OsStr::new(s)
            .encode_wide()
            .chain(Some(0))
            .collect()
    }

    #[link(name = "user32")]
    extern "system" {
        fn MessageBoxW(hwnd: *mut u8, text: *const u16, caption: *const u16, kind: u32) -> i32;
    }

    const MB_ICONERROR: u32 = 0x10;
    unsafe {
        MessageBoxW(
            std::ptr::null_mut(),
            wide(message).as_ptr(),
            wide("Deck Station").as_ptr(),
            MB_ICONERROR,
        );
    }
}

#[cfg(not(windows))]
fn message_box(_message: &str) {}

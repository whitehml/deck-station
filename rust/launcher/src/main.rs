//! Stable launch stub.
//!
//! Sits at the fixed install path the desktop/Steam shortcut points at, reads
//! `installed.json`, and hands off to `versions/<current>/`. The updater only
//! ever writes new version directories and flips that pointer, so the shortcut
//! target never moves.

use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::process::Command;

#[cfg(windows)]
const APP_BINARY: &str = "deck-station.exe";
#[cfg(not(windows))]
const APP_BINARY: &str = "deck-station.x86_64";

const POINTER: &str = "installed.json";
const VERSIONS: &str = "versions";

fn main() {
    let root = match std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(Path::to_path_buf))
    {
        Some(dir) => dir,
        None => fail("cannot determine the install directory"),
    };

    let app = match resolve(&root) {
        Some(app) => app,
        None => fail(&format!(
            "no runnable build found under {}\n\
             The install looks incomplete — re-download a release bundle.",
            root.join(VERSIONS).display()
        )),
    };

    launch(&app, std::env::args_os().skip(1).collect());
}

fn resolve(root: &Path) -> Option<PathBuf> {
    let pointer = std::fs::read_to_string(root.join(POINTER)).unwrap_or_default();

    for key in ["current", "previous"] {
        if let Some(version) = json_string_field(&pointer, key) {
            if let Some(app) = candidate(root, &version) {
                return Some(app);
            }
        }
    }

    let mut versions: Vec<OsString> = std::fs::read_dir(root.join(VERSIONS))
        .ok()?
        .flatten()
        .map(|e| e.file_name())
        .collect();
    versions.sort();
    versions
        .iter()
        .rev()
        .find_map(|name| candidate(root, &name.to_string_lossy()))
}

fn candidate(root: &Path, version: &str) -> Option<PathBuf> {
    let app = root.join(VERSIONS).join(version).join(APP_BINARY);
    app.is_file().then_some(app)
}

fn json_string_field(src: &str, key: &str) -> Option<String> {
    let needle = format!("\"{key}\"");
    let rest = &src[src.find(&needle)? + needle.len()..];
    let rest = &rest[rest.find(':')? + 1..];
    let start = rest.find('"')? + 1;
    let end = rest[start..].find('"')?;
    Some(rest[start..start + end].to_string())
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

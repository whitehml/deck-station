use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

type Result<T = ()> = std::result::Result<T, Box<dyn std::error::Error>>;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let release = args.iter().any(|a| a == "--release");

    let result = match args.first().map(String::as_str) {
        Some("stage") => stage(release),
        Some("dev") => dev(),
        Some("mock") => mock(),
        Some("export") => export(),
        Some("lint") => lint(),
        Some("clean") => clean(),
        _ => {
            print_help();
            return;
        }
    };

    if let Err(e) = result {
        eprintln!("xtask: {e}");
        std::process::exit(1);
    }
}

fn print_help() {
    println!(
        "cargo xtask <command>\n\
         \n\
         stage [--release]   Build robocol_godot and copy the lib into godot/bin/\n\
         dev                 stage (debug) -> godot4 --path godot\n\
         mock                stage (debug) + build fake_rc -> DECK_DS_MOCK=1 godot4\n\
         export              stage (release) -> godot4 --headless --export-release Linux\n\
         lint                gdformat --check + gdlint over godot/\n\
         clean               remove staged libs from godot/bin/"
    );
}

struct LibNames {
    built: &'static str,
    prefix: &'static str,
    ext: &'static str,
}

fn lib_names() -> LibNames {
    // cargo drops the "lib" prefix on Windows and uses a per-OS extension; the
    // .gdextension entries mirror exactly what we stage here.
    if cfg!(target_os = "windows") {
        LibNames {
            built: "robocol_godot.dll",
            prefix: "robocol_godot",
            ext: "dll",
        }
    } else if cfg!(target_os = "macos") {
        LibNames {
            built: "librobocol_godot.dylib",
            prefix: "librobocol_godot",
            ext: "dylib",
        }
    } else {
        LibNames {
            built: "librobocol_godot.so",
            prefix: "librobocol_godot",
            ext: "so",
        }
    }
}

fn stage(release: bool) -> Result {
    let profile = if release { "release" } else { "debug" };

    let mut build = Command::new("cargo");
    build
        .current_dir(workspace())
        .args(["build", "-p", "robocol_godot"]);
    if release {
        build.arg("--release");
    }
    run(build, "cargo build robocol_godot")?;

    let n = lib_names();
    let src = repo_root().join("rust/target").join(profile).join(n.built);
    // Un-exported Godot runs with the "debug" feature tag and loads the ".debug"
    // name; an exported release template loads the bare name.
    let staged = if release {
        format!("{}.{}", n.prefix, n.ext)
    } else {
        format!("{}.debug.{}", n.prefix, n.ext)
    };
    let dst = repo_root().join("godot/bin").join(&staged);
    fs::copy(&src, &dst)
        .map_err(|e| format!("copy {} -> {}: {e}", src.display(), dst.display()))?;
    println!("staged {staged}");
    Ok(())
}

fn dev() -> Result {
    stage(false)?;
    run(godot(&[]), "godot")
}

fn mock() -> Result {
    stage(false)?;

    let mut fake = Command::new("cargo");
    fake.current_dir(repo_root().join("external/robocol"))
        .args(["build", "-p", "fake_rc"]);
    run(fake, "cargo build fake_rc")?;

    let mut g = godot(&[]);
    g.env("DECK_DS_MOCK", "1");
    run(g, "godot (mock)")
}

fn export() -> Result {
    stage(true)?;
    run(
        godot(&["--headless", "--export-release", "Linux"]),
        "godot export",
    )
}

fn lint() -> Result {
    let godot_dir = repo_root().join("godot");
    let mut fmt = Command::new("gdformat");
    fmt.arg("--check").arg(&godot_dir);
    run(fmt, "gdformat")?;

    let mut lint = Command::new("gdlint");
    lint.arg(&godot_dir);
    run(lint, "gdlint")
}

fn clean() -> Result {
    let bin = repo_root().join("godot/bin");
    for entry in fs::read_dir(&bin)? {
        let path = entry?.path();
        if matches!(
            path.extension().and_then(|e| e.to_str()),
            Some("so" | "dylib" | "dll")
        ) {
            fs::remove_file(&path)?;
            println!("removed {}", path.display());
        }
    }
    Ok(())
}

fn godot(extra: &[&str]) -> Command {
    let mut cmd = Command::new("godot4");
    cmd.arg("--path").arg(repo_root().join("godot")).args(extra);
    cmd
}

fn run(mut cmd: Command, label: &str) -> Result {
    let status = cmd.status().map_err(|e| format!("{label}: {e}"))?;
    if !status.success() {
        return Err(format!("{label}: exited with {status}").into());
    }
    Ok(())
}

fn workspace() -> &'static Path {
    Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap()
}

fn repo_root() -> PathBuf {
    workspace().parent().unwrap().to_path_buf()
}

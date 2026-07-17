# external

## robocol

`external/robocol/` the
[`robocol`](../../robocol) crate the bridge depends on.

It is a git submodule pinned to a specific `robocol` commit. A fresh clone
must pull it down before the workspace will build:

```sh
git clone --recurse-submodules <deck-station-remote-url>
# or when already cloned:
git submodule update --init external/robocol
```

To move the pin to a newer core commit:

```sh
git -C external/robocol checkout <sha>   # pin
git add external/robocol && git commit    # records the SHA
```

The bridge path-depends on it (`rust/robocol_godot/Cargo.toml`):

```toml
robocol = { path = "../../external/robocol/robocol" }
```

The submodule SHA plus `rust/Cargo.lock` pin the exact core the app was built
against.

In the future, we will drop the submodule and switch the bridge to a
pinned git-dep (`robocol = { git = "…", tag = "v0.x.y" }`). Once the core is stable.

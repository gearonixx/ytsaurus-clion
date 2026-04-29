# CLion setup for YTsaurus

End-to-end guide for getting CLion (local or Remote Development via Gateway) to
correctly configure, build and index YTsaurus.

The container provided by `dev/Dockerfile` ships clang-18, cmake, ninja, conan
and ccache, but two things still need to be wired up before CLion can take over:

1. Unsuffixed names for the LLVM IR tools (`llvm-link`, `opt`, `llc`,
   `llvm-as`) — only versioned binaries are installed by default.
2. The CMake option `-DREQUIRED_LLVM_TOOLING_VERSION=18` so the
   `cmake/llvm-tools.cmake` module forces version 18 instead of probing
   for `-12`/`-14`.

Either of those is enough. Both together are belt-and-suspenders and idempotent.

---

## 1. Fix LLVM tooling on the host

Run once inside the container (or wherever your build host is):

```bash
./dev/setup-llvm-symlinks.sh
```

This creates `/usr/local/bin/{llvm-link,opt,llc,llvm-as}` pointing at the
versioned binaries. Idempotent — safe to re-run, will report `[ok]` if the
links already match.

To target a different LLVM major version:

```bash
LLVM_VERSION=20 ./dev/setup-llvm-symlinks.sh
```

> The Dockerfile only sets `update-alternatives` for `clang`/`clang++`/`clangd`,
> which is why these four extra tools need a separate step. Long-term fix is
> to add them to the Dockerfile; this script is the immediate workaround.

## 2. Configure CLion

### 2.1 Toolchain

`Settings → Build, Execution, Deployment → Toolchains`

Pick the remote toolchain attached to the dev container (or local on a native
Linux setup). Make sure `CMake`, `Make`, `C Compiler`, `C++ Compiler`,
`Debugger` resolve — CLion auto-detects `cmake`, `clang-18`, `clang++-18`,
`gdb` from `PATH`.

### 2.2 CMake profile

`Settings → Build, Execution, Deployment → CMake`

Select (or create) the **Release** profile and set:

| Field | Value |
|---|---|
| Build type | `Release` |
| **CMake options** | `-DREQUIRED_LLVM_TOOLING_VERSION=18` |
| Build directory | `/workspace/build/conan/build/Release` |
| Toolchain | the one from 2.1 |

> **Important:** the flag goes in the **CMake options** field — the line that
> ends up between `cmake` and `--preset`. Do **not** put it in
> "Build options" (that's `cmake --build`) or "Environment".

If you use the Conan-generated preset:

* CLion → `CMake` → `+` → `From CMakePresets.json` → `conan-release`,
  then add `-DREQUIRED_LLVM_TOOLING_VERSION=18` to its CMake options.

Alternatively, define your own preset in `CMakeUserPresets.json` that inherits
`conan-release` and pre-sets the cache variable — see the project root for the
existing setup.

### 2.3 Apply

`Tools → CMake → Reset Cache and Reload Project`

> **Reset**, not just **Reload** — otherwise stale `LLVMLINK-NOTFOUND` entries
> survive in `CMakeCache.txt` and configure fails again.

Watch the CMake output panel. Successful run ends with:

```
-- Configuring done (3.3s)
-- Generating done (8.3s)
-- Build files have been written to: /workspace/build/conan/build/Release
```

CLion will then start indexing — status bar shows
`Processing files X of Y`. On YTsaurus this typically takes 30–90 minutes the
first time, depending on cores and disk speed. Subsequent reloads are seconds.

## 3. Verify

```bash
./dev/verify-clion-setup.sh
```

Expected output (numbers will vary):

```
== LLVM tooling ==
  [ok]   llvm-link -> /usr/local/bin/llvm-link
  [ok]   opt -> /usr/local/bin/opt
  [ok]   llc -> /usr/local/bin/llc
  [ok]   llvm-as -> /usr/local/bin/llvm-as

== CMake configuration (/workspace/build/conan/build/Release) ==
  [ok]   CMakeCache.txt present
  [ok]   REQUIRED_LLVM_TOOLING_VERSION=18

== compile_commands.json ==
  [ok]   compile_commands.json: 104 MB, 18207 entries

== clangd index (/workspace/ytsaurus/.cache/clangd/index) ==
  [ok]   indexed files: 23944, total size: 268M

All required checks passed.
```

A populated clangd index is the strongest evidence that CLion has actually
parsed the project — without `compile_commands.json` being read, the
`.cache/clangd/index/` directory stays empty.

Override the build dir if it lives elsewhere:

```bash
BUILD_DIR=/somewhere/else ./dev/verify-clion-setup.sh
```

## 4. Smoke-test in the IDE

Open `yt/yt/server/all/main.cpp` and:

* `Ctrl+Click` on any `#include "yt/..."` — should jump into the file.
* Hover over a symbol — popup with type info should appear.
* `Alt+F7` (Find Usages) on a class — should list call sites across the repo.

If those work, the toolchain, CMake configuration, and indexer are all wired
correctly.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `llvm-link not found` from cmake | unsuffixed binaries missing | run `setup-llvm-symlinks.sh` |
| Configure passes but flag never appears in cmake command line | flag put in wrong CLion field | move to **CMake options**, then **Reset Cache and Reload** |
| `find_package(linux-headers-generic)` fails | Conan toolchain not loaded | use the `conan-release` preset, not a bare Debug/Release profile |
| `Cannot resolve` red squiggles everywhere | indexing not finished | wait, or `File → Invalidate Caches → Invalidate and Restart` |
| Stale `LLVMLINK-NOTFOUND` in cache | partial fix without reset | `rm $BUILD_DIR/CMakeCache.txt` then reload |

## Reference: what `cmake/llvm-tools.cmake` does

```cmake
if (REQUIRED_LLVM_TOOLING_VERSION)
    find_program(LLVMLINK llvm-link-${REQUIRED_LLVM_TOOLING_VERSION} REQUIRED)
    find_program(LLVMOPT  opt-${REQUIRED_LLVM_TOOLING_VERSION}       REQUIRED)
    # ...
else()
    find_program(LLVMLINK NAMES llvm-link-12 llvm-link-14 llvm-link)
    find_program(LLVMOPT  NAMES opt-12       opt-14       opt)
    # ...
endif()
```

Two ways to satisfy it:

* Set `REQUIRED_LLVM_TOOLING_VERSION=18` → the first branch finds
  `/usr/bin/{llvm-link,opt,llc,llvm-as}-18` directly.
* Provide unsuffixed `llvm-link`/`opt`/`llc`/`llvm-as` in PATH → the
  fallback branch (last `NAMES` entry) succeeds.

`setup-llvm-symlinks.sh` covers the second; the CLion CMake option covers the
first. Either is sufficient.

---

## Import host CLion settings into the container backend

When CLion runs as a Gateway backend inside the container, it starts with a
fresh config and none of your host keymap, themes, plugins, code style, or
inspection profile carry over. Easiest way to bring them across is to copy your
host `settings.zip` into the container and import it from the remote IDE.

### One-shot

```bash
./dev/clion-import-settings.sh
```

This:

1. Auto-detects the newest `~/.config/JetBrains/CLion<ver>/settings.zip` on the
   host (if you've never exported one, do it first via
   **File → Manage IDE Settings → Export Settings…**).
2. `docker cp`s it to `/home/dev/settings.zip` inside the container.
3. `chown`s it to `dev:dev`.

Then in the **remote** CLion UI:

**File → Manage IDE Settings → Import Settings…** → enter
`/home/dev/settings.zip` → pick categories → restart.

> If the file picker doesn't show `/home/dev/settings.zip`, type the full path
> into the location bar — it loads.

### Options

```bash
# different container or destination path
./dev/clion-import-settings.sh --container my-dev --dest /tmp/settings.zip

# explicit source (e.g. an old export checked into a dotfiles repo)
./dev/clion-import-settings.sh --settings ~/dotfiles/clion-settings.zip
```

Env-var equivalents: `CONTAINER`, `DEST`, `SETTINGS_SRC`.

### Manual fallback

If you'd rather not use the script:

```bash
docker cp ~/.config/JetBrains/CLion2026.1/settings.zip \
    ytsaurus-dev:/home/dev/settings.zip
docker exec ytsaurus-dev chown dev:dev /home/dev/settings.zip
```

### Cross-version note

JetBrains supports forward import (older `settings.zip` into a newer IDE) but
not backward. If your host CLion is *newer* than the container backend, export
from the matching older install or skip the import and configure manually.
The script prints a `note:` line when host and container versions differ so you
can decide.

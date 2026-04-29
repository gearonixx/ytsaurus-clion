# YTsaurus dev container

Ubuntu 20.04 + clang-18, cmake, ninja, conan, protoc, ccache. Non-root `dev` user with passwordless sudo, sshd on port 2222.

## Build

```bash
docker build -t ytsaurus-build \
    --build-arg USER_UID=$(id -u) \
    --build-arg USER_GID=$(id -g) \
    dev/
```

## Run

```bash
docker run -d \
    --name ytsaurus-dev \
    -p 2222:2222 \
    -v "$PWD":/workspace/ytsaurus \
    -v ytsaurus-ccache:/home/dev/.ccache \
    -w /workspace \
    ytsaurus-build
```

```bash
docker start ytsaurus-dev
docker stop ytsaurus-dev
docker exec -it ytsaurus-dev bash
```

## Build YTsaurus

```bash
./ya make yt/yt/server/all
```

```bash
cd build
cmake -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DREQUIRED_LLVM_TOOLING_VERSION=18 \
      -DCMAKE_TOOLCHAIN_FILE=../ytsaurus/clang.toolchain \
      -DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=../ytsaurus/cmake/conan_provider.cmake \
      ../ytsaurus
ninja
```

## SSH / Remote IDE

Copy the key once:

```bash
docker cp ytsaurus-dev:/home/dev/.ssh/clion_key ~/.ssh/clion_key
chmod 600 ~/.ssh/clion_key
```

Connect:

```bash
ssh -i ~/.ssh/clion_key -p 2222 dev@localhost
```

Password fallback: `dev` / `dev`.

Or connect by container IP (find it with
`docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ytsaurus-dev`):

```bash
ssh dev@172.17.0.2 -p 2222   # password: dev
```

Same pattern in JetBrains Gateway / CLion Remote Development — when prompted
`Authenticating to: dev@172.17.0.2:2222`, the password is `dev`.

**CLion:** Toolchains → Remote Host → `localhost:2222`, user `dev`, key `~/.ssh/clion_key`. CMake build dir `/workspace/build`. See [`CLION_SETUP.md`](CLION_SETUP.md) for the full IDE setup (LLVM tooling fix, CMake options, verification).

**VSCode:** Remote-SSH with:

```
Host ytsaurus-dev
    HostName localhost
    Port 2222
    User dev
    IdentityFile ~/.ssh/clion_key
```

## CLion settings import

Bring host CLion settings (keymap, theme, plugins, code style) into the
container backend:

```bash
./dev/clion-import-settings.sh
```

Auto-detects the newest host `~/.config/JetBrains/CLion<ver>/settings.zip`,
copies it to `/home/dev/settings.zip` in the container. Then in remote CLion:
**File → Manage IDE Settings → Import Settings…** → `/home/dev/settings.zip`.
Details in [`CLION_SETUP.md`](CLION_SETUP.md).

## CLion backend download

Gateway's downloader has no retry and dies on any network blip. Use `clion-backend-download.sh` instead — runs parallel `wget --continue` workers in tmux, survives drops and host suspend.

```bash
pkill -f 'download.jetbrains.com'
./clion-backend-download.sh start https://download.jetbrains.com/cpp/CLion-<build>.tar.gz
./clion-backend-download.sh status
./clion-backend-download.sh finalize
```

`finalize` does three things in one go: picks the largest `*.tar.gz.*`, verifies it, renames to the canonical `<hash>_CLion-<build>.tar.gz`, **extracts it into the matching directory and `touch`es `.expandSucceeded` inside**, then creates two backups (hardlink in `~/backups/`, reflink copy in `/workspace/backups/`).

Then Gateway → **Reconnect**.

### Why we touch `.expandSucceeded` and pre-extract

Gateway's download path has a second bug on top of the no-retry one: even if a valid `<canonical>.tar.gz` is already on disk, Gateway's `curl --output` opens it in *truncate* mode before checking — destroying the cached file and starting from zero. The only way it skips its own download/extract is if the target directory `<hash>_CLion-<build>/` already contains a `.expandSucceeded` flag file.

So after a clean download we extract the archive ourselves (`tar --strip-components=1` straight into that dir) and `touch .expandSucceeded`. Gateway sees the flag, treats the unpack as already done, and goes straight to launching the backend — no truncation, no redownload.

The two backups (`~/backups/` hardlink + `/workspace/backups/` reflink-copy) cost zero extra disk: the inner one shares the inode, the host-side one is a btrfs CoW clone. They're insurance against Gateway truncating the cached archive on a future reconnect, or the container being rebuilt — restore is just `cp` from either path. Override locations with `INNER_BACKUP_DIR` / `OUTER_BACKUP_DIR` env vars.

## Project setup helpers

After the container is up and the source is mounted, two scripts get the build
ready for CLion:

```bash
./dev/setup-llvm-symlinks.sh    # symlinks llvm-link/opt/llc/llvm-as into PATH
./dev/verify-clion-setup.sh     # checks compile_commands.json + clangd index
```

`setup-llvm-symlinks.sh` is idempotent and only needed once per container —
`cmake/llvm-tools.cmake` looks up unsuffixed `llvm-*` binaries that the
Dockerfile doesn't `update-alternatives`, so the symlinks bridge that gap.

`verify-clion-setup.sh` is the answer to "did CLion actually pick up
`compile_commands.json`?" — see [`CLION_SETUP.md`](CLION_SETUP.md) for what
its output means.

## Screenshots

Walkthrough of the setup, in order:

| #   | Screenshot                              |
| --- | --------------------------------------- |
| 1   | ![1](screenshots/1.png)                 |
| 2   | ![2](screenshots/2.png)                 |
| 3   | ![3](screenshots/3.png)                 |
| 4   | ![4](screenshots/4.png)                 |
| 5   | ![5](screenshots/5.png)                 |
| 6   | ![6](screenshots/6.png)                 |
| 7   | ![7](screenshots/7.png)                 |
| 8   | ![8](screenshots/8.png)                 |
| 9   | ![9](screenshots/9.png)                 |

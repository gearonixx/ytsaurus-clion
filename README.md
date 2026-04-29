# YTsaurus dev container

Ubuntu 20.04 image with the full YTsaurus build toolchain (clang-18, cmake,
ninja, conan, protoc, ccache), a non-root `dev` user with passwordless sudo,
and an sshd on port 2222 for CLion / VSCode remote development.

## Build the image

From the repo root (one level above `dev/`):

```bash
docker build -t ytsaurus-build \
    --build-arg USER_UID=$(id -u) \
    --build-arg USER_GID=$(id -g) \
    dev/
```

`USER_UID` / `USER_GID` matter so files written through the bind mount stay
writable on the host.

## Run the container

Create it once with a named volume for ccache so rebuilds stay fast across
runs:

```bash
docker run -it \
    --name ytsaurus-dev \
    -v "$PWD":/workspace/ytsaurus \
    -v ytsaurus-ccache:/home/dev/.ccache \
    -w /workspace \
    ytsaurus-build
```

Re-attach to the same container later:

```bash
docker start -ai ytsaurus-dev
```

Open another shell into the running container:

```bash
docker exec -it ytsaurus-dev bash
```

## Build YTsaurus

### ya make (Arcadia-style)

```bash
./ya make yt/yt/server/all
```

### CMake + Ninja

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

Build a single target:

```bash
ninja <target>
```

Generate `compile_commands.json` for IDE indexing (CLion / clangd / VSCode):

```bash
cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON .
```

The file lands at `build/compile_commands.json`.

## Remote IDE access (CLion / VSCode)

The container starts `sshd` on port 2222 automatically (see `entrypoint.sh`).
A keypair is generated on first start at `/home/dev/.ssh/clion_key` and
registered in `authorized_keys`.

Copy the private key to the host:

```bash
docker cp ytsaurus-dev:/home/dev/.ssh/clion_key ~/.ssh/clion_key
chmod 600 ~/.ssh/clion_key
```

Connect:

```bash
ssh -i ~/.ssh/clion_key -p 2222 dev@<container-ip-or-localhost>
```

Publish the port to the host with `-p 2222:2222` on `docker run` if you need
to reach it from outside Docker's bridge network.

Password fallback (if you don't want to deal with keys): user `dev`, password
`dev`.

### CLion

1. Settings → Build, Execution, Deployment → Toolchains → **+** → Remote Host
2. Credentials: host = container IP (or `localhost` if you forwarded the port),
   port = `2222`, user = `dev`, auth = key file `~/.ssh/clion_key`
3. Settings → Build → CMake → select that toolchain, build dir = `/workspace/build`
4. Optionally: Settings → Build → Compilation Database → `/workspace/build`

### VSCode

Use the **Remote-SSH** extension and add a host entry:

```
Host ytsaurus-dev
    HostName <container-ip>
    Port 2222
    User dev
    IdentityFile ~/.ssh/clion_key
```

Then `Remote-SSH: Connect to Host…` → `ytsaurus-dev`.

## Files in this directory

| File             | Purpose                                                  |
| ---------------- | -------------------------------------------------------- |
| `Dockerfile`     | Builds the `ytsaurus-build` image.                       |
| `entrypoint.sh`  | Starts sshd, generates host + user keys on first run.    |
| `README.md`      | You are here.                                            |

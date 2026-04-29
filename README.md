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

**CLion:** Toolchains → Remote Host → `localhost:2222`, user `dev`, key `~/.ssh/clion_key`. CMake build dir `/workspace/build`.

**VSCode:** Remote-SSH with:

```
Host ytsaurus-dev
    HostName localhost
    Port 2222
    User dev
    IdentityFile ~/.ssh/clion_key
```

## CLion backend download

Gateway's downloader has no retry and dies on any network blip. Use `clion-backend-download.sh` instead — runs parallel `wget --continue` workers in tmux, survives drops and host suspend.

```bash
pkill -f 'download.jetbrains.com'
./clion-backend-download.sh start https://download.jetbrains.com/cpp/CLion-<build>.tar.gz
./clion-backend-download.sh status
./clion-backend-download.sh finalize
```

Then Gateway → **Reconnect**.

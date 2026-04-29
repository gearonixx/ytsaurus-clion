FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

ARG LLVM_VERSION=18
ARG PROTOC_VERSION=3.20.3
ARG CONAN_VERSION=2.4.1
ARG PYYAML_VERSION=6.0.1
ARG CCACHE_VERSION=4.8.2
ARG USER_NAME=dev
ARG USER_UID=1000
ARG USER_GID=1000

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg lsb-release software-properties-common wget \
        libidn11-dev m4 ninja-build unzip \
        python3 python3-pip python3-dev python3-venv \
        antlr3 libaio1 libaio-dev build-essential pkg-config \
        gdb vim nano less tree jq htop tmux sudo openssh-client rsync \
        zip xz-utils file patch \
        git-lfs \
        openssh-server procps \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key \
        | gpg --dearmor -o /usr/share/keyrings/llvm-archive-keyring.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/llvm-archive-keyring.gpg] http://apt.llvm.org/focal/ llvm-toolchain-focal-${LLVM_VERSION} main" \
        > /etc/apt/sources.list.d/llvm.list \
 && curl -fsSL https://apt.kitware.com/keys/kitware-archive-latest.asc \
        | gpg --dearmor -o /usr/share/keyrings/kitware-archive-keyring.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ focal main" \
        > /etc/apt/sources.list.d/kitware.list \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
 && add-apt-repository -y ppa:ubuntu-toolchain-r/test \
 && add-apt-repository -y ppa:git-core/ppa

RUN apt-get update && apt-get install -y --no-install-recommends \
        clang-${LLVM_VERSION} clang-tools-${LLVM_VERSION} \
        lld-${LLVM_VERSION} lldb-${LLVM_VERSION} \
        llvm-${LLVM_VERSION} llvm-${LLVM_VERSION}-dev llvm-${LLVM_VERSION}-tools \
        libclang-rt-${LLVM_VERSION}-dev \
        clangd-${LLVM_VERSION} clang-tidy-${LLVM_VERSION} clang-format-${LLVM_VERSION} \
        libc++-${LLVM_VERSION}-dev libc++abi-${LLVM_VERSION}-dev \
        cmake git gh \
    && rm -rf /var/lib/apt/lists/* \
    && update-alternatives --install /usr/bin/clang        clang        /usr/bin/clang-${LLVM_VERSION}        100 \
    && update-alternatives --install /usr/bin/clang++      clang++      /usr/bin/clang++-${LLVM_VERSION}      100 \
    && update-alternatives --install /usr/bin/lld          lld          /usr/bin/lld-${LLVM_VERSION}          100 \
    && update-alternatives --install /usr/bin/clangd       clangd       /usr/bin/clangd-${LLVM_VERSION}       100 \
    && update-alternatives --install /usr/bin/clang-tidy   clang-tidy   /usr/bin/clang-tidy-${LLVM_VERSION}   100 \
    && update-alternatives --install /usr/bin/clang-format clang-format /usr/bin/clang-format-${LLVM_VERSION} 100

RUN python3 -m pip install --no-cache-dir --upgrade pip setuptools wheel \
 && python3 -m pip install --no-cache-dir --ignore-installed PyYAML \
        conan==${CONAN_VERSION} \
        PyYAML==${PYYAML_VERSION} \
        dacite

RUN cd /tmp \
 && curl -fsSL -o protoc.zip \
        "https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/protoc-${PROTOC_VERSION}-linux-x86_64.zip" \
 && unzip protoc.zip -d /usr/local \
 && rm protoc.zip

RUN cd /tmp \
 && curl -fsSL -o ccache.tar.xz \
        "https://github.com/ccache/ccache/releases/download/v${CCACHE_VERSION}/ccache-${CCACHE_VERSION}-linux-x86_64.tar.xz" \
 && tar xf ccache.tar.xz \
 && install -m755 "ccache-${CCACHE_VERSION}-linux-x86_64/ccache" /usr/local/bin/ccache \
 && rm -rf ccache.tar.xz "ccache-${CCACHE_VERSION}-linux-x86_64"

RUN groupadd -g ${USER_GID} ${USER_NAME} \
 && useradd -m -u ${USER_UID} -g ${USER_GID} -s /bin/bash ${USER_NAME} \
 && echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USER_NAME} \
 && chmod 0440 /etc/sudoers.d/${USER_NAME} \
 && mkdir -p /workspace /home/${USER_NAME}/.ccache \
 && chown -R ${USER_UID}:${USER_GID} /workspace /home/${USER_NAME}/.ccache \
 && echo "${USER_NAME}:${USER_NAME}" | chpasswd

RUN printf '%s\n' \
        'Port 2222' \
        'PermitRootLogin no' \
        'PubkeyAuthentication yes' \
        'PasswordAuthentication yes' \
        'ChallengeResponseAuthentication no' \
        'UsePAM yes' \
        'X11Forwarding no' \
        'PrintMotd no' \
        'AcceptEnv LANG LC_*' \
        'Subsystem sftp /usr/lib/openssh/sftp-server' \
        > /etc/ssh/sshd_config \
 && mkdir -p /run/sshd \
 && rm -f /etc/ssh/ssh_host_*
EXPOSE 2222

ENV CMAKE_C_COMPILER_LAUNCHER=ccache \
    CMAKE_CXX_COMPILER_LAUNCHER=ccache \
    CCACHE_DIR=/home/${USER_NAME}/.ccache

RUN clang --version && clang++ --version && ld.lld-${LLVM_VERSION} --version \
 && clangd --version && clang-tidy --version && clang-format --version \
 && cmake --version && ninja --version && git --version && gh --version \
 && python3 --version && conan --version && protoc --version \
 && ccache --version && gdb --version

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

USER ${USER_NAME}
WORKDIR /workspace

RUN curl -fsSL https://claude.ai/install.sh | bash \
 && echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
ENV PATH=/home/${USER_NAME}/.local/bin:${PATH}

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]

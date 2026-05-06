#!/bin/bash
# Host-side wrapper that gets CLion ready to SSH into the dev container.
#
# Steps:
#   1. Start the container if it's not running.
#   2. Run dev/manually-start-ssh.sh inside it (generates host keys, ensures
#      ~/.ssh/clion_key exists, appends the pubkey to authorized_keys, starts sshd).
#   3. Copy the generated private key out to the host so CLion can use it.
#   4. Verify the host can actually SSH into the container.
#
# Run this from the host. Usage:
#     ./dev/setup-clion-ssh.sh
#
# Overrides:
#     CONTAINER=my-dev ./dev/setup-clion-ssh.sh
#     HOST_KEY=~/.ssh/some_other_key ./dev/setup-clion-ssh.sh

set -euo pipefail

CONTAINER="${CONTAINER:-ytsaurus-dev}"
HOST_KEY="${HOST_KEY:-$HOME/.ssh/ytsaurus_clion_key}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IN_CONTAINER_SCRIPT="/workspace/ytsaurus/dev/manually-start-ssh.sh"

echo "[1/4] Ensuring container '${CONTAINER}' is running..."
if ! docker inspect "${CONTAINER}" >/dev/null 2>&1; then
    echo "ERROR: container '${CONTAINER}' does not exist. Create it first (docker run ...)." >&2
    exit 1
fi
state="$(docker inspect -f '{{.State.Status}}' "${CONTAINER}")"
if [ "${state}" != "running" ]; then
    docker start "${CONTAINER}" >/dev/null
    echo "      started (was ${state})"
else
    echo "      already running"
fi

echo "[2/4] Running manually-start-ssh.sh inside the container..."
docker exec "${CONTAINER}" bash "${IN_CONTAINER_SCRIPT}"

echo "[3/4] Copying private key to host (${HOST_KEY})..."
mkdir -p "$(dirname "${HOST_KEY}")"
chmod 700 "$(dirname "${HOST_KEY}")"
docker cp "${CONTAINER}:/home/dev/.ssh/clion_key"     "${HOST_KEY}"
docker cp "${CONTAINER}:/home/dev/.ssh/clion_key.pub" "${HOST_KEY}.pub"
chmod 600 "${HOST_KEY}"
chmod 644 "${HOST_KEY}.pub"

echo "[4/4] Verifying host can SSH into the container..."
IP="$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$v.IPAddress}}{{"\n"}}{{end}}' "${CONTAINER}" | awk 'NF{print; exit}')"
if [ -z "${IP}" ]; then
    IP="$(docker inspect -f '{{.NetworkSettings.IPAddress}}' "${CONTAINER}")"
fi
if [ -z "${IP}" ]; then
    echo "ERROR: could not determine container IP." >&2
    exit 1
fi
if ssh -i "${HOST_KEY}" \
       -o StrictHostKeyChecking=no \
       -o UserKnownHostsFile=/dev/null \
       -o LogLevel=ERROR \
       -p 2222 "dev@${IP}" 'echo SSH_OK' 2>/dev/null | grep -q SSH_OK; then
    echo
    echo "OK — CLion can now connect with:"
    echo "    Host: ${IP}"
    echo "    Port: 2222"
    echo "    User: dev"
    echo "    Key:  ${HOST_KEY}"
    echo
    echo "Quick test from a terminal:"
    echo "    ssh -i ${HOST_KEY} -p 2222 dev@${IP}"
else
    echo "ERROR: sshd is up inside the container but the host can't reach it on ${IP}:2222." >&2
    echo "       Check 'docker network inspect bridge' and that nothing on the host blocks 172.17.0.0/16." >&2
    exit 1
fi

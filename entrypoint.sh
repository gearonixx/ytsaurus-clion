#!/bin/bash
set -e

sudo ssh-keygen -A >/dev/null 2>&1 || true
sudo mkdir -p /run/sshd

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
if [ ! -f "$HOME/.ssh/clion_key" ]; then
    ssh-keygen -t ed25519 -f "$HOME/.ssh/clion_key" -N "" -C "clion@ytsaurus" >/dev/null
fi
touch "$HOME/.ssh/authorized_keys"
chmod 600 "$HOME/.ssh/authorized_keys"
if ! grep -qxF "$(cat "$HOME/.ssh/clion_key.pub")" "$HOME/.ssh/authorized_keys"; then
    cat "$HOME/.ssh/clion_key.pub" >> "$HOME/.ssh/authorized_keys"
fi

if ! pgrep -fx "/usr/sbin/sshd -f /etc/ssh/sshd_config" >/dev/null; then
    sudo /usr/sbin/sshd -f /etc/ssh/sshd_config
fi

if [ "$#" -eq 0 ]; then
    exec sleep infinity
fi

exec "$@"

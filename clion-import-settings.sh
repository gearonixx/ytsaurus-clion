#!/bin/bash
set -euo pipefail

# Copy host JetBrains CLion settings.zip into the dev container so the remote
# CLion backend can import them via File -> Manage IDE Settings -> Import Settings.

CONTAINER="${CONTAINER:-ytsaurus-dev}"
DEST="${DEST:-/home/dev/settings.zip}"
SETTINGS_SRC="${SETTINGS_SRC:-}"

usage() {
    cat <<EOF
usage: clion-import-settings.sh [--container NAME] [--settings PATH] [--dest PATH]

  --container NAME   target container (default: ytsaurus-dev, env: CONTAINER)
  --settings PATH    host settings.zip; auto-detected from
                     ~/.config/JetBrains/CLion<ver>/settings.zip if omitted
  --dest PATH        path inside container (default: /home/dev/settings.zip)

After running, in the remote CLion UI:
  File -> Manage IDE Settings -> Import Settings... -> $DEST
EOF
    exit "${1:-1}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --container) CONTAINER="$2"; shift 2 ;;
        --settings)  SETTINGS_SRC="$2"; shift 2 ;;
        --dest)      DEST="$2"; shift 2 ;;
        -h|--help)   usage 0 ;;
        *)           echo "unknown arg: $1" >&2; usage ;;
    esac
done

command -v docker >/dev/null || { echo "error: docker not found" >&2; exit 1; }

if ! docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -qx true; then
    echo "error: container '$CONTAINER' is not running" >&2
    echo "       docker ps --format '{{.Names}}'  to list" >&2
    exit 1
fi

if [[ -z "$SETTINGS_SRC" ]]; then
    # newest CLion<version> dir under ~/.config/JetBrains containing settings.zip
    SETTINGS_SRC=$(find "${HOME}/.config/JetBrains" -mindepth 2 -maxdepth 2 \
        -type f -name 'settings.zip' -path '*/CLion*/settings.zip' \
        -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
fi

[[ -n "$SETTINGS_SRC" && -f "$SETTINGS_SRC" ]] || {
    echo "error: settings.zip not found" >&2
    echo "       export it from CLion: File -> Manage IDE Settings -> Export Settings" >&2
    echo "       or pass --settings PATH" >&2
    exit 1
}

HOST_VER=$(basename "$(dirname "$SETTINGS_SRC")")
echo "host:      $SETTINGS_SRC ($HOST_VER, $(stat -c%s "$SETTINGS_SRC") bytes)"
echo "container: $CONTAINER:$DEST"

docker cp "$SETTINGS_SRC" "${CONTAINER}:${DEST}"
docker exec "$CONTAINER" chown dev:dev "$DEST"

# best-effort: report container's CLion version so user knows about cross-version imports
CONT_VER=$(docker exec "$CONTAINER" bash -c \
    'ls -d ~/.config/JetBrains/CLion* 2>/dev/null | head -1 | xargs -r basename' \
    2>/dev/null || true)
[[ -n "$CONT_VER" && "$CONT_VER" != "$HOST_VER" ]] && \
    echo "note: host is $HOST_VER, container is $CONT_VER (forward-import is supported)"

cat <<EOF

done. in the remote CLion UI:
  File -> Manage IDE Settings -> Import Settings...
  path: $DEST
  (if the file picker hides it, type the full path into the location bar)
EOF

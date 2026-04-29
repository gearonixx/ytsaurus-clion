#!/bin/bash
set -euo pipefail

DIST_DIR="${HOME}/.cache/JetBrains/RemoteDev/dist"
SESSION_PREFIX="clion-dl"
DEFAULT_PARALLEL=2
INNER_BACKUP_DIR="${INNER_BACKUP_DIR:-${HOME}/backups}"
OUTER_BACKUP_DIR="${OUTER_BACKUP_DIR:-/workspace/backups}"

usage() {
    cat <<'EOF'
usage:
  clion-backend-download.sh start <url> [N]   start N parallel workers (default 2)
  clion-backend-download.sh status            list sessions, processes, files
  clion-backend-download.sh attach [N]        attach to worker N (default 1)
  clion-backend-download.sh finalize [name]   verify largest .tar.gz, rename,
                                              extract + .expandSucceeded, backup
                                              (auto-detects canonical name from
                                              Gateway-created dir if not given)
  clion-backend-download.sh expand [name]     extract archive into <name-no-ext>/
                                              and touch .expandSucceeded
  clion-backend-download.sh backup [name]     hardlink to $INNER_BACKUP_DIR and
                                              reflink-copy to $OUTER_BACKUP_DIR
  clion-backend-download.sh stop              kill all workers
EOF
    exit 1
}

detect_target() {
    local dir
    dir=$(find "$DIST_DIR" -maxdepth 1 -type d \
        -regextype posix-extended -regex '.*/[a-f0-9]+_[A-Za-z]+-[0-9.]+' \
        -printf '%f\n' 2>/dev/null | head -1)
    [[ -n "$dir" ]] && echo "${dir}.tar.gz"
}

require_tmux() {
    command -v tmux >/dev/null || { echo "error: tmux not installed" >&2; exit 1; }
}

start_worker() {
    local n="$1" url="$2" outfile="$3"
    local session="${SESSION_PREFIX}-${n}"

    if tmux has-session -t "$session" 2>/dev/null; then
        echo "  [$n] session '$session' already running, skipping"
        return
    fi

    tmux new-session -d -s "$session" -c "$DIST_DIR" "
        echo '=== worker $n started '\$(date)' ==='
        while true; do
            wget --continue \
                 --tries=0 --waitretry=15 --retry-connrefused \
                 --timeout=60 --read-timeout=60 \
                 -O '$outfile' \
                 '$url' \
                && break
            echo \"[\$(date)] wget died, retry in 10s...\"
            sleep 10
        done
        echo '=== worker $n DONE '\$(date)' ==='
        echo 'next: clion-backend-download.sh finalize <canonical-name>'
        read -n1
    "
    echo "  [$n] session '$session' -> $outfile"
}

cmd_start() {
    local url="${1:-}" parallel="${2:-$DEFAULT_PARALLEL}"
    [[ -z "$url" ]] && usage
    [[ "$parallel" =~ ^[0-9]+$ && "$parallel" -ge 1 ]] || { echo "N must be a positive integer" >&2; exit 1; }

    require_tmux
    mkdir -p "$DIST_DIR"

    local fname; fname="$(basename "$url")"
    echo "starting $parallel parallel workers in $DIST_DIR"
    for i in $(seq 1 "$parallel"); do
        start_worker "$i" "$url" "${fname}.${i}"
    done
    echo
    echo "monitor: clion-backend-download.sh status"
    echo "attach:  clion-backend-download.sh attach [N]"
}

expand_archive() {
    local archive="$1"
    local extract_dir="${archive%.tar.gz}"

    mkdir -p "$extract_dir"
    if [[ -f "$extract_dir/.expandSucceeded" ]]; then
        echo "  [skip] $extract_dir already expanded"
        return
    fi

    echo "  extracting $archive -> $extract_dir/"
    tar -xzf "$archive" -C "$extract_dir" --strip-components=1
    touch "$extract_dir/.expandSucceeded"
    echo "  [ok] .expandSucceeded set — Gateway will skip its own download/extract"
}

backup_archive() {
    local src="$1"
    local fname; fname="$(basename "$src")"

    mkdir -p "$INNER_BACKUP_DIR"
    local inner="${INNER_BACKUP_DIR}/${fname}"
    if [[ -e "$inner" ]] && [[ "$(stat -c%i "$src")" == "$(stat -c%i "$inner")" ]]; then
        echo "  [skip] inner hardlink already in place: $inner"
    else
        rm -f "$inner"
        ln "$src" "$inner"
        echo "  [ok] inner hardlink: $inner (inode $(stat -c%i "$inner"))"
    fi

    if [[ -d "$(dirname "$OUTER_BACKUP_DIR")" ]]; then
        mkdir -p "$OUTER_BACKUP_DIR"
        local outer="${OUTER_BACKUP_DIR}/${fname}"
        if [[ -f "$outer" ]] && [[ "$(stat -c%s "$outer")" == "$(stat -c%s "$src")" ]]; then
            echo "  [skip] outer copy already exists: $outer"
        else
            cp --reflink=auto "$src" "$outer"
            sha256sum "$src" | awk -v p="$outer" '{print $1"  "p}' > "${outer}.sha256"
            echo "  [ok] outer copy: $outer (+.sha256)"
        fi
    else
        echo "  [warn] outer backup parent $(dirname "$OUTER_BACKUP_DIR") missing — skipping host-side backup" >&2
    fi
}

cmd_status() {
    echo "--- tmux sessions ---"
    tmux ls 2>/dev/null | grep "^${SESSION_PREFIX}-" || echo "  (none)"
    echo
    echo "--- wget processes ---"
    pgrep -af 'wget.*download.jetbrains.com' || echo "  (none)"
    echo
    echo "--- $DIST_DIR ---"
    [[ -d "$DIST_DIR" ]] && ls -lh "$DIST_DIR" || echo "  (does not exist)"
}

cmd_attach() {
    local n="${1:-1}"
    tmux attach -t "${SESSION_PREFIX}-${n}"
}

cmd_finalize() {
    local target="${1:-}"
    if [[ -z "$target" ]]; then
        target="$(detect_target)"
        [[ -z "$target" ]] && {
            echo "error: cannot auto-detect canonical name (no <hash>_<Product>-<build> dir in $DIST_DIR)" >&2
            echo "       pass it explicitly: finalize c2662e4f77c0d_CLion-261.22158.190.tar.gz" >&2
            exit 1
        }
        echo "auto-detected target: $target"
    fi

    cd "$DIST_DIR"
    local pick=""
    local largest=0
    for f in *.tar.gz.*; do
        [[ -f "$f" ]] || continue
        local size; size=$(stat -c%s "$f")
        if (( size > largest )); then
            largest=$size
            pick="$f"
        fi
    done

    [[ -z "$pick" ]] && { echo "error: no candidate *.tar.gz.* in $DIST_DIR" >&2; exit 1; }
    echo "candidate: $pick ($(numfmt --to=iec --suffix=B "$largest"))"

    echo "verifying archive..."
    tar -tzf "$pick" >/dev/null

    echo "stopping all workers..."
    pkill -f 'wget.*download.jetbrains.com' 2>/dev/null || true
    for s in $(tmux ls 2>/dev/null | awk -F: "/^${SESSION_PREFIX}-/ {print \$1}"); do
        tmux kill-session -t "$s" 2>/dev/null || true
    done

    rm -rf "${target%.tar.gz}"
    rm -f *.tar.gz.* 2>/dev/null
    [[ "$pick" != "$target" ]] && mv -v "$pick" "$target" || true
    rm -f "$DIST_DIR"/*.tar.gz.*

    echo "expanding archive..."
    expand_archive "$DIST_DIR/$target"

    echo "creating backups..."
    backup_archive "$DIST_DIR/$target"

    echo "done. on host: Gateway -> Reconnect."
}

cmd_backup() {
    local target="${1:-}"
    if [[ -z "$target" ]]; then
        target="$(detect_target)"
        [[ -z "$target" ]] && { echo "error: cannot auto-detect archive name" >&2; exit 1; }
    fi
    [[ -f "$DIST_DIR/$target" ]] || { echo "error: $DIST_DIR/$target not found" >&2; exit 1; }
    backup_archive "$DIST_DIR/$target"
}

cmd_expand() {
    local target="${1:-}"
    if [[ -z "$target" ]]; then
        target="$(detect_target)"
        [[ -z "$target" ]] && { echo "error: cannot auto-detect archive name" >&2; exit 1; }
    fi
    [[ -f "$DIST_DIR/$target" ]] || { echo "error: $DIST_DIR/$target not found" >&2; exit 1; }
    expand_archive "$DIST_DIR/$target"
}

cmd_stop() {
    pkill -f 'wget.*download.jetbrains.com' 2>/dev/null || true
    for s in $(tmux ls 2>/dev/null | awk -F: "/^${SESSION_PREFIX}-/ {print \$1}"); do
        tmux kill-session -t "$s" 2>/dev/null || true
    done
    echo "stopped"
}

case "${1:-}" in
    start)    shift; cmd_start "$@" ;;
    status)   cmd_status ;;
    attach)   shift; cmd_attach "$@" ;;
    finalize) shift; cmd_finalize "$@" ;;
    expand)   shift; cmd_expand "$@" ;;
    backup)   shift; cmd_backup "$@" ;;
    stop)     cmd_stop ;;
    *)        usage ;;
esac

#!/usr/bin/env bash
set -euo pipefail

LLVM_VERSION="${LLVM_VERSION:-18}"
TOOLS=(llvm-link opt llc llvm-as)
TARGET_DIR="/usr/local/bin"

SUDO=""
if [[ $EUID -ne 0 ]]; then
    SUDO="sudo"
fi

echo "Setting up LLVM ${LLVM_VERSION} symlinks in ${TARGET_DIR}..."

for tool in "${TOOLS[@]}"; do
    src="/usr/bin/${tool}-${LLVM_VERSION}"
    dst="${TARGET_DIR}/${tool}"

    if [[ ! -x "$src" ]]; then
        echo "  [skip] $src not found — install llvm-${LLVM_VERSION} first" >&2
        continue
    fi

    if [[ -L "$dst" ]]; then
        current="$(readlink -f "$dst")"
        if [[ "$current" == "$(readlink -f "$src")" ]]; then
            echo "  [ok]   $dst -> $src (already correct)"
            continue
        fi
        echo "  [fix]  $dst -> $current, replacing with $src"
        $SUDO rm "$dst"
    elif [[ -e "$dst" ]]; then
        echo "  [warn] $dst exists and is not a symlink — leaving alone" >&2
        continue
    fi

    $SUDO ln -s "$src" "$dst"
    echo "  [new]  $dst -> $src"
done

echo "Verifying:"
for tool in "${TOOLS[@]}"; do
    if resolved="$(command -v "$tool" 2>/dev/null)"; then
        printf "  %-12s -> %s\n" "$tool" "$resolved"
    else
        printf "  %-12s NOT FOUND\n" "$tool" >&2
    fi
done

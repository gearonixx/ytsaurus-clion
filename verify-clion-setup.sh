#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${BUILD_DIR:-/workspace/build/conan/build/Release}"
SOURCE_DIR="${SOURCE_DIR:-/workspace/ytsaurus}"
CLANGD_CACHE="${CLANGD_CACHE:-${SOURCE_DIR}/.cache/clangd/index}"

pass() { printf "  \033[32m[ok]\033[0m   %s\n" "$1"; }
fail() { printf "  \033[31m[fail]\033[0m %s\n" "$1" >&2; exit 1; }
warn() { printf "  \033[33m[warn]\033[0m %s\n" "$1" >&2; }

for tool in llvm-link opt llc llvm-as; do
    if path="$(command -v "$tool" 2>/dev/null)"; then
        pass "$tool -> $path"
    else
        fail "$tool not found in PATH (run ./setup-llvm-symlinks.sh)"
    fi
done

if [[ ! -f "$BUILD_DIR/CMakeCache.txt" ]]; then
    fail "CMakeCache.txt missing — configure has not run yet"
fi
pass "CMakeCache.txt present"

if grep -q "^REQUIRED_LLVM_TOOLING_VERSION:" "$BUILD_DIR/CMakeCache.txt"; then
    version="$(grep "^REQUIRED_LLVM_TOOLING_VERSION:" "$BUILD_DIR/CMakeCache.txt" | cut -d= -f2)"
    pass "REQUIRED_LLVM_TOOLING_VERSION=$version"
else
    warn "REQUIRED_LLVM_TOOLING_VERSION not set in cache — relying on PATH lookup"
fi

cc="$BUILD_DIR/compile_commands.json"
if [[ ! -f "$cc" ]]; then
    fail "$cc missing — re-run cmake with -DCMAKE_EXPORT_COMPILE_COMMANDS=ON or use a preset"
fi
size_bytes=$(stat -c%s "$cc")
size_mb=$(( size_bytes / 1024 / 1024 ))
entries=$(grep -c '"file":' "$cc" || true)
if (( entries < 100 )); then
    fail "only $entries entries — looks empty/broken"
fi
pass "compile_commands.json: ${size_mb} MB, ${entries} entries"

# INDEXING!!!
if [[ ! -d "$CLANGD_CACHE" ]]; then
    warn "no index yet — open the project in CLion and wait for first scan"
else
    idx_count=$(find "$CLANGD_CACHE" -maxdepth 1 -name '*.idx' | wc -l)
    idx_size=$(du -sh "$CLANGD_CACHE" 2>/dev/null | cut -f1)
    if (( idx_count == 0 )); then
        warn "index dir empty — CLion has not finished indexing yet"
    else
        pass "indexed files: $idx_count, total size: $idx_size"
    fi
fi

echo "All required checks passed."

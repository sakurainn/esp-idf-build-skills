#!/usr/bin/env bash
# Detect and activate a matching ESP-IDF environment, then run idf.py.
# Works on Linux and macOS. ASCII-only on purpose (no encoding surprises).
#
# Usage:
#   bash build.sh --project ~/work/myapp
#   bash build.sh --project ~/work/myapp --idf-path /opt/esp/idf --clean
#   bash build.sh --project ~/work/myapp --port /dev/ttyUSB0 --flash-monitor
#   bash build.sh --project ~/work/myapp --dry-run

set -eo pipefail

PROJECT=""
IDF_PATH_ARG=""
ACTION="build"
TARGET=""
PORT=""
CLEAN=0
FLASH=0
MONITOR=0
FLASH_MONITOR=0
DRY_RUN=0

usage() {
    sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
}

die() { echo "error: $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
    case "$1" in
        --project)       PROJECT="${2:-}"; shift 2 ;;
        --idf-path)      IDF_PATH_ARG="${2:-}"; shift 2 ;;
        --export-script) EXPORT_ARG="${2:-}"; shift 2 ;;
        --action)        ACTION="${2:-}"; shift 2 ;;
        --target)        TARGET="${2:-}"; shift 2 ;;
        --port)          PORT="${2:-}"; shift 2 ;;
        --clean)         CLEAN=1; shift ;;
        --flash)         FLASH=1; shift ;;
        --monitor)       MONITOR=1; shift ;;
        --flash-monitor) FLASH_MONITOR=1; shift ;;
        --dry-run)       DRY_RUN=1; shift ;;
        -h|--help)       usage; exit 0 ;;
        *)               usage >&2; die "unknown argument: $1" ;;
    esac
done

EXPORT_ARG="${EXPORT_ARG:-}"

case "$ACTION" in
    build|fullclean|reconfigure|menuconfig|size-components|size-files|set-target|erase-flash) ;;
    *) die "unsupported --action: $ACTION" ;;
esac

[ -n "$PROJECT" ] || die "--project is required"
[ -d "$PROJECT" ] || die "project directory not found: $PROJECT"
PROJECT="$(cd "$PROJECT" && pwd)"

# ---------- discovery ----------

# Read the IDF path the build cache was created with (build locks the version).
project_idf_path() {
    local desc="$1/build/project_description.json" out=""
    [ -f "$desc" ] || return 0
    if command -v python3 >/dev/null 2>&1; then
        out="$(python3 - "$desc" <<'PY' 2>/dev/null || true
import json, sys
try:
    with open(sys.argv[1]) as f:
        p = json.load(f).get("idf_path")
    if p:
        print(p)
except Exception:
    pass
PY
)"
        if [ -n "$out" ]; then echo "$out"; return 0; fi
    fi
    sed -n 's/.*"idf_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$desc" | head -n 1
}

first_existing() {
    local p
    for p in "$@"; do
        [ -n "$p" ] && [ -f "$p" ] && { echo "$p"; return 0; }
    done
    return 1
}

# Probe roots: declared tools path, official installer layout, common manual-clone locations.
PROBE_ROOTS="${IDF_TOOLS_PATH:-} $HOME/.espressif/frameworks $HOME/esp $HOME/esp-idf /opt/esp /opt/esp/idf /opt/esp-idf /usr/local/share/esp-idf"

probe_install() {
    local r c
    for r in $PROBE_ROOTS; do
        for c in "$r"/export.sh "$r"/esp-idf/export.sh "$r"/esp-idf-*/export.sh; do
            [ -f "$c" ] && { echo "$c"; return 0; }
        done
    done
    return 1
}

EXPORT_SH=""
SOURCE=""
PINNED=0

if   [ -n "$EXPORT_ARG" ];    then EXPORT_SH="$EXPORT_ARG";  SOURCE="--export-script"; PINNED=1
elif [ -n "$IDF_PATH_ARG" ];   then EXPORT_SH="$IDF_PATH_ARG/export.sh"; SOURCE="--idf-path"; PINNED=1
elif [ -n "${IDF_PATH:-}" ];   then EXPORT_SH="$IDF_PATH/export.sh"; SOURCE="IDF_PATH"; PINNED=1
else
    proj_path="$(project_idf_path "$PROJECT" || true)"
    if [ -n "$proj_path" ] && [ -f "$proj_path/export.sh" ]; then
        EXPORT_SH="$proj_path/export.sh"; SOURCE="project_description.json"; PINNED=1
    else
        if probe="$(probe_install)"; then
            EXPORT_SH="$probe"; SOURCE="probe:$probe"
        elif command -v idf.py >/dev/null 2>&1; then
            EXPORT_SH=""; SOURCE="PATH:$(command -v idf.py)"
        fi
    fi
fi

if [ -z "$EXPORT_SH" ]; then
    die "No usable ESP-IDF environment. Set IDF_PATH, pass --idf-path/--export-script, or install ESP-IDF first."
fi

if [ -n "$EXPORT_SH" ] && [ ! -f "$EXPORT_SH" ]; then
    die "activation script not found: $EXPORT_SH"
fi

if [ -n "$EXPORT_SH" ]; then
    echo "==> activation: $EXPORT_SH"
    echo "==> picked from: $SOURCE"
    if [ "$PINNED" -eq 0 ]; then
        echo "warning: no IDF version recorded for this project and none given explicitly;" >&2
        echo "warning: picked a detected install. Pin it with --idf-path if the build fails," >&2
        echo "warning: and run 'idf.py fullclean' after switching versions." >&2
    fi
else
    echo "==> no activation script; using idf.py on PATH ($SOURCE)"
fi
echo "==> project   : $PROJECT"
[ -n "$PORT" ] && echo "==> port      : $PORT"

if [ "$DRY_RUN" -eq 1 ]; then
    echo "==> dry-run done."
    exit 0
fi

# Activate in this same shell so the environment survives.
if [ -n "$EXPORT_SH" ]; then
    set +u   # export.sh may read unset variables
    . "$EXPORT_SH"
    set -u
fi
cd "$PROJECT"

run_idf() {
    echo "==> idf.py $*"
    idf.py "$@"
}

if [ "$CLEAN" -eq 1 ]; then
    run_idf fullclean
fi

PORT_ARGS=()
if [ -n "$PORT" ]; then
    PORT_ARGS=(-p "$PORT")
elif [ "$FLASH$MONITOR$FLASH_MONITOR" -ne 0 ]; then
    echo "hint: no --port given. List candidates with:" >&2
    echo "      ls /dev/serial/by-id/ 2>/dev/null || ls /dev/cu.* 2>/dev/null || ls /dev/ttyUSB* 2>/dev/null" >&2
fi

if   [ "$FLASH_MONITOR" -eq 1 ]; then run_idf "${PORT_ARGS[@]}" flash monitor
elif [ "$FLASH" -eq 1 ];         then run_idf "${PORT_ARGS[@]}" flash
elif [ "$MONITOR" -eq 1 ];       then run_idf "${PORT_ARGS[@]}" monitor
elif [ "$ACTION" = "set-target" ]; then
    [ -n "$TARGET" ] || die "--action set-target requires --target <chip>"
    run_idf set-target "$TARGET"
else
    run_idf "${PORT_ARGS[@]}" "$ACTION"
fi

echo "==> done"
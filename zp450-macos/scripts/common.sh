#!/bin/bash
#
# Shared configuration and helpers for the ZP 450 macOS printer application.
#

set -euo pipefail

# --- Pinned upstream versions -------------------------------------------------
# LPrint master is explicitly marked "not suitable for packaging" by upstream,
# so we build from tagged releases only.
PAPPL_VERSION="${PAPPL_VERSION:-1.4.9}"
LPRINT_VERSION="${LPRINT_VERSION:-1.4.0}"

# --- Installation layout ------------------------------------------------------
PREFIX="${PREFIX:-/usr/local}"
BUILD_DIR="${BUILD_DIR:-/tmp/zp450-build}"
PLIST_LABEL="org.zp450.lprint"
PLIST_PATH="/Library/LaunchDaemons/${PLIST_LABEL}.plist"
LOG_FILE="/Library/Logs/lprint-zp450.log"

# --- Queue configuration ------------------------------------------------------
# LPRINT_QUEUE  - the queue inside the printer application (IPP resource name)
# CUPS_QUEUE    - the queue macOS shows in Printers & Scanners / the print dialog
# LPRINT_PORT   - TCP port the printer application listens on (localhost + DNS-SD)
LPRINT_QUEUE="${LPRINT_QUEUE:-zp450}"
CUPS_QUEUE="${CUPS_QUEUE:-ZP450}"
LPRINT_PORT="${LPRINT_PORT:-8100}"

# --- Printer defaults ---------------------------------------------------------
# The ZP 450 is a 203dpi, 4-inch direct thermal printer (a rebadged GK420d).
# It ships with EPL2 firmware; dual-firmware units also speak ZPL II.
DRIVER="${DRIVER:-epl2_4inch-203dpi-dt_zp450}"
DRIVER_FALLBACK="${DRIVER_FALLBACK:-epl2_4inch-203dpi-dt}"
MEDIA="${MEDIA:-na_index-4x6_4x6in}"
DARKNESS="${DARKNESS:-50}"

LPRINT="${PREFIX}/bin/lprint"

# --- Output helpers -----------------------------------------------------------
if [ -t 1 ]; then
  _c_bold=$'\033[1m'; _c_red=$'\033[31m'; _c_yellow=$'\033[33m'
  _c_green=$'\033[32m'; _c_reset=$'\033[0m'
else
  _c_bold=''; _c_red=''; _c_yellow=''; _c_green=''; _c_reset=''
fi

info()  { printf '%s==>%s %s\n' "$_c_bold" "$_c_reset" "$*"; }
warn()  { printf '%swarning:%s %s\n' "$_c_yellow" "$_c_reset" "$*" >&2; }
error() { printf '%serror:%s %s\n' "$_c_red" "$_c_reset" "$*" >&2; }
ok()    { printf '%s  ok%s %s\n' "$_c_green" "$_c_reset" "$*"; }
die()   { error "$@"; exit 1; }

# run_root CMD...  - run a command as root, using sudo only when needed.
run_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

# lprint_root SUBCOMMAND...  - talk to the system (root) LPrint server.
#
# PAPPL clients reach the server over a UNIX domain socket whose path depends on
# the caller's uid: root uses /private/var/run/lprint.sock, everyone else gets a
# per-user socket in $TMPDIR. Our daemon runs as root, so every administrative
# command has to run as root too.
lprint_root() {
  run_root "$LPRINT" "$@"
}

# Confirm with the user unless --yes was passed (ASSUME_YES=1).
confirm() {
  local prompt="$1"
  if [ "${ASSUME_YES:-0}" = "1" ]; then
    return 0
  fi
  read -r -p "$prompt [y/N] " reply
  case "$reply" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

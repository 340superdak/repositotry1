#!/bin/bash
#
# Remove everything install.sh set up: the macOS printer, the LPrint queue,
# the LaunchDaemon, and (optionally) the installed binaries.
#
# Usage: ./uninstall.sh [--purge] [-y|--yes]
#
#   --purge   also delete the installed lprint/PAPPL files under the prefix
#   -y        do not prompt
#

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PURGE=0
export ASSUME_YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --purge) PURGE=1 ;;
    -y|--yes) export ASSUME_YES=1 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

# shellcheck source=scripts/common.sh
source "$HERE/scripts/common.sh"

info "Removing the macOS printer '$CUPS_QUEUE'"
if lpstat -p "$CUPS_QUEUE" >/dev/null 2>&1; then
  run_root lpadmin -x "$CUPS_QUEUE" && ok "removed"
else
  ok "not present"
fi

info "Removing the LPrint queue '$LPRINT_QUEUE'"
if [ -x "$LPRINT" ] && lprint_root printers 2>/dev/null | grep -qx "$LPRINT_QUEUE"; then
  lprint_root delete -d "$LPRINT_QUEUE" && ok "removed"
else
  ok "not present"
fi

info "Unloading the LaunchDaemon"
if [ -f "$PLIST_PATH" ]; then
  run_root launchctl bootout "system/${PLIST_LABEL}" 2>/dev/null \
    || run_root launchctl unload -w "$PLIST_PATH" 2>/dev/null \
    || true
  run_root rm -f "$PLIST_PATH"
  ok "removed $PLIST_PATH"
else
  ok "not present"
fi

if [ "$PURGE" = "1" ]; then
  if confirm "Delete installed files under ${PREFIX}?"; then
    info "Deleting installed files"
    run_root rm -f "${PREFIX}/bin/lprint"
    run_root rm -f "${PREFIX}/lib/libpappl."*
    run_root rm -rf "${PREFIX}/include/pappl"
    run_root rm -f "${PREFIX}/lib/pkgconfig/pappl.pc"
    run_root rm -f "${PREFIX}/share/man/man1/lprint"*
    run_root rm -f "$LOG_FILE"
    # Root-mode state and spool locations on macOS (PAPPL_STATEDIR=/private/var).
    run_root rm -f /private/var/lib/lprint.state
    run_root rm -rf /private/var/spool/lprint
    ok "purged"
  fi
else
  info "Leaving ${PREFIX}/bin/lprint and PAPPL in place (use --purge to delete)"
fi

echo
ok "Uninstall complete"

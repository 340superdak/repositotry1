#!/bin/bash
#
# Set up a Zebra ZP 450 on macOS 26 as a driverless printer.
#
# This builds a printer application (PAPPL + LPrint) that converts print jobs
# to EPL2/ZPL and publishes the printer over IPP Everywhere, then registers it
# with macOS. It does not install any PPD or CUPS filter driver.
#
# Usage: ./install.sh [options]
#
#   --zpl               use the ZPL driver instead of EPL2 (dual-firmware units)
#   --driver NAME       use a specific LPrint driver name
#   --media SIZE        default media size (default: na_index-4x6_4x6in)
#   --darkness N        print darkness 0-100 (default: 50)
#   --queue NAME        LPrint queue name (default: zp450)
#   --cups-queue NAME   macOS printer name (default: ZP450)
#   --port N            port for the printer application (default: 8100)
#   --prefix DIR        install prefix (default: /usr/local)
#   --device-uri URI    skip auto-detection and use this device URI
#   --skip-build        reuse an already-built lprint
#   --no-cups-queue     set up LPrint only, add the printer in System Settings
#   -y, --yes           do not prompt
#   -h, --help          show this help
#

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SKIP_BUILD=0
export SKIP_CUPS_QUEUE=0
export ASSUME_YES=0

usage() { sed -n '2,/^$/p' "$0" | sed 's/^#\{1,2\} \{0,1\}//'; exit 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    --zpl)          export DRIVER="zpl_4inch-203dpi-dt_zp450" DRIVER_FALLBACK="zpl_4inch-203dpi-dt" ;;
    --driver)       export DRIVER="$2"; shift ;;
    --media)        export MEDIA="$2"; shift ;;
    --darkness)     export DARKNESS="$2"; shift ;;
    --queue)        export LPRINT_QUEUE="$2"; shift ;;
    --cups-queue)   export CUPS_QUEUE="$2"; shift ;;
    --port)         export LPRINT_PORT="$2"; shift ;;
    --prefix)       export PREFIX="$2"; shift ;;
    --device-uri)   export DEVICE_URI="$2"; shift ;;
    --skip-build)   SKIP_BUILD=1 ;;
    --no-cups-queue) export SKIP_CUPS_QUEUE=1 ;;
    -y|--yes)       export ASSUME_YES=1 ;;
    -h|--help)      usage ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

# shellcheck source=scripts/common.sh
source "$HERE/scripts/common.sh"

preflight() {
  info "Checking this Mac"

  if [ "$(uname -s)" != "Darwin" ]; then
    die "This installer only runs on macOS."
  fi

  local os_version os_major
  os_version="$(sw_vers -productVersion)"
  os_major="${os_version%%.*}"
  ok "macOS $os_version ($(uname -m))"

  if [ "$os_major" -lt 26 ]; then
    warn "Written and tested against macOS 26. On $os_version everything here"
    warn "should still work, since it relies only on IPP Everywhere."
  fi

  # A raw CUPS queue on the same USB device keeps the interface busy and stops
  # the printer application from claiming it.
  if lpstat -v 2>/dev/null | grep -qi 'usb.*zebra\|usb.*ztc'; then
    warn "An existing CUPS queue is bound directly to the Zebra over USB:"
    lpstat -v 2>/dev/null | grep -i 'usb.*zebra\|usb.*ztc' | sed 's/^/    /' >&2
    warn "It can block the printer application from opening the device."
    if confirm "Remove that queue now?"; then
      local q
      while read -r q; do
        q="${q#device for }"; q="${q%%:*}"
        if [ -n "$q" ]; then
          if run_root lpadmin -x "$q"; then ok "removed $q"; else warn "could not remove $q"; fi
        fi
      done < <(lpstat -v 2>/dev/null | grep -i 'usb.*zebra\|usb.*ztc')
    else
      warn "Leaving it in place - printing may fail with a busy device."
    fi
  fi

  if system_profiler SPUSBDataType 2>/dev/null | grep -qi 'zebra\|ztc'; then
    ok "Zebra printer detected on USB"
  else
    warn "No Zebra printer detected on USB. Connect and power it on;"
    warn "the build will still run, but queue setup needs the printer."
  fi
}

main() {
  preflight

  if [ "$SKIP_BUILD" = "1" ]; then
    info "Skipping build (--skip-build)"
    [ -x "$LPRINT" ] || die "$LPRINT is not installed - run without --skip-build"
  else
    bash "$HERE/scripts/build.sh"
  fi

  bash "$HERE/scripts/setup-queue.sh"

  echo
  info "Done"
  echo "  Printer application : $LPRINT (queue '$LPRINT_QUEUE', port $LPRINT_PORT)"
  if [ "${SKIP_CUPS_QUEUE:-0}" != "1" ]; then
    echo "  macOS printer       : $CUPS_QUEUE"
  fi
  echo "  Web interface       : http://localhost:${LPRINT_PORT}/"
  echo "  Log file            : $LOG_FILE"
  echo
  echo "  Print a test label  : $HERE/scripts/test-print.sh"
  echo "  Diagnose detection  : $HERE/scripts/device-id.sh"
  echo "  Remove everything   : $HERE/uninstall.sh"
}

main "$@"

#!/bin/bash
#
# Print what macOS and LPrint actually see for the connected ZP 450, and which
# driver LPrint's auto-detection would pick. Run this first when the printer is
# not found, or when reporting a problem.
#

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$HERE/common.sh"

info "USB devices reported by macOS (Zebra only)"
if system_profiler SPUSBDataType 2>/dev/null | grep -iA 8 'zebra\|ZTC\|ZP 450'; then
  :
else
  warn "No Zebra device found in system_profiler output."
  warn "Check the USB cable and that the printer is powered on."
fi

echo
if [ ! -x "$LPRINT" ]; then
  warn "LPrint is not installed at $LPRINT - run install.sh first."
  exit 0
fi

info "Devices visible to LPrint"
# -o verbose=1 adds the IEEE-1284 device ID under each device URI.
lprint_root devices -o verbose=1 || warn "Could not query devices (is the daemon running?)"

echo
info "Driver LPrint would auto-select"
DEVICE_ID="${1:-}"
if [ -z "$DEVICE_ID" ]; then
  echo "  Pass a device ID to test auto-detection, for example:"
  echo "    $0 'MANUFACTURER:Zebra Technologies ;COMMAND SET:EPL;MODEL:ZTC ZP 450;'"
else
  # The value needs literal double quotes inside the -o argument: CUPS option
  # parsing splits on spaces, and every device ID contains them.
  "$LPRINT" drivers -o "device-id=\"$DEVICE_ID\""
fi

echo
info "Existing CUPS queues pointing at a Zebra USB device"
if lpstat -v 2>/dev/null | grep -i 'usb.*zebra\|usb.*ZTC'; then
  warn "A raw CUPS queue is bound to the printer over USB."
  warn "It can hold the USB interface open and block the printer application."
  warn "Remove it with: sudo lpadmin -x QUEUE_NAME"
else
  ok "none (good)"
fi

#!/bin/bash
#
# Print a test label, either straight through the printer application
# (--direct, the default) or through the macOS print queue (--cups).
#
# The direct path proves the driver and the USB link work. The CUPS path
# additionally proves that what apps print reaches the printer.
#

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$HERE/common.sh"

MODE="direct"
case "${1:-}" in
  --cups)   MODE="cups" ;;
  --direct|"") MODE="direct" ;;
  *) die "Usage: $0 [--direct|--cups]" ;;
esac

if [ "$MODE" = "direct" ]; then
  # LPrint recognizes a file whose first 17 bytes are "T*E*S*T*P*A*G*E*\0"
  # as a request for its built-in self test page, rendered to the loaded media.
  TESTFILE="$(mktemp -t lprint-testpage)"
  printf 'T*E*S*T*P*A*G*E*\0' >"$TESTFILE"

  info "Printing LPrint's built-in test page to '$LPRINT_QUEUE'"
  lprint_root submit -d "$LPRINT_QUEUE" "$TESTFILE"
  rm -f "$TESTFILE"

  echo
  info "Queue status"
  lprint_root status -d "$LPRINT_QUEUE" || true
else
  command -v lp >/dev/null 2>&1 || die "lp not found"

  info "Printing a test page through the macOS queue '$CUPS_QUEUE'"
  # Any PDF works; this one ships with macOS.
  SAMPLE="/System/Library/Frameworks/CoreServices.framework/Resources/Certificates.pdf"
  if [ ! -f "$SAMPLE" ]; then
    SAMPLE="$(mktemp -t zp450-test).txt"
    printf 'ZP 450 test label\n%s\n' "$(date)" >"$SAMPLE"
  fi

  lp -d "$CUPS_QUEUE" -o media="$MEDIA" "$SAMPLE"

  echo
  info "CUPS queue status"
  lpstat -p "$CUPS_QUEUE" -o || true
fi

echo
ok "Job submitted. If nothing prints, see docs/TROUBLESHOOTING.md"

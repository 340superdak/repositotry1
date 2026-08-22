#!/bin/bash
#
# Install the LaunchDaemon, create the LPrint queue for the ZP 450, and expose
# it to macOS as a normal printer so it appears in every app's print dialog.
#

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$HERE/common.sh"

PLIST_TEMPLATE="$HERE/../launchd/${PLIST_LABEL}.plist.in"

install_daemon() {
  info "Installing the LPrint LaunchDaemon"

  local tmp
  tmp="$(mktemp)"
  sed -e "s|@PLIST_LABEL@|${PLIST_LABEL}|g" \
      -e "s|@PREFIX@|${PREFIX}|g" \
      -e "s|@LPRINT_PORT@|${LPRINT_PORT}|g" \
      -e "s|@LOG_FILE@|${LOG_FILE}|g" \
      "$PLIST_TEMPLATE" >"$tmp"

  run_root install -m 0644 -o root -g wheel "$tmp" "$PLIST_PATH"
  rm -f "$tmp"

  # Reload cleanly if a previous version is already running.
  run_root launchctl bootout "system/${PLIST_LABEL}" 2>/dev/null || true
  if ! run_root launchctl bootstrap system "$PLIST_PATH" 2>/dev/null; then
    # Fallback for hosts where bootstrap is unavailable or the job is cached.
    run_root launchctl load -w "$PLIST_PATH"
  fi

  ok "daemon loaded (${PLIST_LABEL})"
}

wait_for_server() {
  info "Waiting for the printer application on port ${LPRINT_PORT}"
  for _ in $(seq 1 30); do
    if nc -z localhost "$LPRINT_PORT" 2>/dev/null; then
      ok "server is listening"
      return 0
    fi
    sleep 1
  done

  error "Printer application did not start on port ${LPRINT_PORT}."

  if [ -s "$LOG_FILE" ]; then
    error "Last lines of $LOG_FILE:"
    run_root tail -20 "$LOG_FILE" | sed 's/^/    /' >&2
  else
    error "$LOG_FILE is empty - the server exited before it could log anything,"
    error "which usually means it could not start at all rather than failed later."
  fi

  error "To see the failure directly, run the same command the daemon runs:"
  error "    sudo ${PREFIX}/bin/lprint server -o server-port=${LPRINT_PORT} -o log-level=debug"
  die "Printer application did not start."
}

# Echo the device URI of the attached Zebra printer, if there is exactly one.
detect_device_uri() {
  local uris
  uris="$(lprint_root devices 2>/dev/null | grep -i 'zebra\|ztc' || true)"

  if [ -z "$uris" ]; then
    return 1
  fi

  if [ "$(printf '%s\n' "$uris" | wc -l | tr -d ' ')" -gt 1 ]; then
    warn "More than one Zebra device is attached:"
    printf '%s\n' "$uris" | sed 's/^/    /' >&2
    warn "Re-run with DEVICE_URI=... to choose one."
    return 1
  fi

  printf '%s\n' "$uris"
}

select_driver() {
  # Prefer the ZP 450 specific driver from our patch, fall back to the generic
  # 4-inch driver if LPrint was built without it.
  if "$LPRINT" drivers | grep -q "^${DRIVER} "; then
    printf '%s\n' "$DRIVER"
  else
    warn "Driver ${DRIVER} is not available; using ${DRIVER_FALLBACK}"
    printf '%s\n' "$DRIVER_FALLBACK"
  fi
}

create_lprint_queue() {
  local device_uri driver
  device_uri="${DEVICE_URI:-}"

  if [ -z "$device_uri" ]; then
    info "Looking for the printer"
    if ! device_uri="$(detect_device_uri)"; then
      error "No Zebra printer found over USB."
      error "Check power and cabling, then run: $HERE/device-id.sh"
      exit 1
    fi
  fi
  ok "device: $device_uri"

  driver="$(select_driver)"
  ok "driver: $driver"

  if lprint_root printers 2>/dev/null | grep -qx "$LPRINT_QUEUE"; then
    info "Queue '$LPRINT_QUEUE' already exists - updating it"
    lprint_root modify -d "$LPRINT_QUEUE" \
      -o media-ready="$MEDIA" \
      -o printer-darkness-configured="$DARKNESS"
  else
    info "Creating LPrint queue '$LPRINT_QUEUE'"
    # Only printer-level options here: passing a job default such as
    # "-o media=..." makes PAPPL 1.4.9 write the job attribute group before the
    # printer group, and the server rejects the request ("Attribute groups are
    # out of order"). media-ready sets the default media on its own.
    lprint_root add -d "$LPRINT_QUEUE" -v "$device_uri" -m "$driver" \
      -o media-ready="$MEDIA" \
      -o printer-darkness-configured="$DARKNESS"
  fi

  lprint_root default -d "$LPRINT_QUEUE"
  ok "LPrint queue ready"
}

create_cups_queue() {
  local uri="ipp://localhost:${LPRINT_PORT}/ipp/print/${LPRINT_QUEUE}"

  info "Adding '${CUPS_QUEUE}' to macOS printers"

  # -m everywhere is the driverless (IPP Everywhere) path: CUPS asks the printer
  # application for its capabilities instead of loading a deprecated PPD driver.
  if run_root lpadmin -p "$CUPS_QUEUE" -E -v "$uri" -m everywhere \
      -o printer-is-shared=false \
      -D "Zebra ZP 450" \
      -L "USB"; then
    ok "queue '${CUPS_QUEUE}' added"
  else
    error "lpadmin failed. The printer application is running, so you can still"
    error "add the printer by hand: System Settings > Printers & Scanners > Add,"
    error "then pick '${LPRINT_QUEUE}' from the Bonjour list."
    return 1
  fi
}

main() {
  install_daemon
  wait_for_server
  create_lprint_queue

  if [ "${SKIP_CUPS_QUEUE:-0}" = "1" ]; then
    info "Skipping the macOS print queue (--no-cups-queue)"
  else
    create_cups_queue
  fi
}

main "$@"

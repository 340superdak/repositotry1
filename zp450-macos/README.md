# Zebra ZP 450 on macOS 26

A working print path for the Zebra ZP 450 thermal label printer on macOS 26,
built as a **printer application** rather than as a classic printer driver.

The printer ends up in System Settings ▸ Printers & Scanners like any other
printer, and prints from any app's print dialog.

## Why not a "real" driver

The ZP 450 needs no kernel driver: it is a USB printer-class device that macOS
already enumerates. What it needs is *page-description translation* — turning a
rasterized page into EPL2 or ZPL byte streams — plus a print queue.

Historically that meant a CUPS PPD plus a filter binary. Apple has been
deprecating that mechanism for several releases; `lpadmin` now warns that
"printer drivers are deprecated". That said, macOS 26 still ships and uses a
working Zebra ZPL driver for this printer today — the deprecation is a
direction of travel, not a current outage. What this buys you is insulation
from the day that changes.

The supported direction is driverless printing (IPP Everywhere). So instead of
shipping a filter, this sets up a small local IPP Everywhere print service that
owns the USB connection and speaks EPL2/ZPL to the printer:

```
  App print dialog
        │  (standard macOS printing)
        ▼
  CUPS queue "ZP450"  ──ipp://localhost:8100──▶  LPrint printer application
        (driverless, -m everywhere)                    │  raster ➞ EPL2/ZPL
                                                       ▼
                                                  ZP 450 over USB
```

Nothing in this path is deprecated: macOS sees a standards-compliant IPP
Everywhere printer, exactly as it would see an AirPrint device on the network.

## What gets installed

| Component | Version | Location |
|---|---|---|
| [PAPPL](https://www.msweet.org/pappl) — printer application framework | 1.4.9 | `/usr/local/lib`, `/usr/local/include` |
| [LPrint](https://www.msweet.org/lprint) — label printer application | 1.4.0 | `/usr/local/bin/lprint` |
| ZP 450 driver entries | this repo | patch applied at build time |
| LaunchDaemon | this repo | `/Library/LaunchDaemons/org.zp450.lprint.plist` |

Both upstream projects are by Michael Sweet, the author of CUPS itself, and are
Apache-2.0 licensed. Releases are pinned and checksum-verified; upstream marks
the LPrint `master` branch as unsuitable for packaging, so only tagged releases
are used.

## Requirements

- macOS 26 (works on earlier versions too — nothing here is 26-specific)
- Xcode command line tools (`xcode-select --install`)
- [Homebrew](https://brew.sh), for `libusb`, `libpng`, `jpeg-turbo`, `openssl@3`
- Admin rights (the daemon runs as root so it can claim the USB interface)

## Install

```sh
cd zp450-macos
./install.sh
```

Then print a test label:

```sh
./scripts/test-print.sh          # direct through the printer application
./scripts/test-print.sh --cups   # through the macOS print queue
```

### Options

```
--zpl               use ZPL instead of EPL2 (dual-firmware units)
--driver NAME       use a specific LPrint driver
--media SIZE        default media (default: na_index-4x6_4x6in)
--darkness N        print darkness, 0-100 (default: 50)
--queue NAME        LPrint queue name (default: zp450)
--cups-queue NAME   macOS printer name (default: ZP450)
--port N            printer application port (default: 8100)
--device-uri URI    skip detection, use this device URI
--skip-build        reuse an already-built lprint
--no-cups-queue     set up LPrint only; add the printer via System Settings
-y, --yes           do not prompt
```

## EPL2 or ZPL?

The ZP 450 shipped in two firmware flavors. Stock units are EPL2 only, which is
why EPL2 is the default here. Dual-firmware units (`ZP450-0501-0000A` and
similar) also accept ZPL, which is worth using — LPrint's ZPL driver reports
printer status and can read the loaded media configuration back from the
printer, which the EPL2 driver cannot.

To find out which yours speaks without guessing: if macOS already has a queue
for the printer, open System Settings ▸ Printers & Scanners and read **Kind**.
"Zebra ZPL Label Printer" means the unit accepts ZPL, so install with `--zpl`.
You can also read the command set directly from the device ID with
`./scripts/device-id.sh`.

If unsure, install with the default. If the printer feeds a blank label instead
of printing, try the other language:

```sh
./install.sh --zpl --skip-build
```

## Media sizes

The driver advertises the standard 4-inch label sizes; `na_index-4x6_4x6in`
(4×6" shipping label) is the default. Common alternatives:
`oe_4x2-label_4x2in`, `oe_2.25x1.25-label_2.25x1.25in`,
`oe_3x1-label_3x1in`, `roll_max_4x100in` for continuous stock.

To change it after install:

```sh
sudo lprint modify -d zp450 -o media-ready=oe_4x2-label_4x2in
```

`media-ready` is the media actually loaded in the printer, and it also becomes
the default for new jobs. Do not also pass `-o media=...`: PAPPL 1.4.9 writes
that job attribute into an IPP group that comes before the printer group, and
the server rejects the whole request with "Attribute groups are out of order".

## Day-to-day use

```sh
sudo lprint status -d zp450            # printer state
sudo lprint jobs -d zp450              # pending jobs
sudo lprint printers                   # all queues
sudo lprint drivers                    # available drivers
open http://localhost:8100/            # web interface (darkness, speed, media)
```

Administrative `lprint` commands need `sudo`: PAPPL clients reach the server
over a UNIX domain socket whose path depends on the caller's uid, and the
daemon runs as root.

Labels can also be sent straight to the printer, bypassing rasterization —
useful for programmatic label generation:

```sh
printf '\nN\nA50,50,0,3,1,1,N,"HELLO"\nP1\n' > label.epl
sudo lprint submit -d zp450 label.epl
```

LPrint recognizes raw EPL2 (files starting with `\nN\n`), raw ZPL (files
starting with `^XA`), PNG images, and Apple/PWG raster.

## Uninstall

```sh
./uninstall.sh            # remove queues and the daemon
./uninstall.sh --purge    # also delete the installed binaries and state
```

## Layout

```
install.sh                  orchestrates everything
uninstall.sh                undoes it
scripts/common.sh           shared configuration and helpers
scripts/build.sh            fetch, verify, patch and build PAPPL + LPrint
scripts/setup-queue.sh      LaunchDaemon, LPrint queue, macOS print queue
scripts/device-id.sh        diagnostics: what is attached, what would be picked
scripts/test-print.sh       print a test label
patches/                    ZP 450 driver entries for LPrint
launchd/                    LaunchDaemon template
docs/TROUBLESHOOTING.md     when it does not work
```

## Status

**Read this before investing time here.** On macOS 26 as of August 2026, Apple
still ships a working "Zebra ZPL Label Printer" driver (version 2.3) that
drives a ZP 450 out of the box — a Mac Studio running 26 prints to one happily
with no third-party software at all. The argument for this printer application
is *future-proofing* against Apple eventually removing that driver, not a
present-day breakage. If the bundled driver works for you, using it is the
reasonable choice.

Verified, by building on Linux and printing to a simulated printer:

- The patch applies and compiles against LPrint 1.4.0; all four ZP 450 driver
  entries register.
- Auto-detection resolves a real unit's device ID (`MODEL:ZTC ZP 450-200dpi`,
  captured from hardware) to the ZP 450 EPL or ZPL driver as appropriate,
  resolves the shorter `ZTC ZP 450` to the `_alt` entries, and does not
  hijack a GX420d.
- A test page renders to correct EPL2: `q816` label width, `D7` darkness, 1218
  raster rows for a 4×6" label at 203dpi, terminated by `P1`.

Known broken:

- **Universal build flags break the build on Apple Silicon.** PAPPL and LPrint
  both request `-arch x86_64 -arch arm64` on macOS 11+, and Homebrew's
  libraries are arm64-only, so the x86_64 slice fails to link — reported as
  undefined `ASN1_*` symbols "for architecture x86_64", which looks like an
  OpenSSL problem and is not. `build.sh` rewrites `Makedefs` after `configure`
  to build native-only. Found on a macOS 26 Mac Studio; the fix has not yet
  been confirmed end to end there.
- The macOS-specific runtime parts (LaunchDaemon, USB claim via libusb, the
  `lpadmin -m everywhere` queue) have therefore never been executed.
- The daemon runs as root. That is what upstream's own macOS package does, and
  it is needed for libusb to claim the printer interface.
- Only one process can own the USB device. A leftover raw CUPS queue pointed at
  the same printer will fight the printer application; `install.sh` detects this
  and offers to remove it.

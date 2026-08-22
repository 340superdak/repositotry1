# Troubleshooting

Start here:

```sh
./scripts/device-id.sh
tail -50 /Library/Logs/lprint-zp450.log
```

## The printer is not detected

`lprint devices` lists nothing, or nothing matching Zebra.

1. Confirm macOS sees the hardware at all:
   `system_profiler SPUSBDataType | grep -iA8 zebra`
   Nothing there means it is a cable, power, or port problem, not software.
2. Confirm the daemon is running as root:
   `sudo launchctl print system/org.zp450.lprint | head -20`
   LPrint uses libusb, which cannot open the interface as a normal user.
3. Confirm nothing else holds the device. A raw CUPS queue bound to
   `usb://Zebra...` will keep the interface busy:
   `lpstat -v | grep -i zebra` then `sudo lpadmin -x THAT_QUEUE`.

## The printer is detected but auto-detection picks the wrong driver

The install script always passes `-m` explicitly, so this only matters for
manual `lprint add` runs. To see what auto-detection would choose:

```sh
sudo lprint devices -o verbose=1          # prints the IEEE-1284 device ID
lprint drivers -o 'device-id="...paste it here..."'
```

The inner double quotes matter: CUPS option parsing splits values on spaces,
and every device ID contains them. Without them the ID parses to nothing and no
driver is reported.

The ZP 450 entries in `patches/0001-add-zebra-zp450-driver-entries.patch` match
on `COMMAND SET` plus `MODEL`. Two model strings are covered: `ZTC ZP 450-200dpi`
(observed on real hardware) and `ZTC ZP 450` (the `_alt` entries). Matching is
all-or-nothing per key, so a unit reporting some third string matches neither.

What that costs you depends on the language. An EPL unit still auto-detects,
because upstream's generic `epl2_4inch-203dpi-dt` carries `COMMAND SET:EPL;`.
A ZPL unit auto-detects *nothing* — every generic ZPL entry upstream has an
empty device ID — so `lprint` cannot guess and you must name the driver with
`-m`. The install script always passes `-m` explicitly, so setup works either
way; auto-detection only affects manual `lprint add` runs.

To make the specific entry match your unit, edit the `MODEL:` value in the patch
to the exact string from `lprint devices -o verbose=1` and rebuild:

```sh
./install.sh          # rebuilds LPrint with the updated patch
```

## A label feeds but comes out blank

Almost always the wrong printer language. Stock ZP 450s are EPL2 only;
dual-firmware units accept both. Switch and retry:

```sh
sudo lprint delete -d zp450
./install.sh --zpl --skip-build
./scripts/test-print.sh
```

## Printing is too light or too dark

```sh
sudo lprint modify -d zp450 -o printer-darkness-configured=75
```

Range is 0–100. Direct thermal stock varies a lot; 50 is a middle setting.
Print speed can be lowered for better quality on dense labels via the web
interface at <http://localhost:8100/>.

## Labels print at the wrong size, or the printer feeds several labels per job

The media size in the queue does not match the stock that is loaded:

```sh
sudo lprint modify -d zp450 -o media-ready=oe_4x2-label_4x2in
sudo lprint options -d zp450        # lists every supported size
```

Set `media-ready` only. Adding `-o media=...` fails on PAPPL 1.4.9 with
"Attribute groups are out of order" (on `add`) or "Unsupported media-default
keyword value" (on `modify`); `media-ready` sets the job default by itself.

If the printer cannot find the gap between labels it will feed continuously.
Run the printer's own auto-calibration (hold the feed button until the status
light blinks — see the ZP 450 manual), then reprint. For continuous stock, set
`-o media-tracking=continuous`.

## The macOS queue exists but jobs sit in "Processing"

The CUPS queue talks to the printer application over `ipp://localhost:8100`.
Check the printer application is answering:

```sh
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8100/
sudo lprint status -d zp450
```

If the daemon is down, `launchctl` will restart it (KeepAlive is set); if it is
crash-looping, the reason will be in `/Library/Logs/lprint-zp450.log`.

Recreate the CUPS queue if its cached capabilities went stale:

```sh
sudo lpadmin -x ZP450
sudo lpadmin -p ZP450 -E -v ipp://localhost:8100/ipp/print/zp450 -m everywhere
```

## The build fails

**Linker error building `libpappl.1.dylib`.** Seen on macOS 26 (Mac Studio):
`make` dies with `clang: error: linker command failed with exit code 1`. That
line is only clang's summary — the cause is the `ld:` line above it, and the
fixes differ completely:

| `ld:` message | Cause |
|---|---|
| `library not found for -lssl` | keg-only `openssl@3` not on the link path |
| `library not found for -lcups` | the SDK no longer supplies what PAPPL expects |
| `symbol(s) not found` | API mismatch between PAPPL and the installed libs |
| `building for macOS-arm64 but attempting to link ... x86_64` | Homebrew architecture mismatch |
| `symbol(s) not found for architecture x86_64` **on an Apple Silicon Mac** | same mismatch, seen from the other side — see below |

**Cross-architecture builds.** On Apple Silicon (every Mac Studio, and all Macs
since 2020), `for architecture x86_64` means the toolchain targeted Intel. The
linker ignores the arm64 libraries it finds and then reports everything in them
as an undefined symbol, which reads like an API problem but is not. Check with:

```sh
uname -m; arch; brew --prefix
```

`arm64` and `/opt/homebrew` are correct. `x86_64` means a Rosetta shell — start
a native one with `arch -arm64 zsh`. A `brew --prefix` of `/usr/local` on Apple
Silicon means Intel Homebrew, whose libraries are x86_64; install the native
Homebrew at `/opt/homebrew`. Either way, delete the half-built tree before
retrying, or stale objects of the wrong architecture linger:

```sh
rm -rf /tmp/zp450-build && ./install.sh
```

`install.sh` now refuses to start when it detects either mismatch.

To capture it, re-run just the failed link — the object files are already
built, so this takes seconds:

```sh
cd /tmp/zp450-build/pappl-1.4.9 && make 2>&1 | tail -30
```

A full `./install.sh` also tees configure and make output to
`/tmp/zp450-build/pappl-{configure,build}.log`.

- `configure: error: ...pkg-config...` — run `brew install pkg-config`.
- OpenSSL not found — `brew install openssl@3`; the build script adds its
  keg-only `pkgconfig` directory to `PKG_CONFIG_PATH` automatically.
- `libusb not found` — `brew install libusb`. Without it PAPPL builds fine but
  cannot talk to USB printers at all.
- Checksum mismatch — the pinned release was re-uploaded or the download was
  corrupted. Verify against the upstream release page before overriding
  `PAPPL_SHA256` / `LPRINT_SHA256`.

## Reporting a problem upstream

Driver-level issues (rendering, EPL2/ZPL output, media handling) belong to
LPrint: <https://github.com/michaelrsweet/lprint/issues>. Include the output of
`sudo lprint devices -o verbose=1` and the LPrint version.

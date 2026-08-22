# Installer package

Builds `ZP450-Installer-<version>.pkg`: a double-clickable macOS installer that
sets up the ZP 450 printer application on a Mac with **no Homebrew, no Xcode
command line tools, and no compiling**.

## Build it

On a Mac that can already build from source (Homebrew + command line tools):

```sh
cd zp450-macos/package
./build-pkg.sh
```

Roughly five minutes, mostly compiling PAPPL. The result lands in
`package/out/`.

## What the package contains

Everything installs under `/usr/local/zp450`, a private prefix that cannot
collide with a from-source install in `/usr/local`:

| Path | Contents |
|---|---|
| `bin/lprint` | the printer application |
| `bin/zp450-setup` | create or recreate the queues (`--epl` / `--zpl`) |
| `bin/zp450-uninstall` | remove queues, daemon and files |
| `lib/` | `libpappl` plus every Homebrew library it needs |
| `share/zp450/` | queue setup, diagnostics, LaunchDaemon template |
| `share/doc/zp450/` | README and troubleshooting guide |

The libraries are the point. A stock Mac has no `openssl@3`, `cups` 2.4,
`libusb`, `libpng` or `jpeg-turbo`, so `build-pkg.sh` copies each one in and
rewrites its load path from `/opt/homebrew/...` to `@rpath` with
`install_name_tool`, walking dependencies transitively — `libcrypto`, for
instance, arrives only because `libssl` needs it. Rewriting invalidates code
signatures, so everything is re-signed afterwards.

Two checks guard against shipping something broken: the bundler refuses to
finish if any binary still references a build-machine path, and `build-pkg.sh`
runs the staged `lprint` before packaging — which only works if `@rpath`
resolution is correct.

## Installing it

Double-click. The installer explains what it does, asks for an admin password,
and creates the queue automatically if the printer is connected.

Because the package is unsigned, Gatekeeper blocks a plain double-click on Macs
other than the one that built it. Either right-click the package and choose
**Open**, or install from Terminal:

```sh
sudo installer -pkg ZP450-Installer-1.0.0.pkg -target /
```

A package meant for wider distribution needs a Developer ID and notarization
(a paid Apple Developer account). To sign, add `--sign "Developer ID Installer:
NAME (TEAMID)"` to the `productbuild` call in `build-pkg.sh`, then run
`xcrun notarytool submit` and `xcrun stapler staple` on the result.

## After installing

- Printer settings: <http://localhost:8100/>
- Queue not created (printer was unplugged): `sudo zp450-setup`
- Blank labels: `sudo zp450-setup --zpl`
- Remove: `sudo zp450-uninstall`
